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

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    private let ownershipKey = "therapy.calendar.events"

    func sync(schedule: TherapySchedule, profile: UserProfile, requestPermission: Bool = true) async throws -> String {
        if requestPermission { guard try await requestAccess() else { throw ServiceError.permissionDenied("Kalenderzugriff wurde nicht erlaubt.") } }
        guard hasAccess else { throw ServiceError.permissionDenied("Bitte vollen Kalenderzugriff erlauben. Änderungen konnten noch nicht synchronisiert werden.") }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { throw ServiceError.generic("Kein beschreibbarer Kalender verfügbar.") }
        // Individual, bounded appointments: exclusions cannot leave an endless recurring alert behind.
        let dates = TherapyDateHelper.occurrences(schedule: schedule, count: 26)
        guard !dates.isEmpty else { throw ServiceError.generic("Kein nächster Therapietermin gefunden.") }
        var created: [EKEvent] = []
        let owned = UserDefaults.standard.stringArray(forKey: ownershipKey) ?? []
        do {
            for date in dates {
                let event = EKEvent(eventStore: eventStore)
                event.title = "Therapie"; event.location = schedule.location; event.calendar = calendar
                var notes: [String] = []
                if !profile.therapistName.isEmpty { notes.append("Therapie mit " + profile.therapistName) }
                if let preparation = schedule.preparation, !preparation.isEmpty { notes.append("Vorbereitung: " + preparation) }
                event.notes = notes.joined(separator: "\n")
                event.startDate = date; event.endDate = date.addingTimeInterval(Double(max(1, schedule.durationMinutes)) * 60)
                event.alarms = Set(schedule.reminderOffsetsMinutes).filter { (0...10080).contains($0) }.map { EKAlarm(relativeOffset: -Double($0) * 60) }
                try eventStore.save(event, span: .thisEvent, commit: false); created.append(event)
            }
            var identifiers = Set(owned)
            if let legacy = schedule.calendarEventIdentifier { identifiers.insert(legacy) }
            for id in identifiers { if let event = eventStore.event(withIdentifier: id) { try eventStore.remove(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent, commit: false) } }
            try eventStore.commit()
        } catch { eventStore.reset(); throw error }
        let ids = created.compactMap(\.eventIdentifier)
        UserDefaults.standard.set(ids, forKey: ownershipKey)
        guard let first = ids.first else { throw ServiceError.generic("Kalender wurde gespeichert, aber ohne Kennungen zurückgegeben.") }
        return first
    }
    func removeSyncedEvent(identifier: String?) {
        var identifiers = Set(UserDefaults.standard.stringArray(forKey: ownershipKey) ?? [])
        if let identifier { identifiers.insert(identifier) }
        var retained: [String] = []
        for id in identifiers {
            if let event = eventStore.event(withIdentifier: id) {
                do { try eventStore.remove(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent, commit: true) }
                catch { retained.append(id) }
            }
        }
        UserDefaults.standard.set(retained, forKey: ownershipKey)
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

    func cancel(ids: [String]) throws {
        let live = Set(try AlarmManager.shared.alarms.map(\.id))
        var firstError: Error?
        for raw in ids {
            guard let id = UUID(uuidString: raw), live.contains(id) else { continue }
            do { try AlarmManager.shared.cancel(id: id) } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }

    func cancelAllOwnedAlarms() {
        if let alarms = try? AlarmManager.shared.alarms {
            for alarm in alarms {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
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
            options: [],
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
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            try selectFolder(url)
        }
        return url
    }

    func backup(snapshot: AppData, appRoot: URL) throws {
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
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
                let raw = try encoder.encode(snapshot.portableSnapshot)
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
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        let folder = try resolveFolder()
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let backupRoot = folder.appendingPathComponent("Therapie Backup", isDirectory: true)
        let dataURL = backupRoot.appendingPathComponent("therapy-data.json")
        let raw = try Data(contentsOf: dataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppData.self, from: raw).portableSnapshot

        let fm = FileManager.default
        let staged = try BackupArchive.privateDirectory()
        defer { try? fm.removeItem(at: staged) }
        for directory in ["Media", "Recordings"] {
            try fm.createDirectory(at: staged.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        for item in restored.media {
            try BackupArchive.validatePath(item.relativePath)
            if item.attachmentOmitted == true { continue }
            let source = try BackupArchive.sourceURL(item.relativePath, root: backupRoot)
            let target = staged.appendingPathComponent(item.relativePath)
            try fm.copyItem(at: source, to: target)
            try BackupArchive.protect(target)
        }
        try BackupArchive.encoder().encode(restored).write(to: staged.appendingPathComponent("therapy-data.json"), options: .atomic)
        try BackupArchive.protect(staged.appendingPathComponent("therapy-data.json"))
        try BackupArchive.install(directory: staged, root: appRoot)
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
        try Task.checkCancellation()
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
        guard recorder.record() else { try? session.setActive(false); throw ServiceError.generic("Die Aufnahme konnte nicht gestartet werden.") }
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
