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
        try expect(migrated.schemaVersion == 7 && migrated.routines.isEmpty && migrated.guidedCheckIns.isEmpty, "Schema 6 migration defaults")
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
        print("Passed \(count) companion migration, optional answers, routine identity, snooze, vacation and DST checks.")
    }
}
enum BackupArchiveCompatible {
    static func encode(_ data: AppData) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(data) }
    static func decode(_ raw: Data) throws -> AppData { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(AppData.self, from: raw) }
}
