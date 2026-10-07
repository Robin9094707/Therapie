import Foundation

@main
struct StorageReminderChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ test: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !test() { throw Failure.assertion(message) } }
    static func rejects(_ message: String, _ work: () throws -> Void) throws { do { try work() } catch { count += 1; return }; throw Failure.assertion(message) }
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        let fm = FileManager.default, base = try BackupArchive.privateDirectory()
        defer { try? fm.removeItem(at: base) }
        let support = base.appendingPathComponent("Support"), documents = base.appendingPathComponent("Documents")
        let legacy = support.appendingPathComponent("Therapie")
        for folder in ["Media", "Recordings"] { try fm.createDirectory(at: legacy.appendingPathComponent(folder), withIntermediateDirectories: true) }
        var data = AppData()
        let supportClock = Date(timeIntervalSince1970: 1_790_000_000)
        data.copingMethods = [.asmrExample, .thoughtStopExample]
        for index in data.copingMethods.indices { data.copingMethods[index].createdAt = supportClock; data.copingMethods[index].updatedAt = supportClock }
        data.emergencyPlan = PersonalEmergencyPlan(firstStep: "Reize reduzieren", steps: ["Eine Pause machen"], support: "Meine eigene Kontaktperson", methodIDs: [data.copingMethods[0].id], updatedAt: supportClock)
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
        data.schedule.recurrence = TherapyRecurrence(interval: 2, additionalWeeklySlots: [TherapyWeeklySlot(weekday: 5, hour: 10)])
        data.schedule.extraAppointments = [TherapyExtraAppointment(title: "Zusatzgespräch")]
        data.companionSettings.allowMultipleCheckInsPerSlot = false
        data.companionSettings.alarmShowsActualTitles = true
        data.aiSettings.enabled = true; data.aiSettings.model = "gpt-5.6-luna"; data.aiSettings.contextDays = 14
        data.aiMessages = [AIBuddyMessage(role: "assistant", text: "Mein KI-Rückblick", reply: AIBuddyReply(title: "Meine Woche", message: "Ein ruhiger Moment", sections: [], actions: [], suggestedDays: 7))]
        AIConversationMutation.migrate(&data)
        data.aiConversations[0].contextDays = 14
        data.aiConversations[0].draftText = "Noch nicht gesendeter Gedanke"
        data.accentTheme = .purple; data.wellbeingPreferences.estimateBattery = true; data.wellbeingPreferences.hourlyDecline = 2
        data.aiSettings.speakReplies = true
        data.aiConversations[0].memory = "Familie und Pausen"; data.aiConversations[0].tags = ["Familie"]
        data.guidedCheckIns[0].conversationTranscript = "Du: Meine Schwester hilft."
        data.guidedCheckIns[0].satisfaction = 4
        data.aiSettings.weeklyReviewEnabled = true
        data.aiSettings.lastWeeklyReview = Date(timeIntervalSince1970: 1_780_000_000)
        data.aiSettings.lastWeeklyReviewAttempt = data.aiSettings.lastWeeklyReview
        data.editorDrafts = [try AppEditorDraft.make(TherapyNote(title: "Entwurfsnotiz", text: "Mein nicht verlorener Entwurf", tags: ["Familie"]), id: UUID(), kind: "note", title: "Entwurfsnotiz")]
        data.routines[0].recurrenceAnchor = Date(timeIntervalSince1970: 1_770_000_000)
        data.routines[0].repeatEveryWeeks = 2
        data.routines[0].endsAt = Date(timeIntervalSince1970: 1_880_000_000)
        data.hashtagCatalog = ["Familie"]
        data.guidedCheckIns[0].tags = ["Familie"]
        data.therapyDiscussionAcknowledgedIDs = ["guided-discussed"]
        data.reminderPreferences.energyReviewEnabled = true
        data.notes = [TherapyNote(title: "Lesbare Notiz", text: "Meine wichtige Zeile\nzweite Zeile", tags: ["wichtig"], isImportant: true, conversationID: data.aiConversations[0].id, conversationTranscript: "Du: Meine Schwester hilft. Begleiter: Eine Pause.")]
        data.therapyFolders = [TherapyFolder(title: "Meine Themen")]
        data.weeklyEnergyReviews = [WeeklyEnergyReview(periodEnd: now, energy: 4, gives: [WeeklyEnergyFactor(title: "Freunde", impact: 4)], takes: [WeeklyEnergyFactor(title: "Viele Reize", impact: 2)], therapyQuestion: "Wie kann ich Pausen planen?")]
        try expect(data.guidedCheckIns[0].batteryPercent == 0, "Zero battery fixture")
        let week = now.therapyWeek
        data.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: week.week, yearForWeekOfYear: week.year, title: "Meine Aufgabe", details: "Kleiner Schritt", reminder: TaskReminder(), smallStep: "Erst anfangen", support: "Therapie", progress: 20)]
        let photo = Data((0..<(BackupArchive.chunkSize * 2 + 5)).map { UInt8($0 % 251) })
        try photo.write(to: legacy.appendingPathComponent("Media/p.jpg"))
        try Data().write(to: legacy.appendingPathComponent("Recordings/empty.m4a"))
        data.media = [MediaItem(kind: .photo, title: "Bild", note: "Wichtige Beschreibung", tags: ["Privat"], relativePath: "Media/p.jpg"), MediaItem(kind: .audio, title: "Leer", note: "", tags: [], relativePath: "Recordings/empty.m4a")]
        data.emergencyPlan.imageID = data.media.first?.id
        data.notes[0].mediaIDs = data.media.map(\.id)
        data.notes[0].updatedAt = Date()
        data.moodCheckIns = [MoodCheckIn(mood: 4, battery: 3, moodPercent: 76)]
        data.guidedCheckIns[0].moodPercent = 77
        let point = BatteryPoint(title: "Technik", direction: .gives, note: "Ruhe beim Tüfteln", checkInID: data.guidedCheckIns[0].id)
        var unresolvedPoint = point; unresolvedPoint.impactConfirmed = false
        data.guidedCheckIns[0].energyPoints = [unresolvedPoint]
        data.batteryPoints = [unresolvedPoint]
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
        try BackupArchive.encoder().encode(data).write(to: legacy.appendingPathComponent("therapy-data.json"))
        let legacyRecovery = BackupArchive.recoveryURL(legacy)
        try fm.createDirectory(at: legacyRecovery, withIntermediateDirectories: true)
        try Data("recovery".utf8).write(to: legacyRecovery.appendingPathComponent("original.txt"))
        let root = try AppFileStorage.root(applicationSupport: support, documents: documents, folder: "Therapie")
        try expect(root == documents.appendingPathComponent("Therapiedaten"), "Documents location is stable")
        try expect(!fm.fileExists(atPath: legacy.path), "Legacy storage migrated")
        try expect(try String(contentsOf: BackupArchive.recoveryURL(root).appendingPathComponent("original.txt"), encoding: .utf8) == "recovery", "Pre-import recovery copy migrates to Files too")
        try expect(try Data(contentsOf: root.appendingPathComponent("Media/p.jpg")) == photo, "Migration preserves exact photo bytes")
        try expect(try BackupArchive.decoder().decode(AppData.self, from: Data(contentsOf: root.appendingPathComponent("therapy-data.json"))).notes.count == 1, "Migration retains original data")
        try expect(try AppFileStorage.root(applicationSupport: support, documents: documents, folder: "Therapie") == root, "Migration is idempotent")
        try ReadableBackup.writeEntries(data: data, root: root)
        try expect(try ReadableBackup.relativePath(root.appendingPathComponent("Media/p.jpg").resolvingSymlinksInPath(), in: root) == "Media/p.jpg", "Canonical and system-alias paths have the same relative path")
        let dashboardText = try String(contentsOf: root.appendingPathComponent("Eintraege/Einstellungen/dashboard.txt"), encoding: .utf8)
        try expect(dashboardText.contains("note-backup-test") && dashboardText.contains("routines"), "Readable mirror retains layout and pins")
        let noteFile = root.appendingPathComponent("Eintraege/notes/" + data.notes[0].id.uuidString + ".txt")
        try expect(try String(contentsOf: noteFile, encoding: .utf8).contains("zweite Zeile"), "Human-readable multiline note retained")
        try expect(try String(contentsOf: root.appendingPathComponent("UEBERSICHT.md"), encoding: .utf8).contains("Lesbare Notiz"), "Human-readable index contains titles")
        let energyFile = root.appendingPathComponent("Eintraege/weeklyEnergyReviews/" + data.weeklyEnergyReviews[0].id.uuidString + ".txt")
        try expect(try String(contentsOf: energyFile, encoding: .utf8).contains("Freunde"), "Weekly energy factors human-readable")
        let pointFile = root.appendingPathComponent("Eintraege/batteryPoints/" + point.id.uuidString + ".txt")
        try expect(try String(contentsOf: pointFile, encoding: .utf8).contains("Akku-Wirkung bestaetigt"), "Readable mirror includes the unresolved impact status")
        var removed = data; removed.notes = []
        try ReadableBackup.writeEntries(data: removed, root: root)
        try expect(!fm.fileExists(atPath: noteFile.path), "Deleted records removed from readable mirror")
        try ReadableBackup.writeEntries(data: data, root: root)
        let preferences = PortablePreferences(appearance: "dark", calmInterface: true, haptics: false, confetti: true)
        data.captureEntryLocation = true; data.suggestionsEnabled = true; data.lastSuggestionAttempt = Date(timeIntervalSince1970: 1780000000)
        data.entryLocations = [EntryLocation(id: "note-" + data.notes[0].id.uuidString, capturedAt: Date(timeIntervalSince1970: 1780000000), latitude: 52.52, longitude: 13.405, accuracy: 65)]
        data.buddySuggestions = [BuddySuggestion(date: Date(timeIntervalSince1970: 1780000000), reply: AIBuddyReply(title: "Dein Impuls", message: "Eine kleine Pause", sections: [], actions: [], quickReplies: [BuddyQuickReply(title: "Ruhe", text: "Ich brauche Ruhe.")]))]
        data.aiMessages[0].mediaIDs = data.media.map(\.id)
        data.aiConversations[0].draftMediaIDs = data.media.map(\.id)
        data.routines[0].repeatUntilDone = false
        let zip = try ReadableBackup.export(data: data, root: root, preferences: preferences, options: BackupOptions(), version: "3003.0.0")
        defer { try? fm.removeItem(at: zip.deletingLastPathComponent()) }
        let prepared = try ReadableBackup.prepareImport(url: zip); defer { prepared.discard() }
        try expect(prepared.manifest.data.copingMethods == data.copingMethods && prepared.manifest.data.emergencyPlan == data.emergencyPlan, "Methods, thought stops and emergency image references round-trip")
        try expect(prepared.manifest.data.showerPreferences == data.showerPreferences && prepared.manifest.data.routineDeferrals == data.routineDeferrals && prepared.manifest.data.routines[0].repeatEveryDays == 2, "Shower target, calendar-day rhythm and per-occurrence deferral round-trip")
        try expect(prepared.manifest.data.groundingPractices == data.groundingPractices && prepared.manifest.data.showerEntries == data.showerEntries, "Grounding answers and flexible shower dates round-trip")
        try expect(try BackupArchive.encoder().encode(prepared.manifest.data) == BackupArchive.encoder().encode(data.portableSnapshot), "Plain ZIP preserves all AppData fields")
        try expect(prepared.manifest.preferences == preferences, "Plain ZIP preserves portable settings")
        try expect(try Data(contentsOf: prepared.directory.appendingPathComponent("Media/p.jpg")) == photo, "ZIP streams multiple attachment blocks")
        try expect(try Data(contentsOf: prepared.directory.appendingPathComponent("Recordings/empty.m4a")).isEmpty, "ZIP supports empty attachments")
        try expect(fm.fileExists(atPath: prepared.directory.appendingPathComponent("UEBERSICHT.md").path), "ZIP contains readable overview")
        try expect(prepared.manifest.data.aiConversations[0].id == data.aiConversations[0].id && prepared.manifest.data.aiConversations[0].contextDays == 14 && prepared.manifest.data.guidedCheckIns[0].tags == ["Familie"], "Readable ZIP preserves linked chat, context and hashtags")
        try expect(prepared.manifest.data.dashboard == data.dashboard && prepared.manifest.data.archivePreferences == data.archivePreferences, "Readable ZIP restores personalization and archive settings")
        try expect(prepared.manifest.data.batteryPoints[0].impactConfirmed == false && prepared.manifest.data.guidedCheckIns[0].energyPoints?[0].signedImpact == 0, "Readable ZIP preserves unresolved energy strength in both linked records")
        try expect(prepared.manifest.data.entryLocations == data.entryLocations && prepared.manifest.data.buddySuggestions == data.buddySuggestions && prepared.manifest.data.aiMessages[0].mediaIDs == data.media.map(\.id) && prepared.manifest.data.routines[0].repeatUntilDone == false, "Readable ZIP preserves locations, suggestions, audio links and reminder mode")
        let locationText = try String(contentsOf: prepared.directory.appendingPathComponent("Eintraege/entryLocations/0.txt"), encoding: .utf8)
        try expect(locationText.contains("52.52"), "New location records appear in the human-readable mirror")
        let reminderText = try String(contentsOf: prepared.directory.appendingPathComponent("Eintraege/Einstellungen/companionSettings.txt"), encoding: .utf8)
        try expect(reminderText.contains("Check-in-Erinnerungen"), "Reminder settings appear in readable mirror")
        let logText = try String(contentsOf: prepared.directory.appendingPathComponent("Eintraege/routineCompletions/" + data.routineCompletions[0].id.uuidString + ".txt"), encoding: .utf8)
        try expect(logText.contains("Falsche Angabe") && logText.contains("Frühstück"), "History titles and correction audit are human-readable")
        let checkURL = URL(fileURLWithPath: "/tmp/therapie-portable-check.zip")
        try? fm.removeItem(at: checkURL); try fm.copyItem(at: zip, to: checkURL)
        var noPhotos = BackupOptions(); noPhotos.includePhotos = false
        let slim = try ReadableBackup.export(data: data, root: root, preferences: preferences, options: noPhotos, version: "3003.0.0")
        defer { try? fm.removeItem(at: slim.deletingLastPathComponent()) }
        let small = try ReadableBackup.prepareImport(url: slim); defer { small.discard() }
        try expect(small.manifest.omittedAttachments == 1 && small.manifest.data.media[0].attachmentOmitted == true, "ZIP image exclusion explicit")
        try expect(small.manifest.data.media[0].note == data.media[0].note, "Excluded attachment metadata retained")
        try expect(!fm.fileExists(atPath: small.directory.appendingPathComponent("Media/p.jpg").path), "Excluded photo absent from ZIP")
        for path in ["../x", "/x", "a//b", "a/../b", "a\\b", "a/./b", "a/", "a\0b"] { try rejects("Unsafe ZIP path accepted") { try StoredZIP.path(path) } }
        let raw = try Data(contentsOf: zip), corrupt = base.appendingPathComponent("bad.zip")
        try raw.prefix(raw.count - 1).write(to: corrupt)
        try rejects("Truncated ZIP accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        var changed = raw; changed[100] ^= 1; try changed.write(to: corrupt)
        try rejects("Modified ZIP accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        try (raw + Data([0])).write(to: corrupt)
        try rejects("Appended bytes accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        var attacked = raw
        let originalName = Data("Media/p.jpg".utf8), unsafeName = Data("../xx/p.jpg".utf8)
        while let range = attacked.range(of: originalName) { attacked.replaceSubrange(range, with: unsafeName) }
        try attacked.write(to: corrupt)
        try rejects("ZIP traversal accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        let legacy2 = base.appendingPathComponent("Support2/Therapie"), docs2 = base.appendingPathComponent("Documents2")
        try fm.createDirectory(at: legacy2, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: legacy2.appendingPathComponent("therapy-data.json"))
        try fm.createDirectory(at: docs2.appendingPathComponent("Therapiedaten"), withIntermediateDirectories: true)
        try rejects("Occupied target silently replaced") { _ = try AppFileStorage.root(applicationSupport: legacy2.deletingLastPathComponent(), documents: docs2, folder: "Therapie") }
        try expect(try String(contentsOf: legacy2.appendingPathComponent("therapy-data.json"), encoding: .utf8) == "original", "Failed migration keeps original")
        let task = data.weeklyTasks[0]
        let daily = TaskReminderPlanner.slots(tasks: [task], schedule: data.schedule, now: now)
        try expect(daily.count == 1 && daily[0].weekday == nil, "Seven weekdays use one repeating daily notification")
        let many = (0..<45).map { _ -> WeeklyTask in var copy = task; copy.id = UUID(); return copy }
        let planned = TaskReminderPlanner.slots(tasks: many, schedule: data.schedule, now: now)
        try expect(TaskReminderPlanner.admittedSlots(planned).count == 40, "Task notification budget leaves room for session reminders")
        let grouped = (0..<7).flatMap { _ -> [TaskReminderSlot] in let id = UUID(); return (1...6).map { TaskReminderSlot(taskID: id, weekday: $0, hour: 18, minute: 0) } }
        let bounded = TaskReminderPlanner.admittedSlots(grouped)
        try expect(bounded.count == 36 && Set(bounded.map(\.taskID)).count == 6, "Capacity never schedules half a task's weekdays")
        var done = task; done.completed = true
        try expect(TaskReminderPlanner.slots(tasks: [done], schedule: data.schedule, now: now).isEmpty, "Completed task has no reminder")
        var off = task; off.reminder?.enabled = false
        try expect(TaskReminderPlanner.slots(tasks: [off], schedule: data.schedule, now: now).isEmpty, "Disabled task has no reminder")
        var chosen = task; chosen.reminder = TaskReminder(weekdays: [2, 2, 6, 99], hour: 30, minute: -1)
        let selected = TaskReminderPlanner.slots(tasks: [chosen], schedule: data.schedule, now: now)
        try expect(selected.count == 2 && Set(selected.compactMap(\.weekday)) == Set([2, 6]), "Weekdays deduplicate and validate")
        try expect(selected.allSatisfy { $0.hour == 23 && $0.minute == 0 }, "Reminder clock clamped")
        var older = task; older.reminder = nil
        try expect(TaskReminderPlanner.slots(tasks: [older], schedule: data.schedule, now: now).count == 2, "Legacy task inherits global weekdays")
        var future = task; let futureWeek = now.therapyAddingWeeks(1).therapyWeek; future.weekOfYear = futureWeek.week; future.yearForWeekOfYear = futureWeek.year
        try expect(TaskReminderPlanner.slots(tasks: [future], schedule: data.schedule, now: now).isEmpty, "Future task not prematurely reminded")
        try expect(TaskReminderPlanner.slots(tasks: [future], schedule: data.schedule, now: now.therapyAddingWeeks(1)).count == 1, "Future week task becomes active")
        var shifted = task; TaskReminderPlanner.postpone(&shifted, schedule: data.schedule, minutes: 60, now: now)
        try expect(shifted.reminder?.hour == 15 && shifted.reminderShiftedAt == now.addingTimeInterval(3600), "Postpone updates repeating clock and history")
        var tomorrow = task; TaskReminderPlanner.postpone(&tomorrow, schedule: data.schedule, minutes: 1440, now: now)
        try expect(tomorrow.reminderShiftedAt == now.addingTimeInterval(86400) && tomorrow.reminder?.hour == 14, "Tomorrow updates schedule")
        let unchanged = done; TaskReminderPlanner.postpone(&done, schedule: data.schedule, minutes: 60, now: now)
        try expect(done == unchanged, "Done tasks cannot be postponed")
        let periodEnd = TherapyReviewPeriod.latestTherapyDay(schedule: data.schedule, now: now)
        try expect(Calendar.therapyCalendar.component(.weekday, from: periodEnd) == data.schedule.weekday && periodEnd <= now, "Most recent therapy day selected")
        let review = WeeklyEnergyReview(periodEnd: now)
        try expect(Calendar.therapyCalendar.dateComponents([.day], from: review.periodStart, to: Calendar.therapyCalendar.startOfDay(for: now)).day == 7, "Review has exactly seven completed calendar days")
        let dst = ISO8601DateFormatter().date(from: "2026-03-31T12:00:00Z")!
        let dstReview = WeeklyEnergyReview(periodEnd: dst)
        try expect(Calendar.therapyCalendar.dateComponents([.day], from: dstReview.periodStart, to: Calendar.therapyCalendar.startOfDay(for: dst)).day == 7, "Review crosses daylight-saving using calendar days")
        var justEnergy = AppData(); justEnergy.weeklyEnergyReviews = [WeeklyEnergyReview(periodEnd: now)]
        try expect(WellnessAnalytics.streak(WellnessAnalytics.activityDates(justEnergy), now: now).thisWeekRecorded, "Weekly energy contributes to weekly streak")
        print("Passed \(count) readable ZIP, Documents migration, reminder schedule and weekly energy checks.")
    }
}
