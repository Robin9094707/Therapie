import Foundation
import CoreLocation

@MainActor
final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    @Published var lastSaveError: String?
    @Published private(set) var loadError: String?
    private var writeBlocked = false

    private var isLoading = true
    private var backupWorkItem: DispatchWorkItem?

    let rootURL: URL
    let mediaURL: URL
    let recordingsURL: URL
    private let dataURL: URL

    init() {
        let fm = FileManager.default
        let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "TherapieUITests" : "Therapie"
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(folder, isDirectory: true)
        rootURL = root
        mediaURL = root.appendingPathComponent("Media", isDirectory: true)
        recordingsURL = root.appendingPathComponent("Recordings", isDirectory: true)
        dataURL = root.appendingPathComponent("therapy-data.json")

        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: recordingsURL, withIntermediateDirectories: true)

        data = AppData()
        if fm.fileExists(atPath: dataURL.path) {
            do {
                let raw = try Data(contentsOf: dataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                data = try decoder.decode(AppData.self, from: raw)
                let version = (try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["schemaVersion"] as? Int ?? 1
                let snapshot = root.appendingPathComponent("therapy-data.pre-3000.json")
                if version < 3 && !fm.fileExists(atPath: snapshot.path) {
                    try raw.write(to: snapshot, options: [.atomic, .completeFileProtection])
                }
            } catch {
                writeBlocked = true
                loadError = "Vorhandene Daten konnten nicht sicher geöffnet werden. Die Originaldatei bleibt unverändert. Bitte stelle ein gültiges Backup wieder her. " + error.localizedDescription
                lastSaveError = loadError
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            writeBlocked = false
            loadError = nil
            data = AppData()
            if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
                data.profile = UserProfile(userName: "Robin", therapistName: "Therapeutin", onboardingCompleted: true)
                let week = Date().therapyWeek
                data.weeklyTasks = [WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year,
                                               title: "Einen ruhigen Moment festhalten", details: "Ein kleiner Schritt für diese Woche.")]
                data.energyEntries = [EnergyEntry(level: 3, givesEnergy: "Musik und eine Pause", takesEnergy: "", note: "")]
            }
        }
        isLoading = false
    }

    func save() {
        guard !writeBlocked else { lastSaveError = loadError; return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let raw = try encoder.encode(data)
            try raw.write(to: dataURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: dataURL.path
            )
            lastSaveError = nil
            scheduleAutomaticBackup(snapshot: data)
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private func scheduleAutomaticBackup(snapshot: AppData) {
        guard data.preferences.autoBackupToSelectedFolder,
              BackupService.shared.hasSelectedFolder else { return }

        backupWorkItem?.cancel()
        let root = rootURL
        let work = DispatchWorkItem {
            try? BackupService.shared.backup(snapshot: snapshot, appRoot: root)
        }
        backupWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func backupNow() throws {
        try BackupService.shared.backup(snapshot: data, appRoot: rootURL)
    }

    func restoreFromBackup() throws {
        let restored = try BackupService.shared.restore(appRoot: rootURL)
        isLoading = true
        data = restored
        writeBlocked = false
        loadError = nil
        isLoading = false
        save()
    }

    func addWeeklyTask(title: String, details: String) {
        let w = Date().therapyWeek
        data.weeklyTasks.insert(
            WeeklyTask(weekOfYear: w.week, yearForWeekOfYear: w.year, title: title, details: details),
            at: 0
        )
    }

    func addNote(title: String, text: String, tags: [String]) {
        data.notes.insert(TherapyNote(title: title, text: text, tags: tags), at: 0)
    }

    func addEnergy(level: Int, gives: String, takes: String, note: String) {
        data.energyEntries.insert(
            EnergyEntry(level: level, givesEnergy: gives, takesEnergy: takes, note: note),
            at: 0
        )
    }

    func saveCheckIn(_ entry: MoodCheckIn, points: [BatteryPoint]) {
        var snapshot = data
        var clean = entry
        clean.date = min(clean.date, Date())
        clean.mood = max(1, min(5, clean.mood))
        clean.battery = max(1, min(5, clean.battery))
        clean.stress = clean.stress.map { max(1, min(5, $0)) }
        clean.sensoryLoad = clean.sensoryLoad.map { max(1, min(5, $0)) }
        clean.sleepHours = clean.sleepHours.map { max(0, min(24, $0)) }
        snapshot.moodCheckIns.removeAll { $0.id == clean.id }
        snapshot.moodCheckIns.insert(clean, at: 0)
        snapshot.batteryPoints.removeAll { $0.checkInID == clean.id }
        snapshot.batteryPoints += points.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            var point = $0
            point.title = point.title.trimmingCharacters(in: .whitespacesAndNewlines)
            point.checkInID = clean.id
            point.date = clean.date
            point.impact = max(1, min(5, point.impact))
            return point
        }
        data = snapshot
    }

    func saveBatteryPoint(_ point: BatteryPoint) {
        guard !point.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var snapshot = data
        var clean = point
        clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.date = min(clean.date, Date())
        clean.impact = max(1, min(5, clean.impact))
        snapshot.batteryPoints.removeAll { $0.id == clean.id }
        snapshot.batteryPoints.insert(clean, at: 0)
        data = snapshot
    }

    func saveWeekReview(_ review: WeekReview) {
        var snapshot = data
        var clean = review
        clean.weekStart = min(clean.weekStart, Date()).therapyWeekStart
        snapshot.weekReviews.removeAll { $0.id == clean.id || $0.weekStart == clean.weekStart }
        snapshot.weekReviews.insert(clean, at: 0)
        data = snapshot
    }

    func deleteCheckIn(_ entry: MoodCheckIn) {
        var snapshot = data
        snapshot.moodCheckIns.removeAll { $0.id == entry.id }
        snapshot.batteryPoints.removeAll { $0.checkInID == entry.id }
        data = snapshot
    }

    func exportWellnessCSV(period: WellnessPeriod) throws -> URL {
        let directory = rootURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Therapie-Auswertung-\(UUID().uuidString).csv")
        try Data(WellnessExport.csv(data, period: period).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func addReflection(summary: String, helped: String, nextFocus: String, date: Date = Date()) {
        data.reflections.insert(
            TherapySessionReflection(date: date, summary: summary, whatHelped: helped, nextFocus: nextFocus),
            at: 0
        )
    }

    func importPhoto(
        bytes: Data,
        fileExtension: String,
        title: String,
        note: String,
        tags: [String],
        location: CLLocation?
    ) throws {
        let ext = fileExtension.isEmpty ? "jpg" : fileExtension
        let fileName = UUID().uuidString + "." + ext
        let url = mediaURL.appendingPathComponent(fileName)
        try bytes.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )

        data.media.insert(
            MediaItem(
                kind: .photo,
                title: title.isEmpty ? "Therapie-Foto" : title,
                note: note,
                tags: tags,
                relativePath: "Media/" + fileName,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            ),
            at: 0
        )
    }

    func importDocument(from sourceURL: URL, title: String, tags: [String]) throws {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "file" : sourceURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destination = mediaURL.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        data.media.insert(
            MediaItem(
                kind: .document,
                title: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
                note: "",
                tags: tags,
                relativePath: "Media/" + fileName
            ),
            at: 0
        )
    }

    func newRecordingURL() -> URL {
        recordingsURL.appendingPathComponent(UUID().uuidString + ".m4a")
    }

    func commitRecording(url: URL, duration: TimeInterval, title: String, tags: [String]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        data.media.insert(
            MediaItem(
                kind: .audio,
                title: title.isEmpty ? "Sprachnotiz" : title,
                note: "",
                tags: tags,
                relativePath: "Recordings/" + url.lastPathComponent,
                duration: duration
            ),
            at: 0
        )
    }

    func fileURL(for item: MediaItem) -> URL {
        rootURL.appendingPathComponent(item.relativePath)
    }

    func deleteMedia(_ item: MediaItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        data.media.removeAll { $0.id == item.id }
    }

    func resetAllData() {
        backupWorkItem?.cancel()
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        isLoading = true
        data = AppData()
        writeBlocked = false
        loadError = nil
        isLoading = false
        save()
    }
}
