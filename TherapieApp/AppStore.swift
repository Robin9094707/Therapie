import Foundation
import CoreLocation
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet {
            guard !isLoading else { return }
            save()
            if lastSaveError == nil {
                if !data.aiSettings.enabled && selectedTab == 5 { selectedTab = 4 }
                if AppleReminderSyncPolicy.inputsChanged(from: oldValue, to: data) {
                    AppleRemindersService.shared.refresh(self)
                }
                captureLocations(from: oldValue)
                rememberChange(from: oldValue, to: data)
                TherapyEffects.shared.changed(from: oldValue, to: data)
                var previous = oldValue.schedule, current = data.schedule
                previous.calendarEventIdentifier = nil; current.calendarEventIdentifier = nil
                previous.alarmIDs = []; current.alarmIDs = []
                if previous != current || oldValue.profile != data.profile { refreshTherapyCalendar() }
            }
        }
    }

    @Published var lastSaveError: String?
    @Published private(set) var loadError: String?
    @Published private(set) var waitingForProtectedData = false
    private var initialLoadComplete = false
    private var deferredSave = false
    private var storageFolder = "Therapie"
    private var lastStorageRetry = Date.distantPast
    var storageReady: Bool { initialLoadComplete && !waitingForProtectedData && loadError == nil && UIApplication.shared.isProtectedDataAvailable }
    @Published private(set) var readableFileStatus = "Lesbare Dateien werden vorbereitet."
    @Published var taskReminderStatus = ""
    @Published var notificationTaskID: UUID?
    @Published var openEnergyReview = false
    @Published var notificationSession = false
    @Published var notificationTherapy = false
    @Published var therapyCalendarStatus = ""
    private var calendarRefreshTask: Task<Void, Never>?
    private var lastCalendarRefresh = Date.distantPast
    @Published var notificationMood = false
    @Published var pendingGuidedCheckIn: GuidedCheckIn?
    @Published var notificationAIHub = false
    @Published var visibleAIComposerIDs: Set<UUID> = []
    @Published var activeBuddyVoiceIDs: Set<UUID> = []
    @Published var notificationRoutineID: UUID?
    @Published var routineReminderStatus = ""
    @Published var checkInReminderStatus = ""
    @Published var selectedTab = 0
    @Published var notificationRoutines = false
    @Published var notificationReminders = false
    @Published var notificationShowers = false
    @Published var notificationWidgetSetup = false
    @Published var notificationApplePage: String?
    @Published var appleReminderStatus = "Noch nicht verbunden."
    @Published var widgetStatus = ""
    @Published var routineAlarmStatus = ""
    @Published var undoAvailable = false
    var undoSteps: [AppUndoStep] = []
    var undoExpiryTask: Task<Void, Never>?
    var deferredMediaDeletion: [String: Date] = [:]
    var undoInProgress = false
    private var writeBlocked = false

    private var isLoading = true
    var pendingLocationRecords: [String: Date] = [:]
    lazy var entryLocationService: LocationService = {
        let service = LocationService()
        service.receiveLocation = { [weak self] location in self?.attachLocation(location) }
        return service
    }()
    lazy var aiController = AIBuddyController(store: self)
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
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageFolder = folder
        let root = documents.appendingPathComponent(folder == "Therapie" ? "Therapiedaten" : folder, isDirectory: true)
        rootURL = root
        mediaURL = root.appendingPathComponent("Media", isDirectory: true)
        recordingsURL = root.appendingPathComponent("Recordings", isDirectory: true)
        dataURL = root.appendingPathComponent("therapy-data.json")
        data = AppData()
        loadStoredData()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            writeBlocked = false
            loadError = nil
            waitingForProtectedData = false
            initialLoadComplete = true
            data = AppData()
            if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
                data.profile = UserProfile(userName: "Robin", therapistName: "Therapeutin", onboardingCompleted: true)
                let week = Date().therapyWeek
                data.weeklyTasks = [WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year,
                                               title: "Einen ruhigen Moment festhalten", details: "Ein kleiner Schritt für diese Woche.")]
                data.energyEntries = [EnergyEntry(level: 3, givesEnergy: "Musik und eine Pause", takesEnergy: "", note: "")]
                if ProcessInfo.processInfo.arguments.contains("--personalization-fixture") {
                    let past = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
                    data.notes = [TherapyNote(createdAt: Date(), title: "Heute festgehalten", text: "Ein kleiner guter Moment.", tags: ["Alltag"]), TherapyNote(createdAt: past, title: "Früherer Rückblick", text: "Mein Archiv bleibt erhalten.", tags: [])]
                    let clock = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(-300))
                    data.routines = [DailyRoutine(title: "Mein kleiner Tages-Schritt", times: [RoutineTime(hour: clock.hour!, minute: clock.minute!)])]
                }
                if ProcessInfo.processInfo.arguments.contains("--buddy-fixture") {
                    data.aiSettings.enabled = true
                    let action = AIBuddyAction(kind: .note, title: "Ein guter Moment", text: "Heute tat mir eine Pause gut.", weekdays: [])
                    let reply = AIBuddyReply(title: "Mein kleiner Rückblick", message: "Du hast dir heute Raum für eine Pause gegeben.", sections: [AIBuddySection(heading: "Für die nächste Stunde", text: "Welche Pause möchtest du beibehalten?")], actions: [action], suggestedDays: 7)
                    data.aiMessages = [AIBuddyMessage(role: "assistant", text: reply.journalText, reply: reply, contextStart: Date().addingTimeInterval(-6 * 86400), contextEnd: Date(), model: "Lokale Testdaten")]
                    AIConversationMutation.migrate(&data)
                    selectedTab = 0; notificationAIHub = true
                }
                if ProcessInfo.processInfo.arguments.contains("--buddy-network-fixture") { data.aiSettings.enabled = true; selectedTab = 0; notificationAIHub = !ProcessInfo.processInfo.arguments.contains("--buddy-guided-fixture") }
                if ProcessInfo.processInfo.arguments.contains("--buddy-guided-fixture") { data.aiSettings.enabled = true; pendingGuidedCheckIn = GuidedCheckIn(kind: ProcessInfo.processInfo.arguments.contains("--buddy-therapy-fixture") ? .therapy : .morning) }
                if ProcessInfo.processInfo.arguments.contains("--show-checkin") { pendingGuidedCheckIn = GuidedCheckIn(kind: .morning, mood: 4, batteryPercent: 65, step: 2) }
                if ProcessInfo.processInfo.arguments.contains("--show-checkin-tasks") { pendingGuidedCheckIn = GuidedCheckIn(kind: .morning, step: 5) }
                if ProcessInfo.processInfo.arguments.contains("--show-saved-checkin") {
                    let entry = GuidedCheckIn(kind: .morning, mood: 4, batteryPercent: 70, summary: "Mein gespeicherter Rückblick", tasks: [CheckInTaskDraft(title: "Frühstück vorbereiten", smallStep: "Brot bereitlegen")], isDraft: false, step: 7, moodPercent: 78, energyPoints: [BatteryPoint(title: "Technik", note: "Zeit für mein Hobby")])
                    data.guidedCheckIns = [entry]; pendingGuidedCheckIn = entry
                }
                if ProcessInfo.processInfo.arguments.contains("--show-note") {
                    let imagePath = "Media/ui-photo.png", audioPath = "Recordings/ui-audio.wav"
                    let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAF0lEQVR4nGPM23KHgRBgIqhiVNEAKAIAhtcCFmfRl0oAAAAASUVORK5CYII=")!
                    try? image.write(to: root.appendingPathComponent(imagePath))
                    // One second of unsigned 8-bit PCM: a real playable, non-private audio fixture.
                    var wav = Data("RIFF".utf8)
                    func appendWord(_ value: UInt32, width: Int) { for byte in 0..<width { wav.append(UInt8((value >> (byte * 8)) & 255)) } }
                    appendWord(8036, width: 4); wav.append(Data("WAVEfmt ".utf8)); appendWord(16, width: 4)
                    appendWord(1, width: 2); appendWord(1, width: 2); appendWord(8000, width: 4); appendWord(8000, width: 4)
                    appendWord(1, width: 2); appendWord(8, width: 2); wav.append(Data("data".utf8)); appendWord(8000, width: 4); wav.append(Data(repeating: 128, count: 8000))
                    try? wav.write(to: root.appendingPathComponent(audioPath))
                    data.media = [MediaItem(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, createdAt: Date().addingTimeInterval(-3600), kind: .photo, title: "Testfoto", note: "", tags: [], relativePath: imagePath), MediaItem(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, createdAt: Date().addingTimeInterval(-3600), kind: .audio, title: "Testaufnahme", note: "", tags: [], relativePath: audioPath)]
                }
                if ProcessInfo.processInfo.arguments.contains("--feature-ui-fixture") {
                    // A hosted simulator may launch before protected storage is available.
                    // UI fixtures bypass that wait, so create and validate their own files.
                    do {
                        try fm.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
                    } catch { preconditionFailure("Audio fixture directory: \(error)") }
                    data.suggestionsEnabled = false
                    data.aiSettings.enabled = true
                    data.weeklyTasks.append(WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: "Zweiter Wochen-Schritt", details: "Mehrere Aufgaben", dueDate: Date().addingTimeInterval(3600)))
                    data.therapyTopics = [TherapyTopic(title: "Meine nächste Therapiefrage", isCurrent: true)]
                    data.entryLocations = [EntryLocation(id: "task-" + data.weeklyTasks[0].id.uuidString, capturedAt: Date(), latitude: 52.52, longitude: 13.405, accuracy: 60)]
                    var wav = Data("RIFF".utf8)
                    func word(_ value: UInt32, _ width: Int) { for byte in 0..<width { wav.append(UInt8((value >> (byte * 8)) & 255)) } }
                    word(40036, 4); wav.append(Data("WAVEfmt ".utf8)); word(16, 4); word(1, 2); word(1, 2); word(8000, 4); word(8000, 4); word(1, 2); word(8, 2); wav.append(Data("data".utf8)); word(40000, 4); wav.append(Data(repeating: 128, count: 40000))
                    let path = "Recordings/chat-fixture.wav"
                    do {
                        try wav.write(to: root.appendingPathComponent(path), options: .atomic)
                        _ = try BackupArchive.sourceURL(path, root: root)
                    } catch { preconditionFailure("Audio fixture file: \(error)") }
                    let item = MediaItem(kind: .audio, title: "Chat-Testaudio", note: "Meine gesicherte Audio", tags: ["Chat"], relativePath: path, duration: 5)
                    data.media.append(item)
                    let chatID = AIConversationMutation.create(in: &data)
                    data.aiMessages.append(AIBuddyMessage(role: "user", text: "Meine Audio bleibt abspielbar.", conversationID: chatID, mediaIDs: [item.id]))
                }
                if ProcessInfo.processInfo.arguments.contains("--show-appointments") { notificationTherapy = true }
                if ProcessInfo.processInfo.arguments.contains("--show-routines") {
                    let time = RoutineTime(title: "Morgens", hour: 6, minute: 30, weekendHour: 9, weekendMinute: 0)
                    data.routines = [DailyRoutine(title: "Mein kleiner Morgen-Schritt", symbol: "sun.max.fill", details: "Alles für den Start bereitlegen.", times: [time])]
                }
            }
        }
        isLoading = false
        TaskNotificationCoordinator.shared.attach(self)
        if storageReady {
            if !fm.fileExists(atPath: dataURL.path) { save() } else { refreshReadableFiles(); TaskNotificationCoordinator.shared.refresh(self); TherapyWidgetBridge.refresh(self) }
        }

    }

    private func loadStoredData() {
        guard !initialLoadComplete else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            writeBlocked = true; waitingForProtectedData = true
            return
        }
        let fm = FileManager.default
        do {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let migrated = try AppFileStorage.root(applicationSupport: support, documents: documents, folder: storageFolder)
            guard migrated == rootURL else { throw ServiceError.generic("Der Datenordner konnte nicht eindeutig geöffnet werden.") }
            try BackupArchive.recoverInterruptedRestore(root: rootURL)
            for directory in [rootURL, mediaURL, recordingsURL] {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try BackupArchive.protect(directory)
            }
            let raw: Data?
            do { raw = try Data(contentsOf: dataURL) }
            catch {
                let value = error as NSError
                guard value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoSuchFileError else { throw error }
                raw = nil
            }
            var loaded = AppData()
            if let raw {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                loaded = try decoder.decode(AppData.self, from: raw)
                let version = (try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["schemaVersion"] as? Int ?? 1
                if version < 17 {
                    let beforeUpdate = rootURL.appendingPathComponent("therapy-data.pre-3016.json")
                    if !fm.fileExists(atPath: beforeUpdate.path) { try raw.write(to: beforeUpdate, options: [.atomic, .completeFileProtection]) }
                }
                let snapshot = rootURL.appendingPathComponent("therapy-data.pre-3009.json")
                if version < 11 && !fm.fileExists(atPath: snapshot.path) { try raw.write(to: snapshot, options: [.atomic, .completeFileProtection]) }
            }
            let wasLoading = isLoading; isLoading = true
            data = loaded
            isLoading = wasLoading
            writeBlocked = false; waitingForProtectedData = false
            loadError = nil; lastSaveError = nil; initialLoadComplete = true
            BackupArchive.cleanAbandonedTransfers(root: rootURL)
        } catch {
            writeBlocked = true
            if !UIApplication.shared.isProtectedDataAvailable || AppFileAccess.isTemporaryDenial(error) {
                // Alarm intents can launch before the keybag unlock completes. Retry in place;
                // never replace existing data with a fresh snapshot or ask for a backup here.
                waitingForProtectedData = true; loadError = nil; lastSaveError = nil
            } else {
                waitingForProtectedData = false
                loadError = "Vorhandene Daten konnten nicht sicher geöffnet werden. Die Originaldatei bleibt unverändert. " + error.localizedDescription
                lastSaveError = loadError
            }
        }
    }

    func resumeProtectedStorage() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        if !initialLoadComplete {
            guard loadError == nil, Date().timeIntervalSince(lastStorageRetry) >= 1 else { return }
            lastStorageRetry = Date()
            loadStoredData()
            if storageReady {
                if !FileManager.default.fileExists(atPath: dataURL.path) { save() }
                else { refreshReadableFiles(); TaskNotificationCoordinator.shared.refresh(self); TherapyWidgetBridge.refresh(self) }
            }
        } else if deferredSave {
            waitingForProtectedData = false
            save()
        }
    }

    func refreshTherapyCalendar(force: Bool = true) {
        guard loadError == nil, lastSaveError == nil, data.schedule.calendarEventIdentifier != nil,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              force || Date().timeIntervalSince(lastCalendarRefresh) > 1800 else { return }
        calendarRefreshTask?.cancel()
        calendarRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                let id = try await CalendarSyncService.shared.sync(schedule: data.schedule, profile: data.profile, requestPermission: false)
                data.schedule.calendarEventIdentifier = id
                lastCalendarRefresh = Date()
                therapyCalendarStatus = "Kalender aktualisiert · 26 kommende Termine. Absagen und Urlaub berücksichtigt."
            } catch is CancellationError {} catch { therapyCalendarStatus = "Kalender noch nicht aktualisiert: " + error.localizedDescription }
        }
    }

    func save() {
        guard !writeBlocked, initialLoadComplete else { lastSaveError = loadError; return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            deferredSave = true; waitingForProtectedData = true
            lastSaveError = "Deine Eingabe wartet auf den entsperrten Dateizugriff und wird danach erneut gespeichert."
            return
        }
        do {
            // A deferred first write can run before any data directories exist.
            // Prepare them only after protected data is available, including retries.
            for directory in [rootURL, mediaURL, recordingsURL] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try BackupArchive.protect(directory)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let raw = try encoder.encode(data)
            try raw.write(to: dataURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: dataURL.path
            )
            lastSaveError = nil; deferredSave = false; waitingForProtectedData = false
            TherapyWidgetBridge.refresh(self)
            scheduleAutomaticBackup(snapshot: data)
            refreshReadableFiles()
            TaskNotificationCoordinator.shared.refresh(self)
        } catch {
            deferredSave = AppFileAccess.isTemporaryDenial(error) || !UIApplication.shared.isProtectedDataAvailable
            waitingForProtectedData = deferredSave
            lastSaveError = deferredSave ? "Der Dateizugriff ist kurz gesperrt. Deine Eingabe wird nach dem Entsperren erneut gespeichert." : error.localizedDescription
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
        calendarRefreshTask?.cancel()
        backupWorkItem?.cancel()
        backupWorkItem = nil
        let restored = try BackupService.shared.restore(appRoot: rootURL)
        CalendarSyncService.shared.removeSyncedEvent(identifier: data.schedule.calendarEventIdentifier)
        AlarmService.shared.cancelAllOwnedAlarms()
        RoutineAlarmCoordinator.shared.cancel()
        aiController.cancel()
        clearUndo()
        isLoading = true
        data = restored
        writeBlocked = false
        loadError = nil
        initialLoadComplete = true; waitingForProtectedData = false; deferredSave = false
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
        calendarRefreshTask?.cancel()
        backupWorkItem?.cancel(); backupWorkItem = nil
        readableWorkItem?.cancel(); readableWorkItem = nil
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        var restored = prepared.manifest.data.portableSnapshot
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
        aiController.cancel()
        clearUndo()
        isLoading = true
        data = restored
        writeBlocked = false; loadError = nil; lastSaveError = nil
        initialLoadComplete = true; waitingForProtectedData = false; deferredSave = false
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
        if let existing = MoodDailyPolicy.existing(for: entry, in: data), existing.id != entry.id,
           data.moodCheckIns.first(where: { $0.id == entry.id }).map({ MoodDailyPolicy.sameBucket($0, entry, in: data) }) != true {
            lastSaveError = "Für dieses Zeitfenster gibt es heute bereits einen Stimmungs-Check-in. Öffne ihn zum Bearbeiten oder erlaube zusätzliche Einträge im Check-in-Rhythmus."; return
        }
        var snapshot = data
        var clean = entry
        clean.date = min(clean.date, Date())
        clean.daySlotID = clean.daySlotID ?? MoodDailyPolicy.slot(for: clean, data: data)?.id
        clean.mood = max(1, min(5, clean.mood))
        clean.moodPercent = clean.moodPercent.map { max(0, min(100, $0)) }
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
        for index in snapshot.guidedCheckIns.indices {
            if let position = snapshot.guidedCheckIns[index].energyPoints?.firstIndex(where: { $0.id == clean.id }) {
                snapshot.guidedCheckIns[index].energyPoints?[position] = clean
            }
        }
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
        var clean = note; clean.updatedAt = Date()
        clean.mediaIDs = Array(Set(clean.mediaIDs ?? [])).sorted { $0.uuidString < $1.uuidString }
        var snapshot = data
        snapshot.notes.removeAll { $0.id == note.id }
        clean.tags = AppHashtags.clean(clean.tags, known: AppHashtags.catalog(data))
        snapshot.hashtagCatalog = AppHashtags.catalog(data)
        snapshot.notes.insert(clean, at: 0)
        snapshot.hashtagCatalog = AppHashtags.catalog(snapshot)
        data = snapshot
    }
    func saveMediaDetails(_ item: MediaItem) {
        guard let i = data.media.firstIndex(where: { $0.id == item.id }) else { return }
        var snapshot = data
        var clean = item; clean.tags = AppHashtags.clean(item.tags, known: AppHashtags.catalog(snapshot))
        snapshot.media[i] = clean; snapshot.hashtagCatalog = AppHashtags.catalog(snapshot); data = snapshot
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
        // Keep the binary until the undo window expires. Metadata is removed atomically below.
        var snapshot = data
        snapshot.media.removeAll { $0.id == item.id }
        if snapshot.emergencyPlan.imageID == item.id { snapshot.emergencyPlan.imageID = nil }
        for index in snapshot.guidedCheckIns.indices { snapshot.guidedCheckIns[index].mediaIDs.removeAll { $0 == item.id } }
        for index in snapshot.notes.indices { snapshot.notes[index].mediaIDs?.removeAll { $0 == item.id } }
        data = snapshot
    }

    func resetAllData() {
        aiController.cancel()
        AIBuddyKeychain.remove()
        clearUndo()
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
        initialLoadComplete = true; waitingForProtectedData = false; deferredSave = false
        isLoading = false
        save()
    }
}
