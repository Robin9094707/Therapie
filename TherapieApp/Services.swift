import Foundation
import SwiftUI
import EventKit
import AlarmKit
import AVFoundation
import CoreLocation

@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()
    private let eventStore = EKEventStore()

    private init() {}

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func sync(schedule: TherapySchedule, profile: UserProfile) async throws -> String {
        let granted = try await requestAccess()
        guard granted else { throw ServiceError.permissionDenied("Kalenderzugriff wurde nicht erlaubt.") }

        if let oldIdentifier = schedule.calendarEventIdentifier,
           let oldEvent = eventStore.event(withIdentifier: oldIdentifier) {
            try? eventStore.remove(oldEvent, span: .futureEvents, commit: true)
        }

        guard let start = TherapyDateHelper.nextOccurrence(schedule: schedule) else {
            throw ServiceError.generic("Der nächste Therapietermin konnte nicht berechnet werden.")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = "Autismus-Therapie"
        if !profile.therapistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event.notes = "Therapie mit " + profile.therapistName
        }
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(schedule.durationMinutes * 60))
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        event.alarms = schedule.reminderOffsetsMinutes.map {
            EKAlarm(relativeOffset: TimeInterval(-$0 * 60))
        }

        try eventStore.save(event, span: .futureEvents, commit: true)
        guard let identifier = event.eventIdentifier else {
            throw ServiceError.generic("Der Kalendereintrag wurde erstellt, aber ohne Kennung zurückgegeben.")
        }
        return identifier
    }

    func removeSyncedEvent(identifier: String?) {
        guard let identifier,
              let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .futureEvents, commit: true)
    }
}

struct TherapyAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    let category: String
    let offsetMinutes: Int
}

@MainActor
final class AlarmService {
    static let shared = AlarmService()
    private init() {}

    func requestAuthorization() async throws -> Bool {
        let state = try await AlarmManager.shared.requestAuthorization()
        return state == .authorized
    }

    func replaceAll(schedule: TherapySchedule) async throws -> [String] {
        try cancel(ids: schedule.alarmIDs)

        let authorized = try await requestAuthorization()
        guard authorized else {
            throw ServiceError.permissionDenied("AlarmKit wurde nicht erlaubt.")
        }

        var ids: [String] = []
        guard let nextTherapy = TherapyDateHelper.nextOccurrence(schedule: schedule) else {
            return ids
        }

        for offset in schedule.reminderOffsetsMinutes {
            let reminderDate = nextTherapy.addingTimeInterval(TimeInterval(-offset * 60))
            let comps = Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminderDate)
            guard let weekdayNumber = comps.weekday,
                  let hour = comps.hour,
                  let minute = comps.minute,
                  let weekday = localeWeekday(from: weekdayNumber) else { continue }

            let id = UUID()
            let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly([weekday])
            let relative = Alarm.Schedule.Relative(time: time, repeats: recurrence)
            let presentation = AlarmPresentation(
                alert: AlarmPresentation.Alert(title: "Therapie-Erinnerung")
            )
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: TherapyAlarmMetadata(category: "therapy", offsetMinutes: offset),
                tintColor: .indigo
            )
            let configuration = AlarmManager.AlarmConfiguration<TherapyAlarmMetadata>.alarm(
                schedule: .relative(relative),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            ids.append(id.uuidString)
        }

        if schedule.taskReminderEnabled {
            for weekdayNumber in schedule.taskReminderWeekdays {
                guard let weekday = localeWeekday(from: weekdayNumber) else { continue }
                let id = UUID()
                let time = Alarm.Schedule.Relative.Time(
                    hour: schedule.taskReminderHour,
                    minute: schedule.taskReminderMinute
                )
                let relative = Alarm.Schedule.Relative(
                    time: time,
                    repeats: .weekly([weekday])
                )
                let presentation = AlarmPresentation(
                    alert: AlarmPresentation.Alert(title: "Wochenaufgabe ansehen")
                )
                let attributes = AlarmAttributes(
                    presentation: presentation,
                    metadata: TherapyAlarmMetadata(category: "task", offsetMinutes: 0),
                    tintColor: .teal
                )
                let configuration = AlarmManager.AlarmConfiguration<TherapyAlarmMetadata>.alarm(
                    schedule: .relative(relative),
                    attributes: attributes
                )
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                ids.append(id.uuidString)
            }
        }

        return ids
    }

    func cancel(ids: [String]) throws {
        for string in ids {
            guard let id = UUID(uuidString: string) else { continue }
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    func cancelAllOwnedAlarms() {
        if let alarms = try? AlarmManager.shared.alarms {
            for alarm in alarms {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
        }
    }

    private func localeWeekday(from calendarWeekday: Int) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}

final class BackupService {
    static let shared = BackupService()
    private let bookmarkKey = "therapy.backupFolderBookmark"

    var hasSelectedFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    private init() {}

    func selectFolder(_ url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    func selectedFolderName() -> String? {
        guard let url = try? resolveFolder() else { return nil }
        return url.lastPathComponent
    }

    private func resolveFolder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw ServiceError.generic("Es wurde noch kein Backup-Ordner ausgewählt.")
        }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            try selectFolder(url)
        }
        return url
    }

    func backup(snapshot: AppData, appRoot: URL) throws {
        let folder = try resolveFolder()
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        var operationError: Error?

        NSFileCoordinator().coordinate(
            writingItemAt: folder,
            options: .forMerging,
            error: &coordinatorError
        ) { coordinatedFolder in
            do {
                let backupRoot = coordinatedFolder.appendingPathComponent("Therapie Backup", isDirectory: true)
                let fm = FileManager.default
                try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let raw = try encoder.encode(snapshot)
                try raw.write(to: backupRoot.appendingPathComponent("therapy-data.json"), options: .atomic)

                for directory in ["Media", "Recordings"] {
                    let source = appRoot.appendingPathComponent(directory, isDirectory: true)
                    let target = backupRoot.appendingPathComponent(directory, isDirectory: true)
                    if fm.fileExists(atPath: target.path) {
                        try fm.removeItem(at: target)
                    }
                    if fm.fileExists(atPath: source.path) {
                        try fm.copyItem(at: source, to: target)
                    }
                }
            } catch {
                operationError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let operationError { throw operationError }
    }

    func restore(appRoot: URL) throws -> AppData {
        let folder = try resolveFolder()
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let backupRoot = folder.appendingPathComponent("Therapie Backup", isDirectory: true)
        let dataURL = backupRoot.appendingPathComponent("therapy-data.json")
        let raw = try Data(contentsOf: dataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppData.self, from: raw)

        let fm = FileManager.default
        for directory in ["Media", "Recordings"] {
            let source = backupRoot.appendingPathComponent(directory, isDirectory: true)
            let target = appRoot.appendingPathComponent(directory, isDirectory: true)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: target)
            } else {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            }
        }

        return restored
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

@MainActor
final class AudioRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start(url: URL) async throws {
        let allowed = await requestMicrophonePermission()
        guard allowed else {
            throw ServiceError.permissionDenied("Mikrofonzugriff wurde nicht erlaubt.")
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        isRecording = true
        elapsed = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsed = self?.recorder?.currentTime ?? 0
            }
        }
    }

    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        return duration
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum ServiceError: LocalizedError {
    case permissionDenied(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message), .generic(let message):
            message
        }
    }
}
