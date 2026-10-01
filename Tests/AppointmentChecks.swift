import Foundation

@main struct AppointmentChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !value() { throw Failure.assertion(message) } }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-10-01T12:00:00Z"), next = date("2026-10-06T13:00:00Z")
        var schedule = TherapySchedule()
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == next, "Next regular therapy in local time")
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: next, calendar: cal) == next, "Exact appointment boundary is included")
        let cancellation = TherapyCancellation(date: next, reason: .therapist, note: "Fällt aus")
        TherapyScheduleActions.cancel(cancellation, schedule: &schedule, calendar: cal)
        TherapyScheduleActions.cancel(TherapyCancellation(date: next, reason: .me, note: "Geändert"), schedule: &schedule, calendar: cal)
        try expect(schedule.cancellations?.count == 1 && schedule.cancellations?[0].note == "Geändert", "Repeated cancellation updates one record, no duplicates")
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == date("2026-10-13T13:00:00Z"), "Canceled date skipped")
        TherapyScheduleActions.restore(cancellation.id, schedule: &schedule, at: now)
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == next, "Accidental cancellation can restore original next date")
        try expect(schedule.cancellations?[0].restoredAt == now, "Restoration keeps audit record")
        let vacation = TherapyVacation(start: date("2026-10-05T22:00:00Z"), end: date("2026-10-13T22:00:00Z"), note: "Pause")
        schedule.therapyVacations = [vacation]
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == date("2026-10-20T13:00:00Z"), "Whole selected final day included in therapy vacation")
        try expect(TherapyDateHelper.vacation(schedule: schedule, at: vacation.start) != nil && TherapyDateHelper.vacation(schedule: schedule, at: vacation.end) == nil, "Vacation starts inclusively and ends exclusively")
        schedule.therapyVacations?[0].end = next
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == next, "Therapy resumes exactly at exclusive vacation end")
        schedule.therapyVacations = [vacation]
        TherapyScheduleActions.endVacation(vacation.id, schedule: &schedule, at: now)
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == next, "Ending vacation re-enables therapy")
        schedule.therapyVacations = [TherapyVacation(start: now, end: date("2040-01-01T00:00:00Z"))]
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal)! >= date("2040-01-01T00:00:00Z"), "Long vacations jump to end without hundreds of weekly loops")
        schedule.therapyVacations = nil
        let fall = TherapyDateHelper.occurrences(schedule: schedule, after: date("2026-10-24T12:00:00Z"), count: 2, calendar: cal)
        try expect(fall[0] == date("2026-10-27T14:00:00Z") && fall[1] == date("2026-11-03T14:00:00Z"), "Weekly appointment retains 15 local across autumn DST")
        let spring = TherapyDateHelper.occurrences(schedule: schedule, after: date("2026-03-25T12:00:00Z"), count: 2, calendar: cal)
        try expect(spring[0] == date("2026-03-31T13:00:00Z"), "Weekly appointment retains 15 local after spring DST")
        let year = TherapyDateHelper.occurrences(schedule: schedule, after: date("2026-12-30T12:00:00Z"), count: 2, calendar: cal)
        try expect(year[0] == date("2027-01-05T14:00:00Z"), "Next appointment crosses year safely")
        schedule.weekday = 9
        try expect(TherapyDateHelper.nextOccurrence(schedule: schedule, after: now, calendar: cal) == nil, "Invalid imported schedule is not treated as arbitrary date")
        try expect(TherapyCountdown.label(until: now.addingTimeInterval(90061), from: now) == "In 1 Tag 1 Std. 2 Min.", "Countdown includes days, hours and ceiling minutes")
        try expect(TherapyCountdown.label(until: now.addingTimeInterval(61), from: now) == "In 2 Min.", "Short countdown rounds away from false zero")
        try expect(TherapyCountdown.label(until: now, from: now) == "Dein Termin beginnt jetzt", "Exact time shows begins now")
        var data = AppData(); data.schedule.therapyAlarmsEnabled = true; data.schedule.reminderOffsetsMinutes = [30, 0, 30, -1, 20000]
        let regular = CompanionAlarmPlanner.candidates(data, now: now, calendar: cal)
        try expect(regular.count == 16 && Set(regular.map(\.id)).count == 16, "Therapy alarm horizon eight dates, deduplicated valid offsets")
        try expect(regular.allSatisfy { $0.fireAt > now && $0.route == "therapy" }, "Fixed future therapy alarms route to actual appointments")
        TherapyScheduleActions.cancel(cancellation, schedule: &data.schedule, calendar: cal)
        data.schedule.therapyVacations = [vacation]
        let excluded = CompanionAlarmPlanner.candidates(data, now: now, calendar: cal)
        try expect(excluded.count == 16 && excluded.allSatisfy { $0.fireAt >= date("2026-10-20T12:30:00Z") }, "No alarms for canceled or vacation dates; next actual horizon replenished")
        data.schedule.therapyAlarmsEnabled = false
        try expect(CompanionAlarmPlanner.candidates(data, now: now, calendar: cal).isEmpty, "Turning therapy alarm off removes desired inventory")
        data.schedule.alarmIDs = [UUID().uuidString]; data.schedule.calendarEventIdentifier = "device-event"; data.schedule.therapyAlarmsEnabled = nil
        try expect(data.portableSnapshot.schedule.alarmIDs.isEmpty && data.portableSnapshot.schedule.calendarEventIdentifier == nil && data.portableSnapshot.schedule.therapyAlarmsEnabled == true, "Device IDs omitted from portable snapshot; legacy alarm preference retained")
        data = AppData(); data.companionSettings.sessionPhaseAlarmsEnabled = true; data.sessionPreferences.notifyAtPhases = false; data.sessionPreferences.notifyAtEnd = false
        data.currentSession = RunningTherapySession.start(TherapySessionTemplate(), at: now)
        let phases = CompanionAlarmPlanner.candidates(data, now: now, calendar: cal)
        try expect(phases.count == data.currentSession!.phases.count, "Independent phase alarms include every section boundary and end without notifications")
        try expect(phases.first!.title.contains(data.currentSession!.phases[0].title) && phases.first!.title.contains(data.currentSession!.phases[1].title), "Boundary alarm names completed and next section")
        data.currentSession?.pausedAt = now
        try expect(CompanionAlarmPlanner.candidates(data, now: now, calendar: cal).isEmpty, "Pause cancels all section alarms")
        data.currentSession?.pausedAt = nil; data.currentSession?.endedAt = now
        try expect(CompanionAlarmPlanner.candidates(data, now: now, calendar: cal).isEmpty, "Finish cancels all section alarms")
        let busy = (0..<100).map { CompanionAlarmSlot(id: "routine.\($0)", group: "routine", fireAt: now.addingTimeInterval(Double($0)), title: "R", route: "routine") } + phases
        let admitted = CompanionAlarmPlanner.admitted(busy.sorted { $0.fireAt < $1.fireAt })
        try expect(admitted.count <= 24 && phases.allSatisfy { boundary in admitted.contains { $0.id == boundary.id } }, "Running session boundaries retained under busy alarm capacity")
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppData())) as! [String: Any]
        old["schemaVersion"] = 7
        let restored = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: old))
        try expect(restored.schedule.cancellations == nil && restored.schedule.therapyVacations == nil && restored.schedule.therapyAlarmsEnabled == nil && restored.companionSettings.sessionPhaseAlarmsEnabled == nil, "Existing schema defaults new optional fields safely")
        print("Passed \(count) appointment, restoration, therapy vacation, DST/year, countdown and independent phase-alarm checks.")
    }
}
