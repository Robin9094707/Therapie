import Foundation
import CryptoKit

@main
struct BackupChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static let password = "Kaffee ☕ und sichere Therapie 2026!"
    static func expect(_ value: @autoclosure () throws -> Bool, _ text: String) throws {
        count += 1; if try !value() { throw Failure.assertion(text) }
    }
    static func rejects(_ text: String, _ work: () throws -> Void) throws {
        do { try work() } catch { count += 1; return }
        throw Failure.assertion(text)
    }
    static func json(_ data: AppData) throws -> NSDictionary {
        try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(data)) as! NSDictionary
    }
    static func malicious(_ manifest: BackupManifest, at url: URL) throws {
        let salt = Data(repeating: 42, count: 16)
        let header = BackupArchive.magic + BackupArchive.integer(BackupArchive.rounds) + salt
        let key = try BackupArchive.deriveKey(password: password, salt: salt, iterations: BackupArchive.rounds)
        FileManager.default.createFile(atPath: url.path, contents: header)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        try output.seekToEnd()
        var sequence: UInt64 = 0
        try BackupArchive.seal(BackupArchive.encoder().encode(manifest), to: output, key: key, header: header, sequence: &sequence)
        try BackupArchive.seal(BackupArchive.endMarker, to: output, key: key, header: header, sequence: &sequence)
    }
    static func main() throws {
        let fm = FileManager.default, base = try BackupArchive.privateDirectory()
        defer { try? fm.removeItem(at: base) }
        let root = base.appendingPathComponent("Therapie")
        for directory in ["Media", "Recordings"] { try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true) }
        var data = AppData()
        let supportClock = Date(timeIntervalSince1970: 1_790_000_000)
        data.medicalPass = MedicalPass(name: "Testpass", birthDate: Date(timeIntervalSince1970: 946684800), heightCM: 172, medications: "Eigene Angaben", allergies: "Test", contacts: "Kontakt")
        data.appleIntegration = AppleIntegrationPreferences(remindersEnabled: true, removeFinishedReminders: false, privateReminderTitles: false, alarmDelayMinutes: 15)
        let wake = WakeAlarm(title: "Testwecker", excludedDays: [supportClock], challenge: .steps)
        data.wakeAlarms = [wake]
        data.wakeRuns = [WakeRun(id: "wake-test", alarmID: wake.id, scheduledAt: supportClock, outcome: .completed, snoozes: 2, emergencySnoozeUsed: true, operandA: 7, operandB: 4)]
        data.copingMethods = [.asmrExample, .thoughtStopExample]
        for index in data.copingMethods.indices { data.copingMethods[index].createdAt = supportClock; data.copingMethods[index].updatedAt = supportClock }
        data.emergencyPlan = PersonalEmergencyPlan(firstStep: "Reize reduzieren", steps: ["Eine Pause machen"], support: "Meine eigene Kontaktperson", methodIDs: [data.copingMethods[0].id], updatedAt: supportClock)
        data.emergencyPlan.panels = [EmergencyPanel(title: "Stopp", text: "Pause", methodID: data.copingMethods[1].id)]
        data.groundingPractices = [GroundingPractice(date: supportClock, answers: [["Fenster"], ["Boden"], [], [], []], note: "In meinem Tempo")]
        data.showerEntries = [ShowerEntry(date: supportClock, note: "Flexibel")]
        data.showerPreferences.weeklyGoal = 2
        data.dashboard.welcomeMessage = "Ein kleiner Schritt reicht."
        data.dashboard.showFeatureLinks = false
        data.dashboard.cardOrder = ["routines", "appointment", "checkIns"]
        data.dashboard.hiddenCards = ["welcome"]
        data.dashboard.pinnedCards = ["routines"]
        data.dashboard.pinnedRecordIDs = ["note-backup-test"]
        data.dashboard.showWidgetTitles = true
        data.archivePreferences = ArchivePreferences(grouping: .year, oldestFirst: true)
        data.profile = UserProfile(userName: "Robin", therapistName: "Therapeutin", onboardingCompleted: true)
        let routine = DailyRoutine(title: "Frühstück", symbol: "fork.knife", goalID: nil, times: [RoutineTime(title: "Vor der Arbeit", weekdays: [2, 3, 4, 5, 6], hour: 6, minute: 15, weekendHour: 9, weekendMinute: 0)], urgentAlarm: true)
        data.routines = [routine]
        data.routines[0].repeatEveryDays = 2
        data.routineDeferrals = [RoutineDeferral(routineID: routine.id, timeID: routine.times[0].id, scheduledAt: supportClock, deferredUntil: supportClock.addingTimeInterval(86400), createdAt: supportClock)]
        data.routineCompletions = [RoutineCompletion(routineID: routine.id, timeID: routine.times[0].id, scheduledAt: Date(), outcome: .skipped, note: "Pause", routineTitle: "Frühstück", timeTitle: "Vor der Arbeit", corrections: [RoutineCorrection(previousOutcome: .done, previousNote: "", outcome: .skipped, note: "Pause", reason: "Falsche Angabe")])]
        data.routineSnoozes = [RoutineSnooze(id: "portable-occurrence", until: Date())]
        data.guidedCheckIns = [GuidedCheckIn(kind: .therapy, mood: 4, batteryPercent: 0, stress: 2, sensoryLoad: 3, sleepHours: 7.5, summary: "Geführter Rückblick", therapyQuestion: "Was hilft?", tasks: [CheckInTaskDraft(title: "Erster Schritt", source: "Aus der Therapie")], isDraft: false)]
        data.companionSettings = CompanionSettings(vacationUntil: Date(), privateRoutineTitles: false, offerTherapyCheckIn: true, checkInReminders: [CheckInReminder(kind: .morning, time: RoutineTime(weekdays: [2, 3, 4, 5, 6], hour: 6, minute: 30, weekendHour: 9, weekendMinute: 0))])
        data.aiSettings.enabled = true; data.aiSettings.model = "gpt-6-luna"; data.aiSettings.contextDays = 14; data.aiSettings.allowVoiceUploads = true
        data.aiMessages = [AIBuddyMessage(role: "assistant", text: "Mein Rückblick", reply: AIBuddyReply(title: "Meine Woche", message: "Eine gute Pause", sections: [], actions: [AIBuddyAction(kind: .note, title: "Gedanke", text: "Gut", weekdays: [])], suggestedDays: 14))]
        AIConversationMutation.migrate(&data)
        data.aiConversations[0].contextDays = 14
        data.aiConversations[0].draftText = "Noch nicht gesendeter Gedanke"
        data.accentTheme = .purple
        data.wellbeingPreferences.estimateBattery = true; data.wellbeingPreferences.hourlyDecline = 2
        data.aiSettings.speakReplies = true
        data.aiConversations[0].memory = "Familie und Pausen; eine Aufgabe nur vorgeschlagen"
        data.aiConversations[0].tags = ["Familie", "Erholung"]
        data.aiConversations[0].sessionID = routine.id
        data.guidedCheckIns[0].conversationTranscript = "Du: Meine Schwester hilft."
        data.guidedCheckIns[0].satisfaction = 4
        data.aiMessages[0].reply?.memory = "Notiz"
        data.aiMessages[0].reply?.tags = ["Familie"]
        data.aiMessages[0].reply?.quickReplies = [BuddyQuickReply(title: "Ruhe", text: "Ich brauche jetzt Ruhe.")]
        data.aiSettings.weeklyReviewEnabled = true
        data.aiSettings.lastWeeklyReview = Date(timeIntervalSince1970: 1_780_000_000)
        data.aiSettings.lastWeeklyReviewAttempt = data.aiSettings.lastWeeklyReview
        data.editorDrafts = [try AppEditorDraft.make(TherapyNote(title: "Entwurfsnotiz", text: "Mein nicht verlorener Entwurf", tags: ["Familie"]), id: UUID(), kind: "note", title: "Entwurfsnotiz")]
        data.routines[0].recurrenceAnchor = Date(timeIntervalSince1970: 1_770_000_000)
        data.routines[0].repeatEveryWeeks = 2
        data.routines[0].endsAt = Date(timeIntervalSince1970: 1_880_000_000)
        data.hashtagCatalog = ["Familie", "Technik"]
        data.guidedCheckIns[0].tags = ["Familie"]
        data.therapyDiscussionAcknowledgedIDs = ["guided-discussed"]
        data.schedule.recurrence = TherapyRecurrence(interval: 2, additionalWeeklySlots: [TherapyWeeklySlot(weekday: 5, hour: 10)])
        data.schedule.extraAppointments = [TherapyExtraAppointment(title: "Zusatzgespräch")]
        data.companionSettings.allowMultipleCheckInsPerSlot = false; data.companionSettings.alarmShowsActualTitles = true
        data.schedule.alarmIDs = ["local-device-only"]
        data.preferences.includeLocationForNewMedia = false
        data.schedule.location = "Praxis"
        data.schedule.preparation = "Kaffee vorbereiten"
        data.reminderPreferences = ReminderPreferences(privateTaskTitles: false, taskSound: false, energyReviewEnabled: true, energyReviewMinutesBeforeTherapy: 45)
        data.weeklyEnergyReviews = [WeeklyEnergyReview(energy: 4, gives: [WeeklyEnergyFactor(title: "Freunde", impact: 4, category: .people)], takes: [WeeklyEnergyFactor(title: "Viele Termine", impact: 2, category: .work)], nextStep: "Pause einplanen", therapyQuestion: "Besprechen")]
        let folder = TherapyFolder(title: "Autismus")
        data.therapyFolders = [folder]
        let topic = TherapyTopic(title: "Reizregulation")
        data.therapyTopics = [topic]
        data.therapyGoals = [TherapyGoal(title: "Pausen", priority: "high")]
        data.notes = [TherapyNote(title: "PRIVATE-NOTE-DO-NOT-LEAK", text: "Wichtig für mich", tags: ["Privat"], folderID: folder.id, topicID: topic.id, author: "Therapeutin", isImportant: true, conversationID: data.aiConversations[0].id, conversationTranscript: "Du: Meine Schwester hilft. Begleiter: Eine Pause planen.")]
        let week = Date().therapyWeek
        data.weeklyTasks = [WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: "Aufgabe", details: "Wieder aufnehmen", completed: true, completedAt: Date(), topicID: topic.id, reminder: TaskReminder(), dueDate: Date(), smallStep: "Einmal probieren", support: "Zusammen", progress: 80, reminderShiftedAt: Date())]
        data.energyEntries = [EnergyEntry(level: 3, percent: 62, givesEnergy: "Ruhe", takesEnergy: "Lärm", note: "Altbestand")]
        data.reflections = [TherapySessionReflection(summary: "Stunde", whatHelped: "Kaffee", nextFocus: "AirTag")]
        data.moodCheckIns = [MoodCheckIn(mood: 4, battery: 3)]
        data.batteryPoints = [BatteryPoint(title: "Wald", direction: .gives)]
        data.weekReviews = [WeekReview(weekStart: Date().therapyWeekStart, summary: "Gut")]
        data.wellnessSettings.weeklyGoal = 3
        data.currentSession = RunningTherapySession.start(data.sessionTemplates[0])
        data.sessionHistory = [RunningTherapySession.start(data.sessionTemplates[0])]
        data.sessionPreferences.privateLiveActivity = false
        let photo = Data((0..<(BackupArchive.chunkSize * 3 + 19)).map { UInt8($0 % 251) })
        let audio = Data("Realistic audio placeholder bytes".utf8), document = Data()
        let files: [(MediaKind, String, Data)] = [(.photo, "Media/photo.jpg", photo), (.audio, "Recordings/speech.m4a", audio), (.document, "Media/empty.pdf", document)]
        for (kind, path, bytes) in files {
            try bytes.write(to: root.appendingPathComponent(path))
            data.media.append(MediaItem(kind: kind, title: kind.displayName, note: "Metadaten bleiben erhalten", tags: ["Therapie"], relativePath: path, folderID: folder.id, topicID: topic.id))
        }
        data.emergencyPlan.imageID = data.media.first?.id
        data.notes[0].mediaIDs = data.media.map(\.id)
        data.notes[0].updatedAt = Date()
        data.moodCheckIns = [MoodCheckIn(mood: 4, battery: 3, moodPercent: 76)]
        data.guidedCheckIns[0].moodPercent = 77
        let point = BatteryPoint(title: "Technik", direction: .gives, note: "Ruhe beim Tüfteln", checkInID: data.guidedCheckIns[0].id, impactConfirmed: false)
        data.guidedCheckIns[0].energyPoints = [point]
        data.batteryPoints = [point]
        data.companionSettings.dayCheckInSlots = DailyCheckInSlot.defaults + [DailyCheckInSlot(name: "Mein Moment", startHour: 12, endHour: 13)]
        data.companionSettings.taskAlarmsEnabled = true
        data.companionSettings.energyReviewAlarm = true
        data.sessionPreferences.showLiveActivityNames(false)
        data.companionSettings.sessionAlarmsEnabled = true
        data.companionSettings.sessionPhaseAlarmsEnabled = true
        data.schedule.therapyAlarmsEnabled = true
        data.schedule.cancellations = [TherapyCancellation(date: Date(), reason: .therapist, note: "Praxis geschlossen"), TherapyCancellation(date: Date(), reason: .me, restoredAt: Date())]
        data.schedule.therapyVacations = [TherapyVacation(start: Date(), end: Date().addingTimeInterval(86400 * 14), note: "Urlaub")]

        data.companionSettings.wellnessAlarmEnabled = true
        data.companionSettings.checkInReminders?[0].alarmEnabled = true
        data.companionSettings.checkInReminders?[0].slotID = DailyCheckInSlot.defaults[0].id
        data.weeklyTasks[0].reminder?.alarmEnabled = true
        try BackupArchive.encoder().encode(data).write(to: root.appendingPathComponent("therapy-data.json"))
        let prefs = PortablePreferences(appearance: "dark", calmInterface: false, haptics: false, confetti: false)
        data.captureEntryLocation = true; data.suggestionsEnabled = true; data.lastSuggestionAttempt = Date(timeIntervalSince1970: 1780000000)
        data.entryLocations = [EntryLocation(id: "note-" + data.notes[0].id.uuidString, capturedAt: Date(timeIntervalSince1970: 1780000000), latitude: 52.52, longitude: 13.405, accuracy: 65)]
        data.buddySuggestions = [BuddySuggestion(date: Date(timeIntervalSince1970: 1780000000), reply: AIBuddyReply(title: "Dein Impuls", message: "Eine kleine Pause", sections: [], actions: [], quickReplies: [BuddyQuickReply(title: "Ruhe", text: "Ich brauche Ruhe.")]))]
        data.aiMessages[0].mediaIDs = data.media.map(\.id)
        data.aiConversations[0].draftMediaIDs = data.media.map(\.id)
        data.routines[0].repeatUntilDone = false
        let archive = try BackupArchive.export(data: data, root: root, preferences: prefs, options: BackupOptions(), password: password, version: "3002.0.0")
        defer { try? fm.removeItem(at: archive.deletingLastPathComponent()) }
        let original = try Data(contentsOf: archive)
        try expect(original.range(of: Data(data.notes[0].title.utf8)) == nil, "Notes encrypted")
        try expect(original.range(of: Data("Media/photo.jpg".utf8)) == nil, "Filenames encrypted")
        let prepared = try BackupArchive.prepareImport(url: archive, password: password)
        try expect(prepared.manifest.data.medicalPass == data.medicalPass && prepared.manifest.data.appleIntegration == data.appleIntegration && prepared.manifest.data.wakeAlarms == data.wakeAlarms && prepared.manifest.data.wakeRuns == data.wakeRuns, "Therapy pass, Apple preferences, wake alarms and run progress round-trip")
        try expect(prepared.manifest.data.copingMethods == data.copingMethods && prepared.manifest.data.emergencyPlan == data.emergencyPlan, "Methods, thought stops and emergency image references round-trip")
        try expect(prepared.manifest.data.showerPreferences == data.showerPreferences && prepared.manifest.data.routineDeferrals == data.routineDeferrals && prepared.manifest.data.routines[0].repeatEveryDays == 2, "Shower target, calendar-day rhythm and per-occurrence deferral round-trip")
        try expect(prepared.manifest.data.groundingPractices == data.groundingPractices && prepared.manifest.data.showerEntries == data.showerEntries, "Grounding answers and flexible shower dates round-trip")
        defer { prepared.discard() }
        try expect(try json(prepared.manifest.data) == json(data.portableSnapshot), "All AppData fields round-trip")
        try expect(prepared.manifest.data.dashboard == data.dashboard && prepared.manifest.data.archivePreferences == data.archivePreferences, "Encrypted restore retains cards, pins and archive settings")
        try expect(prepared.manifest.data.aiConversations[0].id == data.aiConversations[0].id && prepared.manifest.data.aiConversations[0].contextDays == 14 && prepared.manifest.data.guidedCheckIns[0].tags == ["Familie"] && prepared.manifest.data.hashtagCatalog == data.hashtagCatalog, "Encrypted backup restores linked chats, context and hashtags")
        try expect(prepared.manifest.data.batteryPoints[0].impactConfirmed == false && prepared.manifest.data.guidedCheckIns[0].energyPoints?[0].signedImpact == 0, "Encrypted backups preserve unresolved AI energy impact without guessing")
        var legacyPoint = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(point)) as! [String: Any]
        legacyPoint.removeValue(forKey: "impactConfirmed")
        let migratedPoint = try BackupArchive.decoder().decode(BatteryPoint.self, from: JSONSerialization.data(withJSONObject: legacyPoint))
        try expect(migratedPoint.hasConfirmedImpact && migratedPoint.signedImpact == 3, "Old battery points retain their previously selected strength")
        var noCompanion = prepared.manifest
        noCompanion.data.guidedCheckIns = []; noCompanion.data.routines = []; noCompanion.data.routineCompletions = []; noCompanion.data.routineSnoozes = []
        try expect(prepared.manifest.entryCount - noCompanion.entryCount == data.guidedCheckIns.count + data.routines.count + data.routineCompletions.count + data.routineSnoozes.count, "Backup overview counts all companion records")
        try expect(prepared.manifest.data.entryLocations == data.entryLocations && prepared.manifest.data.buddySuggestions == data.buddySuggestions && prepared.manifest.data.aiMessages[0].mediaIDs == data.media.map(\.id) && prepared.manifest.data.aiConversations[0].draftMediaIDs == data.media.map(\.id) && prepared.manifest.data.routines[0].repeatUntilDone == false, "Encrypted backup preserves locations, suggestions and replayable chat attachment links")
        try expect(prepared.manifest.preferences == prefs, "Portable preferences round-trip")
        try expect(prepared.manifest.attachments.count == 3 && prepared.manifest.omittedAttachments == 0, "All attachment kinds included")
        for (_, path, bytes) in files { try expect(try Data(contentsOf: prepared.directory.appendingPathComponent(path)) == bytes, "Exact attachment bytes: " + path) }
        let second = try BackupArchive.export(data: data, root: root, preferences: prefs, options: BackupOptions(), password: password, version: "3002.0.0")
        defer { try? fm.removeItem(at: second.deletingLastPathComponent()) }
        try expect(try Data(contentsOf: second) != original, "Fresh salt and nonces")
        let derived = try BackupArchive.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 1)
        let hex = derived.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        try expect(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "PBKDF2-HMAC-SHA256 known answer")
        try rejects("Wrong password accepted") { let value = try BackupArchive.prepareImport(url: archive, password: "incorrect"); value.discard() }
        let corrupted = base.appendingPathComponent("bad.therapiebackup")
        for offset in [0, 27, 35, original.count / 2, original.count - 1, original.count - 28] {
            try original.prefix(offset).write(to: corrupted)
            try rejects("Truncation accepted at \(offset)") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        }
        var altered = original; altered[altered.count / 2] ^= 1
        try altered.write(to: corrupted)
        try rejects("Changed ciphertext accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        try (original + Data([0])).write(to: corrupted)
        try rejects("Trailing bytes accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        altered = original; altered[12] ^= 1; try altered.write(to: corrupted)
        try rejects("Changed salt accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        altered = original; altered[8] = 255; try altered.write(to: corrupted)
        try rejects("Hostile KDF count accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        var ranges: [Range<Int>] = [], cursor = 28
        while cursor < original.count {
            let length = Int(BackupArchive.number(Data(original[cursor..<cursor + 4])))
            ranges.append(cursor..<cursor + 4 + length); cursor += 4 + length
        }
        var reordered = original.prefix(28) + original[ranges[0]] + original[ranges[2]] + original[ranges[1]]
        for range in ranges.dropFirst(3) { reordered.append(original[range]) }
        try reordered.write(to: corrupted)
        try rejects("Reordered frames accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        try expect(try Data(contentsOf: root.appendingPathComponent("Media/photo.jpg")) == photo, "Rejected imports leave originals intact")
        for path in ["../outside", "/Media/a", "Media/../a", "Media//a", "Media/a/b", "Other/a", "Recordings/..", "Media/a\\b"] {
            try rejects("Unsafe path accepted: " + path) { try BackupArchive.validatePath(path) }
        }
        var hostile = prepared.manifest
        hostile.attachments[0].path = "../outside"
        try malicious(hostile, at: corrupted)
        try rejects("Authenticated hostile path accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        hostile = prepared.manifest; hostile.formatVersion = 999; try malicious(hostile, at: corrupted)
        try rejects("Future format accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        hostile = prepared.manifest; hostile.attachments[0].bytes = UInt64.max
        try malicious(hostile, at: corrupted)
        try rejects("Overflow size accepted") { let value = try BackupArchive.prepareImport(url: corrupted, password: password); value.discard() }
        var noPhotos = BackupOptions(); noPhotos.includePhotos = false
        let small = try BackupArchive.export(data: data, root: root, preferences: prefs, options: noPhotos, password: password, version: "3002.0.0")
        defer { try? fm.removeItem(at: small.deletingLastPathComponent()) }
        let withoutPhotos = try BackupArchive.prepareImport(url: small, password: password)
        defer { withoutPhotos.discard() }
        try expect(withoutPhotos.manifest.data.media.count == 3, "Excluded photo metadata preserved")
        try expect(withoutPhotos.manifest.data.media[0].attachmentOmitted == true && withoutPhotos.manifest.omittedAttachments == 1, "Photo omission explicit")
        try expect(!fm.fileExists(atPath: withoutPhotos.directory.appendingPathComponent("Media/photo.jpg").path), "No excluded image bytes restored")
        try expect(try Data(contentsOf: withoutPhotos.directory.appendingPathComponent("Recordings/speech.m4a")) == audio, "Audio retained without photos")
        try BackupArchive.install(directory: withoutPhotos.directory, root: root)
        try expect(!fm.fileExists(atPath: root.appendingPathComponent("Media/photo.jpg").path), "Import replaces attachment set")
        try expect(fm.fileExists(atPath: BackupArchive.recoveryURL(root).appendingPathComponent("Media/photo.jpg").path), "Pre-import recovery copy retained")
        let reexport = try BackupArchive.export(data: withoutPhotos.manifest.data, root: root, preferences: prefs, options: BackupOptions(), password: password, version: "3002.0.0")
        defer { try? fm.removeItem(at: reexport.deletingLastPathComponent()) }
        let reimport = try BackupArchive.prepareImport(url: reexport, password: password); defer { reimport.discard() }
        try expect(reimport.manifest.omittedAttachments == 1, "Omissions survive subsequent full export")
        let invalidDirectory = try BackupArchive.privateDirectory(in: base)
        defer { try? fm.removeItem(at: invalidDirectory) }
        try Data("{}".utf8).write(to: invalidDirectory.appendingPathComponent("therapy-data.json"))
        let before = try Data(contentsOf: root.appendingPathComponent("therapy-data.json"))
        try rejects("Invalid staging installed") { try BackupArchive.install(directory: invalidDirectory, root: root) }
        try expect(try Data(contentsOf: root.appendingPathComponent("therapy-data.json")) == before, "Failed install leaves current data unchanged")
        try fm.removeItem(at: root)
        try BackupArchive.recoverInterruptedRestore(root: root)
        try expect(try Data(contentsOf: root.appendingPathComponent("Media/photo.jpg")) == photo, "Interrupted import recovers original directory")
        try fm.removeItem(at: root.appendingPathComponent("Media/photo.jpg"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("Media/photo.jpg"), withDestinationURL: base.appendingPathComponent("bad.therapiebackup"))
        try rejects("Symlink exported") { _ = try BackupArchive.export(data: data, root: root, preferences: prefs, options: BackupOptions(), password: password, version: "3002.0.0") }
        let defaults = UserDefaults(suiteName: "TherapieBackupTests-" + UUID().uuidString)!
        prefs.apply(defaults)
        try expect(PortablePreferences.capture(defaults) == prefs, "Appearance, calm, haptics and confetti restored")
        var oldJSON = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(data)) as! [String: Any]
        for version in 1...16 {
            oldJSON["schemaVersion"] = version
            let migrated = try BackupArchive.decoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: oldJSON))
            try expect(migrated.schemaVersion == 17 && migrated.notes.count == 1 && migrated.media[0].attachmentOmitted == nil, "Schema \(version) migrates for backups")
        }
        oldJSON["schemaVersion"] = 12; oldJSON.removeValue(forKey: "accentTheme"); oldJSON.removeValue(forKey: "wellbeingPreferences")
        for key in ["copingMethods", "emergencyPlan", "groundingPractices", "showerEntries"] { oldJSON.removeValue(forKey: key) }
        let pre3011 = try BackupArchive.decoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try expect(pre3011.copingMethods.isEmpty && !pre3011.emergencyPlan.hasContent && pre3011.groundingPractices.isEmpty && pre3011.showerEntries.isEmpty, "Older backups receive empty support defaults")
        try expect(pre3011.accentTheme == .indigo && !pre3011.wellbeingPreferences.estimateBattery, "Actual schema12 defaults to existing design and no fabricated live battery")
        oldJSON["schemaVersion"] = 8; oldJSON.removeValue(forKey: "dashboard"); oldJSON.removeValue(forKey: "archivePreferences")
        let oldWithoutSettings = try BackupArchive.decoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try expect(oldWithoutSettings.dashboard == DashboardPreferences() && oldWithoutSettings.archivePreferences == ArchivePreferences(), "Real pre-personalization backup migrates safely")
        oldJSON["schemaVersion"] = 9
        for key in ["aiSettings", "aiMessages", "therapyDiscussionAcknowledgedIDs"] { oldJSON.removeValue(forKey: key) }
        var oldSchedule = oldJSON["schedule"] as! [String: Any]; oldSchedule.removeValue(forKey: "recurrence"); oldSchedule.removeValue(forKey: "extraAppointments"); oldJSON["schedule"] = oldSchedule
        let preAI = try BackupArchive.decoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try expect(!preAI.aiSettings.enabled && preAI.aiMessages.isEmpty && preAI.schedule.recurrence == nil && preAI.therapyDiscussionAcknowledgedIDs.isEmpty, "Actual schema-9 backup preserves weekly plan and defaults AI off")
        try expect(!String(decoding: try BackupArchive.encoder().encode(data), as: UTF8.self).contains("apiKey"), "API keys never belong to backup model")
        print("Passed \(count) encrypted backup checks: complete model, streaming attachments, password authentication, tampering, paths, omissions, settings and recovery.")
    }
}
