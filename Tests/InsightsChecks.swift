import Foundation

@main struct InsightsChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !value() { throw Failure.assertion(message) } }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        let cal = Calendar.therapyCalendar
        let now = date("2026-09-30T12:00:00Z")
        let defaults = DailyCheckInSlot.defaults
        try expect(defaults.count == 5 && defaults.filter(\.enabled).count == 4, "Morning, noon, evening and night defaults; afternoon optional")
        let morning = defaults[0], night = defaults[4]
        try expect(morning.contains(date("2026-10-01T03:00:00Z"), calendar: cal), "Morning starts at 5 local")
        try expect(!morning.contains(date("2026-10-01T09:00:00Z"), calendar: cal), "Morning end is exclusive at 11 local")
        try expect(night.contains(date("2026-10-01T01:00:00Z"), calendar: cal) && night.contains(date("2026-09-30T21:00:00Z"), calendar: cal), "Night spans midnight")
        try expect(night.anchor(for: date("2026-10-01T01:00:00Z"), calendar: cal) == night.anchor(for: date("2026-09-30T21:00:00Z"), calendar: cal), "Night shares one anchor across midnight")
        try expect(DayCheckInPolicy.allows(kind: .night, settings: CompanionSettings(), at: date("2026-10-01T01:00:00Z"), calendar: cal), "Night is a default slot")
        try expect(!DayCheckInPolicy.allows(kind: .morning, id: UUID(), settings: CompanionSettings(), at: date("2026-10-01T05:00:00Z"), calendar: cal), "Deleted slot cannot fall back to another slot")
        try expect(DayCheckInPolicy.allows(kind: .therapy, settings: CompanionSettings(), at: now), "Therapy remains available anytime")
        let custom = DailyCheckInSlot(name: "Ruhe", startHour: 13, endHour: 16)
        var data = AppData(); data.companionSettings.dayCheckInSlots = defaults + [custom]
        try expect(DayCheckInPolicy.allows(kind: .free, id: custom.id, settings: data.companionSettings, at: now, calendar: cal), "Custom slot within its window")
        try expect(!DayCheckInPolicy.allows(kind: .free, id: custom.id, settings: data.companionSettings, at: date("2026-09-30T08:00:00Z"), calendar: cal), "Custom free kind still respects window")
        var entry = GuidedCheckIn(date: now, kind: .noon, mood: 4, batteryPercent: 0, moodPercent: 75, energyPoints: [BatteryPoint(title: "Technik", direction: .gives, impact: 4, note: "Ruhe"), BatteryPoint(title: "Lärm", direction: .takes, impact: 2)])
        GuidedCheckInMutation.apply(entry, complete: false, to: &data)
        try expect(data.batteryPoints.isEmpty, "Draft does not affect keyword statistics")
        GuidedCheckInMutation.apply(entry, complete: true, to: &data)
        try expect(data.batteryPoints.count == 2 && data.batteryPoints.allSatisfy { $0.checkInID == entry.id && $0.date == now }, "Completion atomically owns and dates individual points")
        GuidedCheckInMutation.apply(entry, complete: true, to: &data)
        try expect(data.batteryPoints.count == 2, "Repeated finish does not duplicate points")
        entry.energyPoints?.removeAll { $0.direction == .takes }; GuidedCheckInMutation.apply(entry, complete: true, to: &data)
        try expect(data.batteryPoints.count == 1 && data.batteryPoints[0].title == "Technik", "Removing a draft point removes its mirrored statistic on save")
        data.batteryPoints.append(BatteryPoint(date: now, title: "technik", direction: .gives, impact: 3))
        data.batteryPoints.append(BatteryPoint(date: now, title: "Technik", direction: .takes, impact: 5))
        let grouped = InsightsAnalytics.keywords(data: data, period: .week(containing: now))
        try expect(grouped.count == 2 && grouped.first { $0.direction == .gives }?.count == 2, "Case-insensitive keywords keep giver and taker separate")
        try expect(grouped.first { $0.direction == .gives }?.impact == 7, "Self-reported impact aggregation")
        let row = WellnessAnalytics.daily(data, period: .week(containing: now))[0]
        try expect(row.mood == 4 && row.battery == 1, "Fine mood and zero-percent battery preserve chart scale")
        try expect(MoodBarometer.score(-3) == 1 && MoodBarometer.score(120) == 5, "Barometer endpoints clamp")
        try expect(InsightsAnalytics.comparison(data: data, now: now)?.reference == nil, "Insufficient baseline not labelled unusual")
        for offset in 1...7 { let day = cal.date(byAdding: .day, value: -offset, to: now)!; data.moodCheckIns.append(MoodCheckIn(date: day, mood: 2, battery: 3)) }
        try expect(InsightsAnalytics.comparison(data: data, now: now)?.difference == 2, "Latest daily mean compared to earlier observed days")
        data.moodCheckIns.append(MoodCheckIn(date: now.addingTimeInterval(86400), mood: 1, battery: 1))
        try expect(InsightsAnalytics.comparison(data: data, now: now)?.latest == 4, "Future entries excluded from personal comparison")
        data.companionSettings.checkInReminders = [CheckInReminder(kind: .free, time: RoutineTime(hour: 15), alarmEnabled: true, slotID: custom.id)]
        let slots = CheckInReminderPlanner.slots(data: data, now: now, calendar: cal)
        try expect(slots.count == 7 && slots.allSatisfy { $0.slotID == custom.id && $0.title == "Ruhe" }, "Custom timed reminder plans seven days with routing title")
        let alarms = CompanionAlarmPlanner.candidates(data, now: now, calendar: cal)
        try expect(alarms.count == 7 && alarms.allSatisfy { $0.route.contains(custom.id.uuidString) }, "Optional check-in alarms route by slot identity")
        data.companionSettings.checkInReminders?[0].alarmEnabled = false
        try expect(CompanionAlarmPlanner.candidates(data, now: now, calendar: cal).isEmpty, "Alarm switch off removes desired alarms")
        let many = (0..<100).map { CompanionAlarmSlot(id: "\($0)", group: "g\($0 % 5)", fireAt: now.addingTimeInterval(Double($0)), title: "A", route: "x") }
        let admitted = CompanionAlarmPlanner.admitted(many)
        try expect(admitted.count == 24 && Set(admitted.map(\.id)).count == 24 && Set(admitted.map(\.group)).count == 5, "Alarm inventory bounded, unique and groups covered")
        try expect(CompanionAlarmPlanner.admitted(many, budget: 0).isEmpty, "Zero inventory budget")
        var taskData = AppData()
        let week = now.therapyWeek
        taskData.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: week.week, yearForWeekOfYear: week.year, title: "PRIVATE", details: "", reminder: TaskReminder(hour: 15, alarmEnabled: true))]
        let taskAlarms = CompanionAlarmPlanner.candidates(taskData, now: now, calendar: cal)
        try expect(taskAlarms.count == 7 && taskAlarms.allSatisfy { !$0.title.contains("PRIVATE") && $0.fireAt > now }, "Task alarms cover seven days and respect private titles")
        taskData.weeklyTasks[0].completed = true
        try expect(CompanionAlarmPlanner.candidates(taskData, now: now, calendar: cal).isEmpty, "Completing task removes all desired task alarms")
        taskData.companionSettings.sessionAlarmsEnabled = true
        taskData.sessionPreferences.notifyAtPhases = true
        taskData.currentSession = RunningTherapySession.start(TherapySessionTemplate(), at: now)
        let sessionSlots = CompanionAlarmPlanner.candidates(taskData, now: now, calendar: cal)
        try expect(sessionSlots.count == taskData.currentSession!.phases.count && sessionSlots.allSatisfy { $0.route.hasPrefix("session|") && $0.fireAt > now }, "Timer end and phase alarms use active session timeline")
        taskData.currentSession?.pause(at: now.addingTimeInterval(10))
        try expect(CompanionAlarmPlanner.candidates(taskData, now: now, calendar: cal).isEmpty, "Paused therapy timer cancels alarms")
        taskData.currentSession = nil
        taskData.wellnessSettings.reminderEnabled = true; taskData.companionSettings.wellnessAlarmEnabled = true
        try expect(CompanionAlarmPlanner.candidates(taskData, now: now, calendar: cal).count == 1, "Weekly mood reminder has independent opt-in alarm")
        var nightData = AppData(); nightData.companionSettings.dayCheckInSlots = defaults.map { value in var value = value; if value.kind == .night { value.enabled = true }; return value }
        nightData.companionSettings.checkInReminders = [CheckInReminder(kind: .night, time: RoutineTime(hour: 4), slotID: night.id)]
        let nightNow = date("2026-10-01T01:00:00Z")
        nightData.guidedCheckIns = [GuidedCheckIn(date: date("2026-09-30T21:30:00Z"), kind: .night, isDraft: false, daySlotID: night.id)]
        let nightSlots = CheckInReminderPlanner.slots(data: nightData, now: nightNow, calendar: cal)
        try expect(!nightSlots.contains { cal.isDate($0.fireAt, inSameDayAs: nightNow) } && nightSlots.count == 6, "Completed night suppresses only its shared overnight window")
        data.notes = [TherapyNote(createdAt: now, title: "SECRET", text: "Private text", tags: [])]
        var options = WeeklyPrintOptions(weekStart: now.therapyWeekStart, includeName: false, includeBattery: false, includeCheckIns: false, includeTasks: false, includeGoals: false, includeRoutines: false, includeNotes: false)
        let plan = WeeklyPrintPlan.make(data: data, options: options)
        try expect(plan.name.isEmpty && plan.rows.isEmpty && plan.daily.allSatisfy { $0.battery == nil }, "PDF opt-outs omit names, notes and battery")
        options.includeNotes = true
        try expect(WeeklyPrintPlan.make(data: data, options: options).rows.contains { $0.title.contains("SECRET") }, "PDF explicitly chosen notes included")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppData())) as! [String: Any]
        legacy["schemaVersion"] = 7
        let restored = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(restored.schemaVersion == 16 && restored.companionSettings.dayCheckInSlots == nil && restored.companionSettings.taskAlarmsEnabled == nil, "Schema 7 adds safe optional defaults")
        print("Passed \(count) insights, timed check-in, atomic battery, alarm inventory and PDF selection checks.")
    }
}
