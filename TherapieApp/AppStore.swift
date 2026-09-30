import Foundation
import CoreLocation

@MainActor
final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet {
            guard !isLoading else { return }
            save()
            if lastSaveError == nil { TherapyEffects.shared.changed(from: oldValue, to: data) }
        }
    }

    @Published var lastSaveError: String?
    @Published private(set) var loadError: String?
    @Published private(set) var readableFileStatus = "Lesbare Dateien werden vorbereitet."
    @Published var taskReminderStatus = ""
    @Published var notificationTaskID: UUID?
    @Published var openEnergyReview = false
    @Published var pendingGuidedCheckIn: GuidedCheckIn?
    @Published var notificationRoutineID: UUID?
    @Published var routineReminderStatus = ""
    @Published var routineAlarmStatus = ""
    private var writeBlocked = false

    private var isLoading = true
    lazy var sessionController = TherapySessionController(store: self)
    private var backupWorkItem: DispatchWorkItem?
    private var readableWorkItem: DispatchWorkItem?

    let rootURL: URL
    let mediaURL: URL
    let recordingsURL: URL
    private let dataURL: URL

    init() {
        let fm = FileManager.default
        let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "TherapieUITests" : "Therapie"
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root: URL
        let migrationFailure: String?
        do { root = try AppFileStorage.root(applicationSupport: support, documents: documents, folder: folder); migrationFailure = nil }
        catch { root = support.appendingPathComponent(folder); migrationFailure = error.localizedDescription }
        rootURL = root
        mediaURL = root.appendingPathComponent("Media", isDirectory: true)
        recordingsURL = root.appendingPathComponent("Recordings", isDirectory: true)
        dataURL = root.appendingPathComponent("therapy-data.json")

        let recoveryFailure: String?
        do { try BackupArchive.recoverInterruptedRestore(root: root); recoveryFailure = migrationFailure }
        catch { recoveryFailure = error.localizedDescription }
        BackupArchive.cleanAbandonedTransfers(root: root)
        if recoveryFailure == nil { try? fm.createDirectory(at: root, withIntermediateDirectories: true) }
        if recoveryFailure == nil {
            try? fm.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            try? fm.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
            for directory in [root, mediaURL, recordingsURL] { try? BackupArchive.protect(directory) }
        }

        data = AppData()
        var refreshLegacyAlarms = false
        if let recoveryFailure {
            writeBlocked = true
            loadError = "Eine unterbrochene Wiederherstellung konnte nicht abgeschlossen werden. Die vorherige Sicherung bleibt erhalten. " + recoveryFailure
            lastSaveError = loadError
        }
        if fm.fileExists(atPath: dataURL.path) {
            do {
                let raw = try Data(contentsOf: dataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                data = try decoder.decode(AppData.self, from: raw)
                let version = (try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["schemaVersion"] as? Int ?? 1
                refreshLegacyAlarms = version < 6 && !data.schedule.alarmIDs.isEmpty
                let snapshot = root.appendingPathComponent("therapy-data.pre-3004.json")
                if version < 7 && !fm.fileExists(atPath: snapshot.path) {
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
                if ProcessInfo.processInfo.arguments.contains("--show-checkin") { pendingGuidedCheckIn = GuidedCheckIn(kind: .morning, mood: 4, batteryPercent: 65, step: 2) }
                if ProcessInfo.processInfo.arguments.contains("--show-routines") {
                    let time = RoutineTime(title: "Morgens", hour: 6, minute: 30, weekendHour: 9, weekendMinute: 0)
                    data.routines = [DailyRoutine(title: "Mein kleiner Morgen-Schritt", symbol: "sun.max.fill", details: "Alles für den Start bereitlegen.", times: [time])]
                }
            }
        }
        isLoading = false
        TaskNotificationCoordinator.shared.attach(self)
        if loadError == nil {
            if !fm.fileExists(atPath: dataURL.path) { save() } else { refreshReadableFiles(); TaskNotificationCoordinator.shared.refresh(self) }
        }
        if refreshLegacyAlarms && loadError == nil {
            Task {
                do { data.schedule.alarmIDs = try await AlarmService.shared.replaceAll(schedule: data.schedule) }
                catch { taskReminderStatus = "Bitte aktualisiere deine AlarmKit-Erinnerungen im Kalender: " + error.localizedDescription }
            }
        }
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
            refreshReadableFiles()
            TaskNotificationCoordinator.shared.refresh(self)
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private func scheduleAutomaticBackup(snapshot: AppData) {
        backupWorkItem?.cancel()
        backupWorkItem = nil
        guard data.preferences.autoBackupToSelectedFolder,
              BackupService.shared.hasSelectedFolder else { return }

        let root = rootURL
        let work = DispatchWorkItem {
            try? BackupService.shared.backup(snapshot: snapshot, appRoot: root)
        }
        backupWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func refreshReadableFiles() {
        guard !writeBlocked, lastSaveError == nil else { return }
        readableWorkItem?.cancel()
        let snapshot = data, root = rootURL, preferences = PortablePreferences.capture()
        let work = DispatchWorkItem { [weak self] in
            BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
            do {
                try ReadableBackup.writeEntries(data: snapshot, root: root, preferences: preferences)
                Task { @MainActor in self?.readableFileStatus = "Lesbare Dateien sind aktualisiert." }
            } catch { Task { @MainActor in self?.readableFileStatus = "Lesbare Dateien konnten nicht aktualisiert werden: " + error.localizedDescription } }
        }
        readableWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func backupNow() throws {
        guard !writeBlocked else { throw ServiceError.generic("Solange vorhandene Daten nicht sicher geladen sind, wird kein Backup überschrieben. Bitte verwende Wiederherstellen.") }
        try BackupService.shared.backup(snapshot: data, appRoot: rootURL)
    }

    func restoreFromBackup() throws {
        backupWorkItem?.cancel()
        backupWorkItem = nil
        let restored = try BackupService.shared.restore(appRoot: rootURL)
        RoutineAlarmCoordinator.shared.cancel()
        isLoading = true
        data = restored
        writeBlocked = false
        loadError = nil
        isLoading = false
        save()
    }

    func exportSnapshot() throws -> AppData {
        guard !writeBlocked, lastSaveError == nil else {
            throw ServiceError.generic("Bitte behebe zuerst den Speicherfehler oder importiere eine gültige Sicherung. Ungeladene Daten werden nicht exportiert.")
        }
        return data
    }

    func installBackup(_ prepared: PreparedBackup) throws {
        backupWorkItem?.cancel(); backupWorkItem = nil
        readableWorkItem?.cancel(); readableWorkItem = nil
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        var restored = prepared.manifest.data
        // OS identifiers and security-scoped bookmarks belong to this device.
        restored.schedule.calendarEventIdentifier = nil
        restored.schedule.alarmIDs = []
        try BackupArchive.encoder().encode(restored).write(to: prepared.directory.appendingPathComponent("therapy-data.json"), options: .atomic)
        try BackupArchive.protect(prepared.directory.appendingPathComponent("therapy-data.json"))
        try BackupArchive.install(directory: prepared.directory, root: rootURL)
        CalendarSyncService.shared.removeSyncedEvent(identifier: data.schedule.calendarEventIdentifier)
        RoutineAlarmCoordinator.shared.cancel()
        AlarmService.shared.cancelAllOwnedAlarms()
        WeeklyReminderService.cancel()
        BackupService.shared.clearFolder()
        prepared.manifest.preferences.apply()
        isLoading = true
        data = restored
        writeBlocked = false; loadError = nil; lastSaveError = nil
        isLoading = false
        TherapyEffects.shared.light()
        sessionController.restoredData()
        refreshReadableFiles()
        TaskNotificationCoordinator.shared.refresh(self)
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

    func toggleTask(_ id: UUID) {
        guard let i = data.weeklyTasks.firstIndex(where: { $0.id == id }) else { return }
        var snapshot = data
        snapshot.weeklyTasks[i].toggleCompletion()
        if snapshot.weeklyTasks[i].completed { snapshot.weeklyTasks[i].reminderShiftedAt = nil }
        data = snapshot
        if !snapshot.weeklyTasks[i].completed { TherapyEffects.shared.light() }
    }

    func postponeTask(_ id: UUID, minutes: Int) {
        guard let index = data.weeklyTasks.firstIndex(where: { $0.id == id }) else { return }
        var snapshot = data
        TaskReminderPlanner.postpone(&snapshot.weeklyTasks[index], schedule: snapshot.schedule, minutes: minutes)
        data = snapshot
        TherapyEffects.shared.light()
    }

    func saveEnergyReview(_ entry: WeeklyEnergyReview) {
        var clean = entry
        clean.periodEnd = Calendar.therapyCalendar.startOfDay(for: min(entry.periodEnd, Date()))
        clean.energy = max(1, min(5, clean.energy))
        func normalized(_ points: [WeeklyEnergyFactor]) -> [WeeklyEnergyFactor] {
            points.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { value in
                var point = value; point.title = point.title.trimmingCharacters(in: .whitespacesAndNewlines); point.impact = max(1, min(5, point.impact)); return point
            }
        }
        clean.gives = normalized(clean.gives)
        clean.takes = normalized(clean.takes)
        var snapshot = data
        snapshot.weeklyEnergyReviews.removeAll { $0.id == clean.id || Calendar.therapyCalendar.isDate($0.periodEnd, inSameDayAs: clean.periodEnd) }
        snapshot.weeklyEnergyReviews.insert(clean, at: 0)
        data = snapshot
    }

    func saveFolder(_ folder: TherapyFolder) {
        guard !folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let descendants = TherapyHierarchy.descendants(of: folder.id, folders: data.therapyFolders)
        guard folder.parentID != folder.id, folder.parentID.map({ !descendants.contains($0) }) ?? true else { return }
        var snapshot = data
        snapshot.therapyFolders.removeAll { $0.id == folder.id }
        snapshot.therapyFolders.append(folder)
        data = snapshot
    }
    func saveTopic(_ topic: TherapyTopic) {
        var clean = topic
        clean.priority = max(1, min(3, clean.priority))
        if clean.status == .completed { clean.isCurrent = false }
        var snapshot = data
        snapshot.therapyTopics.removeAll { $0.id == clean.id }
        snapshot.therapyTopics.insert(clean, at: 0)
        data = snapshot
    }
    func saveGoal(_ goal: TherapyGoal) {
        var clean = goal
        clean.progress = max(0, min(100, clean.progress))
        if clean.status == .completed { clean.progress = 100 }
        var snapshot = data
        snapshot.therapyGoals.removeAll { $0.id == clean.id }
        snapshot.therapyGoals.insert(clean, at: 0)
        data = snapshot
    }
    func saveNote(_ note: TherapyNote) {
        var snapshot = data
        snapshot.notes.removeAll { $0.id == note.id }
        snapshot.notes.insert(note, at: 0)
        data = snapshot
    }
    func saveMediaDetails(_ item: MediaItem) {
        guard let i = data.media.firstIndex(where: { $0.id == item.id }) else { return }
        data.media[i] = item
    }
    func saveSessionTemplate(_ template: TherapySessionTemplate) {
        guard template.isValid else { return }
        var snapshot = data
        snapshot.sessionTemplates.removeAll { $0.id == template.id }
        snapshot.sessionTemplates.append(template)
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
        try BackupArchive.protect(destination)

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
        var snapshot = data
        snapshot.media.removeAll { $0.id == item.id }
        for index in snapshot.guidedCheckIns.indices { snapshot.guidedCheckIns[index].mediaIDs.removeAll { $0 == item.id } }
        data = snapshot
    }

    func resetAllData() {
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        backupWorkItem?.cancel()
        readableWorkItem?.cancel()
        TaskNotificationCoordinator.shared.cancel()
        RoutineAlarmCoordinator.shared.cancel()
        let oldRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "TherapieUITests" : "Therapie")
        if oldRoot != rootURL { try? FileManager.default.removeItem(at: oldRoot) }
        try? FileManager.default.removeItem(at: BackupArchive.recoveryURL(oldRoot))
        try? FileManager.default.removeItem(at: BackupArchive.recoveryURL(rootURL))
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
