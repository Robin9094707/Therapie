import Foundation

@main struct CompanionChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !value() { throw Failure.assertion(message) } }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-09-30T04:00:00Z")
        var data = AppData()
        let time = RoutineTime(title: "Morgens", weekdays: Array(1...7), hour: 6, minute: 30, weekendHour: 9, weekendMinute: 15)
        var routine = DailyRoutine(title: "Eigene Routine", times: [time], retryMinutes: 20, escalationHour: 23, escalationMinutes: 5)
        data.routines = [routine]
        var entry = GuidedCheckIn(kind: .therapy, batteryPercent: 0, tasks: [CheckInTaskDraft(title: "Kleiner Schritt")], isDraft: false)
        data.guidedCheckIns = [entry]
        let roundtrip = try BackupArchiveCompatible.decode(BackupArchiveCompatible.encode(data))
        try expect(try JSONSerialization.jsonObject(with: BackupArchiveCompatible.encode(roundtrip)) as! NSDictionary == JSONSerialization.jsonObject(with: BackupArchiveCompatible.encode(data)) as! NSDictionary, "All new types and zero battery round-trip")
        var object = try JSONSerialization.jsonObject(with: BackupArchiveCompatible.encode(data)) as! [String: Any]
        object["schemaVersion"] = 6
        for key in ["guidedCheckIns", "routines", "routineCompletions", "routineSnoozes", "companionSettings"] { object.removeValue(forKey: key) }
        let migrated = try BackupArchiveCompatible.decode(JSONSerialization.data(withJSONObject: object))
        try expect(migrated.schemaVersion == 9 && migrated.routines.isEmpty && migrated.guidedCheckIns.isEmpty, "Schema 6 migration defaults")
        entry.mood = nil; entry.batteryPercent = nil; data.guidedCheckIns = [entry]
        try expect(try BackupArchiveCompatible.decode(BackupArchiveCompatible.encode(data)).guidedCheckIns[0].batteryPercent == nil, "Skipped answers stay absent")
        var mutationData = AppData()
        var draftEntry = GuidedCheckIn(kind: .therapy, tasks: [CheckInTaskDraft(title: "Kleiner Schritt")])
        GuidedCheckInMutation.apply(draftEntry, complete: false, to: &mutationData)
        try expect(mutationData.weeklyTasks.isEmpty, "Draft never creates tasks")
        GuidedCheckInMutation.apply(draftEntry, complete: true, to: &mutationData)
        try expect(mutationData.weeklyTasks.count == 1 && !mutationData.guidedCheckIns[0].isDraft, "Finish commits check-in and tasks together")
        GuidedCheckInMutation.apply(draftEntry, complete: true, to: &mutationData)
        try expect(mutationData.weeklyTasks.count == 1, "Repeated finish does not duplicate tasks")
        mutationData.weeklyTasks[0].completed = true
        draftEntry.tasks[0].title = "Bearbeiteter Schritt"
        GuidedCheckInMutation.apply(draftEntry, complete: true, to: &mutationData)
        try expect(mutationData.weeklyTasks[0].completed && mutationData.weeklyTasks[0].title == "Bearbeiteter Schritt", "Editing task details preserves completion")
        mutationData.weeklyTasks = []
        GuidedCheckInMutation.apply(draftEntry, complete: true, to: &mutationData)
        try expect(mutationData.weeklyTasks.isEmpty, "Deleted task cannot resurrect")
        draftEntry.tasks.append(CheckInTaskDraft(title: "Zusätzliche Aufgabe"))
        GuidedCheckInMutation.apply(draftEntry, complete: true, to: &mutationData)
        try expect(mutationData.weeklyTasks.count == 1, "New task in existing check-in creates exactly one task")
        let occurrences = RoutinePlanner.occurrences([routine], settings: data.companionSettings, now: now, calendar: calendar)
        let today = occurrences.first { calendar.isDate($0.due, inSameDayAs: now) }!
        try expect(calendar.component(.hour, from: today.due) == 6 && calendar.component(.minute, from: today.due) == 30, "Weekday clock")
        let saturday = occurrences.first { calendar.component(.weekday, from: $0.due) == 7 }!
        try expect(calendar.component(.hour, from: saturday.due) == 9 && calendar.component(.minute, from: saturday.due) == 15, "Weekend clock")
        let sunday = occurrences.first { calendar.component(.weekday, from: $0.due) == 1 }!
        let monday = occurrences.first { $0.due > sunday.due && calendar.component(.weekday, from: $0.due) == 2 }!
        try expect(sunday.end == monday.due, "Earlier Monday clock closes Sunday's reminders without overlap")
        let original = RoutinePlanner.slots(data: data, now: now, calendar: calendar)
        try expect(original == RoutinePlanner.slots(data: data, now: now, calendar: calendar), "Stable idempotent slots")
        let admitted = RoutinePlanner.admittedSlots(original, budget: 20)
        try expect(admitted.count <= 20 && Set(admitted.map(\.id)).count == admitted.count, "Queue admission remains bounded and unique")
        try expect(Set(admitted.map { $0.occurrence.id }).count == Set(original.map { $0.occurrence.id }).count, "First hint for every occurrence before retry allocation")
        try expect(RoutinePlanner.admittedSlots(original, budget: 0).isEmpty, "Zero capacity is explicit")
        try expect(Set(original.map(\.id)).count == original.count, "No duplicate notification identifiers")
        try expect(original.allSatisfy { $0.fireAt > now && $0.fireAt < $0.occurrence.end }, "No past or expired reminders")
        data.routineCompletions = [RoutineCompletion(routineID: routine.id, timeID: time.id, scheduledAt: today.due)]
        let resolved = RoutinePlanner.slots(data: data, now: now, calendar: calendar)
        try expect(!resolved.contains { $0.occurrence.id == today.id }, "Done cancels exactly one occurrence")
        try expect(resolved.contains { $0.occurrence.id == saturday.id }, "Future occurrence survives completion")
        data.routineCompletions = []; data.routineSnoozes = [RoutineSnooze(id: today.id, until: today.due.addingTimeInterval(3600))]
        let snoozed = RoutinePlanner.slots(data: data, now: now, calendar: calendar).filter { $0.occurrence.id == today.id }
        try expect(snoozed.first?.fireAt == today.due.addingTimeInterval(3600), "Snooze shifts only this occurrence")
        try expect(data.routines[0].times[0].hour == 6, "Snooze does not change recurring clock")
        data.companionSettings.vacationUntil = now.addingTimeInterval(3 * 86400)
        try expect(!RoutinePlanner.slots(data: data, now: now, calendar: calendar).contains { $0.occurrence.id == today.id }, "Vacation pauses selected routine")
        routine.pauseOnVacation = false; data.routines = [routine]
        try expect(RoutinePlanner.slots(data: data, now: now, calendar: calendar).contains { $0.occurrence.id == today.id }, "Vacation-exempt routine continues")
        data.companionSettings.vacationUntil = nil; routine.quietStartHour = 23; routine.quietEndHour = 7; data.routines = [routine]
        try expect(RoutinePlanner.slots(data: data, now: now, calendar: calendar).allSatisfy { let hour = calendar.component(.hour, from: $0.fireAt); return hour >= 7 && hour < 23 }, "Quiet window respected")
        routine.enabled = false; data.routines = [routine]
        try expect(RoutinePlanner.slots(data: data, now: now, calendar: calendar).isEmpty, "Disabling cancels entire routine")
        routine.enabled = true; routine.quietStartHour = nil; routine.times[0].hour = 2; routine.times[0].minute = 30; routine.times[0].weekendHour = nil; routine.times[0].weekendMinute = nil
        let dstNow = date("2026-03-28T12:00:00Z")
        let dst = RoutinePlanner.occurrences([routine], settings: CompanionSettings(), now: dstNow, calendar: calendar)
        try expect(dst.allSatisfy { $0.end > $0.due }, "DST valid occurrence end")
        try expect(dst.filter { calendar.isDate($0.due, inSameDayAs: date("2026-03-29T12:00:00Z")) }.count == 1, "Nonexistent spring clock produces one occurrence")
        let fall = RoutinePlanner.occurrences([routine], settings: CompanionSettings(), now: date("2026-10-24T12:00:00Z"), calendar: calendar)
        try expect(fall.filter { calendar.isDate($0.due, inSameDayAs: date("2026-10-25T12:00:00Z")) }.count == 1, "Repeated autumn clock produces one occurrence")
        let year = RoutinePlanner.occurrences([routine], settings: CompanionSettings(), now: date("2026-12-31T12:00:00Z"), calendar: calendar)
        try expect(year.contains { calendar.component(.year, from: $0.due) == 2027 }, "Year boundary")
        var companion = AppData()
        let morning = CheckInReminder(kind: .morning, time: time)
        let evening = CheckInReminder(kind: .evening, time: RoutineTime(hour: 20, minute: 30))
        companion.companionSettings.checkInReminders = [morning, evening]
        let hints = CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar)
        try expect(hints.count == 14 && Set(hints.map(\.id)).count == 14, "Two check-ins per day, bounded unique seven-day horizon")
        try expect(hints == CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar), "Check-in planner is idempotent")
        try expect(hints.allSatisfy { $0.fireAt > now }, "No past check-in notification")
        let saturdayHint = hints.first { $0.kind == .morning && calendar.component(.weekday, from: $0.fireAt) == 7 }!
        try expect(calendar.component(.hour, from: saturdayHint.fireAt) == 9 && calendar.component(.minute, from: saturdayHint.fireAt) == 15, "Check-in weekend override")
        companion.guidedCheckIns = [GuidedCheckIn(date: now, kind: .morning, isDraft: true)]
        try expect(CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar).count == 14, "Draft does not cancel reminder")
        companion.guidedCheckIns[0].isDraft = false
        let finishedHints = CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar)
        try expect(finishedHints.count == 13 && !finishedHints.contains { $0.kind == .morning && calendar.isDate($0.fireAt, inSameDayAs: now) }, "Completed morning cancels that local day's hint")
        try expect(finishedHints.contains { $0.kind == .evening && calendar.isDate($0.fireAt, inSameDayAs: now) }, "Evening remains after morning completion")
        companion.guidedCheckIns = []
        companion.companionSettings.checkInReminders = [morning, morning, evening, CheckInReminder(kind: .free)]
        try expect(CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar).count == 14, "Duplicate/unsupported imported kinds cannot exceed capacity")
        companion.companionSettings.vacationUntil = now.addingTimeInterval(86400)
        try expect(!CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar).contains { calendar.isDate($0.fireAt, inSameDayAs: now) }, "Check-in vacation pause")
        companion.companionSettings.checkInReminders = [CheckInReminder(kind: .morning, time: time, pauseOnVacation: false)]
        try expect(CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar).count == 7, "Vacation-exempt check-ins continue")
        companion.companionSettings.checkInReminders![0].enabled = false
        try expect(CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar).isEmpty, "Disabled check-in reminder cancels all hints")
        companion.companionSettings.vacationUntil = nil
        companion.companionSettings.dayCheckInSlots = DailyCheckInSlot.defaults.map { slot in var value = slot; if value.kind == .morning { value.startHour = 0; value.endHour = 0 }; return value }
        companion.companionSettings.checkInReminders = [CheckInReminder(time: RoutineTime(hour: 2, minute: 30))]
        let springHints = CheckInReminderPlanner.slots(data: companion, now: dstNow, calendar: calendar)
        try expect(springHints.filter { calendar.isDate($0.fireAt, inSameDayAs: date("2026-03-29T12:00:00Z")) }.count == 1, "Missing spring check-in clock produces exactly one hint")
        let fallHints = CheckInReminderPlanner.slots(data: companion, now: date("2026-10-24T12:00:00Z"), calendar: calendar)
        try expect(fallHints.filter { calendar.isDate($0.fireAt, inSameDayAs: date("2026-10-25T12:00:00Z")) }.count == 1, "Repeated fall check-in clock produces exactly one hint")
        try expect(CheckInReminderPlanner.slots(data: companion, now: date("2026-12-31T12:00:00Z"), calendar: calendar).contains { calendar.component(.year, from: $0.fireAt) == 2027 }, "Check-in scheduling crosses year")
        var legacyObject = try JSONSerialization.jsonObject(with: BackupArchiveCompatible.encode(companion)) as! [String: Any]
        var legacySettings = legacyObject["companionSettings"] as! [String: Any]
        legacySettings.removeValue(forKey: "checkInReminders"); legacyObject["companionSettings"] = legacySettings
        let oldSettings = try BackupArchiveCompatible.decode(JSONSerialization.data(withJSONObject: legacyObject))
        try expect(oldSettings.companionSettings.checkInReminders == nil && oldSettings.schemaVersion == 9, "Previous schema-7 settings decode with reminders off")
        let originalLog = RoutineCompletion(routineID: routine.id, timeID: time.id, scheduledAt: now, recordedAt: now, outcome: .done)
        companion.routines = [routine]; companion.routineCompletions = [originalLog]
        RoutineHistoryMutation.preserveTitles(in: &companion, routine: routine)
        try expect(companion.routineCompletions[0].routineTitle == routine.title, "Existing logs gain portable name before edit/delete")
        var renamed = routine; renamed.title = "Umbenannt"
        RoutineHistoryMutation.preserveTitles(in: &companion, routine: renamed)
        try expect(companion.routineCompletions[0].routineTitle == routine.title, "Snapshot names remain historical")
        try expect(!RoutineHistoryMutation.correct(id: originalLog.id, outcome: .skipped, note: "Pause", reason: "  ", in: &companion, now: now), "Correction requires reason")
        try expect(!RoutineHistoryMutation.correct(id: originalLog.id, outcome: .done, note: "", reason: "Test", in: &companion, now: now), "Unchanged correction has no audit noise")
        try expect(RoutineHistoryMutation.correct(id: originalLog.id, outcome: .skipped, note: "Pause", reason: "Vertippt", in: &companion, now: now.addingTimeInterval(60)), "Correction can change recorded outcome")
        let corrected = companion.routineCompletions[0]
        try expect(corrected.scheduledAt == originalLog.scheduledAt && corrected.recordedAt == originalLog.recordedAt && corrected.id == originalLog.id, "Correction preserves original identity and timestamp")
        try expect(corrected.corrections?.first?.previousOutcome == .done && corrected.corrections?.first?.reason == "Vertippt", "Audit retains original outcome and reason")
        try expect(!RoutineHistoryMutation.correct(id: originalLog.id, outcome: .skipped, note: "Pause", reason: "Vertippt", in: &companion, now: now), "Repeated save remains idempotent")
        companion.routines = []
        try expect(RoutineHistoryMutation.title(corrected, data: companion) == routine.title, "Deleted routine history still has its name")
        var logObject = try JSONSerialization.jsonObject(with: BackupArchiveCompatible.encode(companion)) as! [String: Any]
        var oldLog = (logObject["routineCompletions"] as! [[String: Any]])[0]
        for key in ["routineTitle", "timeTitle", "corrections"] { oldLog.removeValue(forKey: key) }
        logObject["routineCompletions"] = [oldLog]
        try expect(try BackupArchiveCompatible.decode(JSONSerialization.data(withJSONObject: logObject)).routineCompletions[0].corrections == nil, "Previous schema-7 logs decode without audit fields")
        let entryA = GuidedCheckIn(date: now, kind: .morning, batteryPercent: 0, summary: "INCLUDED", isDraft: false)
        let entryB = GuidedCheckIn(date: now.addingTimeInterval(3600), kind: .evening, batteryPercent: 100, isDraft: false)
        let entryC = GuidedCheckIn(date: now.addingTimeInterval(7200), batteryPercent: nil, isDraft: false)
        companion.guidedCheckIns = [entryA, entryB, entryC, GuidedCheckIn(date: now, summary: "DRAFT-PRIVATE"), GuidedCheckIn(date: now.addingTimeInterval(-1), summary: "BEFORE-PRIVATE", isDraft: false), GuidedCheckIn(date: now.addingTimeInterval(86400), summary: "AFTER-PRIVATE", isDraft: false)]
        var reportOptions = TherapyReportOptions(start: now, end: now.addingTimeInterval(86400))
        let selected = TherapyReport.checkIns(data: companion, options: reportOptions)
        try expect(selected.count == 3 && selected[0].id == entryA.id, "Report uses half-open boundaries, sorted completed entries only")
        try expect(TherapyReport.meanBattery(selected) == 50, "Zero and hundred included; missing answers excluded from mean")
        try expect(TherapyReport.meanBattery([entryC]) == nil, "No battery data produces no invented average")
        companion.profile.userName = "NAME-PRIVATE"
        companion.notes = [TherapyNote(createdAt: now, title: "NOTE-PRIVATE", text: "SECRET", tags: [])]
        companion.routineCompletions[0].note = "ROUTINE-PRIVATE"
        let report = TherapyReport.text(data: companion, options: reportOptions)
        try expect(report.contains("INCLUDED") && !["DRAFT-PRIVATE", "BEFORE-PRIVATE", "AFTER-PRIVATE", "NOTE-PRIVATE", "NAME-PRIVATE", "ROUTINE-PRIVATE"].contains(where: report.contains), "Report respects selected fields, boundaries and privacy defaults")
        reportOptions.excludedCheckInIDs = [entryA.id]
        try expect(TherapyReport.checkIns(data: companion, options: reportOptions).count == 2 && !TherapyReport.text(data: companion, options: reportOptions).contains("INCLUDED"), "Individual excluded check-in stays out of text and chart")
        reportOptions.includeNotes = true; reportOptions.includeRoutines = true; reportOptions.includeNames = true
        let expandedReport = TherapyReport.text(data: companion, options: reportOptions)
        try expect(["NOTE-PRIVATE", "NAME-PRIVATE", "ROUTINE-PRIVATE", "Vertippt"].allSatisfy(expandedReport.contains), "Explicit opt-in includes notes/names/routine audit")
        companion.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: 40, yearForWeekOfYear: 2026, title: "TASK-PRIVATE", details: "")]
        reportOptions.includeTasks = false
        try expect(!TherapyReport.text(data: companion, options: reportOptions).contains("TASK-PRIVATE"), "Task opt-out excludes task details")
        reportOptions.includeTasks = true
        companion.guidedCheckIns[0].taskIDs = [companion.weeklyTasks[0].id]
        try expect(!TherapyReport.text(data: companion, options: reportOptions).contains("TASK-PRIVATE"), "Excluded check-in also hides its linked tasks")
        companion.companionSettings.checkInReminders = [CheckInReminder(id: morning.id, kind: .morning, time: time), CheckInReminder(id: morning.id, kind: .evening, time: time)]
        let colliding = CheckInReminderPlanner.slots(data: companion, now: now, calendar: calendar)
        try expect(Set(colliding.map(\.id)).count == colliding.count, "Imported shared reminder UUIDs cannot collide across kinds")
        let firstDraft = CheckInTaskDraft(title: "Erste Aufgabe"), secondDraft = CheckInTaskDraft(title: "Zweite Aufgabe"), thirdDraft = CheckInTaskDraft(title: "Dritte Aufgabe")
        var editable = [firstDraft, secondDraft, thirdDraft]
        editable.removeAll { $0.id == firstDraft.id }
        try expect(IdentifiedDraftAccess.read(id: firstDraft.id, fallback: firstDraft, from: editable) == firstDraft, "Disposed first row can safely finish reading after deletion")
        var delayedFirst = firstDraft; delayedFirst.title = "Verspätete Tastatureingabe"
        try expect(!IdentifiedDraftAccess.replace(delayedFirst, id: firstDraft.id, in: &editable) && editable == [secondDraft, thirdDraft], "Keyboard callback cannot restore removed task or overwrite next row")
        var changedSecond = secondDraft; changedSecond.details = "Bleibt richtig zugeordnet"
        try expect(IdentifiedDraftAccess.replace(changedSecond, id: secondDraft.id, in: &editable) && editable[0] == changedSecond, "Shifted remaining row writes through its stable identity")
        editable.reverse()
        changedSecond.title = "Nach Sortieren"
        try expect(IdentifiedDraftAccess.replace(changedSecond, id: secondDraft.id, in: &editable) && editable[1] == changedSecond && editable[0].id == thirdDraft.id, "Reordering cannot send an edit to a different task")
        editable.removeAll { $0.id == secondDraft.id }
        editable.removeAll { $0.id == thirdDraft.id }
        try expect(IdentifiedDraftAccess.read(id: thirdDraft.id, fallback: thirdDraft, from: editable) == thirdDraft && !IdentifiedDraftAccess.replace(thirdDraft, id: thirdDraft.id, in: &editable), "Removing last/all tasks leaves stale getters and setters safe")
        let freshDraft = CheckInTaskDraft(title: "Neu hinzugefügt"); editable.append(freshDraft)
        try expect(!IdentifiedDraftAccess.replace(changedSecond, id: secondDraft.id, in: &editable) && editable == [freshDraft], "Old callback cannot change a newly added task")
        try expect(!IdentifiedDraftAccess.replace(freshDraft, id: thirdDraft.id, in: &editable), "A replacement cannot change row identity")
        var deletedCheckIn = GuidedCheckIn(kind: .morning, tasks: [firstDraft, secondDraft])
        deletedCheckIn.tasks.removeAll { $0.id == firstDraft.id }
        var finishAfterRemoval = AppData()
        GuidedCheckInMutation.apply(deletedCheckIn, complete: true, to: &finishAfterRemoval)
        try expect(finishAfterRemoval.weeklyTasks.map(\.id) == [secondDraft.id], "Finishing after removal creates only the remaining task")
        deletedCheckIn.tasks = []
        var emptyFinish = AppData(); GuidedCheckInMutation.apply(deletedCheckIn, complete: true, to: &emptyFinish)
        try expect(emptyFinish.weeklyTasks.isEmpty && emptyFinish.guidedCheckIns.count == 1, "Empty task list can still finish and save check-in")
        print("Passed \(count) companion migration, optional answers, routine identity, snooze, vacation and DST checks.")
    }
}
enum BackupArchiveCompatible {
    static func encode(_ data: AppData) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(data) }
    static func decode(_ raw: Data) throws -> AppData { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(AppData.self, from: raw) }
}
