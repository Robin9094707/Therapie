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

        if let loaded = Self.load(from: dataURL) {
            data = loaded
        } else {
            data = AppData()
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
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

    private static func load(from url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: raw)
    }

    func save() {
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
        isLoading = false
        save()
    }
}

