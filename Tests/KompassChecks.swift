import Foundation

@main
struct KompassChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ text: String) throws {
        count += 1; if try !value() { throw Failure.assertion(text) }
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let encoder = BackupArchive.encoder(), decoder = BackupArchive.decoder()
        let now = date("2026-11-04T10:00:00Z") // Wednesday 11:00 in Berlin

        // MARK: Schema 19 migration and defaults
        var legacy = AppData()
        legacy.dashboard.cardOrder = ["welcome", "appointment", "routines"]
        var json = try JSONSerialization.jsonObject(with: encoder.encode(legacy)) as! [String: Any]
        for key in ["quietMode", "surface", "assistedLivingSettings", "assistedLivingAppointments", "assistedLivingTopics", "assistedLivingGoals"] { json.removeValue(forKey: key) }
        json["schemaVersion"] = 18
        let migrated = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        try expect(migrated.schemaVersion == 19, "Schema 18 data opens as schema 19")
        try expect(migrated.quietMode == QuietModeSettings() && migrated.surface == SurfacePreferences(), "Quiet mode and glass default safely")
        try expect(migrated.assistedLivingAppointments.isEmpty && migrated.assistedLivingTopics.isEmpty && migrated.assistedLivingGoals.isEmpty && migrated.assistedLivingSettings == AssistedLivingSettings(), "BeWo starts empty for existing data")
        try expect(migrated.dashboard.cardOrder == ["welcome", "appointment", "assistedLiving", "routines"], "BeWo card appears right after the therapy appointment")
        try expect(migrated.surface.style == .soft && migrated.surface.coverage > 0.6, "Existing users get the calmer, less transparent glass")
        json["schemaVersion"] = 20
        do { _ = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json)); throw Failure.assertion("Future schema 20 accepted") } catch is DecodingError { count += 1 }
        let partialTopic = try decoder.decode(AssistedLivingTopic.self, from: Data(#"{"title":"Brief vom Amt"}"#.utf8))
        try expect(partialTopic.title == "Brief vom Amt" && partialTopic.status == .next && partialTopic.priority == 2, "BeWo topics decode with missing fields")
        let partialSurface = try decoder.decode(SurfacePreferences.self, from: Data(#"{"style":"glass","coverage":7}"#.utf8))
        try expect(partialSurface.style == .glass && partialSurface.coverage == 1 && partialSurface.tintStrength == 0.5, "Surface values clamp and default")
        let quietJSON = String(decoding: try encoder.encode(QuietPause(categories: [.tasks])), as: UTF8.self)
        try expect(quietJSON.contains("\"areas\"") && !quietJSON.contains("\"categories\""), "Quiet areas use an unambiguous readable key")

        // MARK: Quiet policy
        var quiet = QuietModeSettings()
        QuietPolicy.pause(&quiet, categories: [], until: now.addingTimeInterval(86400), now: now)
        let inPause = now.addingTimeInterval(3600), afterPause = now.addingTimeInterval(86400 + 60)
        try expect(QuietPolicy.reason(category: .routines, source: "routine.x", id: "a", fireAt: inPause, settings: quiet, calendar: calendar) != nil, "24 h rest silences routines")
        try expect(QuietPolicy.reason(category: .tasks, source: "task.x", id: "b", fireAt: afterPause, settings: quiet, calendar: calendar) == nil, "Reminders return after the rest")
        try expect(QuietPolicy.reason(category: .wake, source: "wake.x", id: "c", fireAt: inPause, settings: quiet, calendar: calendar) == nil, "Wake alarms keep ringing during a general rest by default")
        try expect(QuietPolicy.reason(category: .session, source: "session", id: "d", fireAt: inPause, settings: quiet, calendar: calendar) == nil, "A running session keeps its hints by default")
        var strict = quiet; strict.wakeAlarmsIgnorePause = false
        try expect(QuietPolicy.reason(category: .wake, source: "wake.x", id: "c", fireAt: inPause, settings: strict, calendar: calendar) != nil, "Wake exemption can be switched off")
        let pauseID = quiet.pauses[0].id
        QuietPolicy.end(pauseID, in: &quiet, now: now.addingTimeInterval(1800))
        try expect(QuietPolicy.reason(category: .routines, source: "routine.x", id: "a", fireAt: inPause, settings: quiet, calendar: calendar) == nil, "Ending the rest early restores reminders immediately")
        try expect(QuietPolicy.reason(category: .routines, source: "routine.x", id: "a", fireAt: now.addingTimeInterval(900), settings: quiet, calendar: calendar) != nil, "Reminders before the early end stay silenced")
        try expect(quiet.pauses[0].endedAt != nil && QuietPolicy.globalPause(quiet, at: now.addingTimeInterval(3600)) == nil, "Ended rest stays in history but is inactive")
        QuietPolicy.pause(&quiet, categories: [], until: now.addingTimeInterval(3600), now: now)
        QuietPolicy.extend(quiet.pauses[0].id, in: &quiet, by: 3600 * 23, now: now)
        try expect(quiet.pauses[0].until == now.addingTimeInterval(86400), "Extending the rest moves its end")
        QuietPolicy.pause(&quiet, categories: [], until: nil, now: now.addingTimeInterval(60))
        try expect(QuietPolicy.activePauses(quiet, at: now.addingTimeInterval(120)).filter(\.isGlobal).count == 1, "A new general rest replaces the old one")
        try expect(QuietPolicy.reason(category: .therapy, source: "therapy", id: "e", fireAt: now.addingTimeInterval(86400 * 30), settings: quiet, calendar: calendar) != nil, "An open rest lasts until it is ended")
        QuietPolicy.endAll(&quiet, now: now.addingTimeInterval(180))
        try expect(QuietPolicy.activePauses(quiet, at: now.addingTimeInterval(200)).isEmpty, "Ending everything leaves no active rest")

        var partial = QuietModeSettings()
        QuietPolicy.pause(&partial, categories: [.checkIns, .tasks], until: now.addingTimeInterval(7200), now: now)
        try expect(QuietPolicy.reason(category: .checkIns, source: "checkin.morning", id: "f", fireAt: inPause, settings: partial, calendar: calendar) != nil, "Area rest silences check-ins")
        try expect(QuietPolicy.reason(category: .routines, source: "routine.y", id: "g", fireAt: inPause, settings: partial, calendar: calendar) == nil, "Area rest leaves other areas alone")
        partial.mutedCategories = [.wellbeing]
        try expect(QuietPolicy.reason(category: .wellbeing, source: "energy", id: "h", fireAt: now.addingTimeInterval(86400 * 300), settings: partial, calendar: calendar) == "Dauerhaft stumm", "Muted area stays silent")

        var single = QuietModeSettings()
        QuietPolicy.silence(&single, key: "therapy.routine.1.2.3.4", wholeSource: false, title: "Tablette", category: .routines, until: nil, now: now)
        try expect(QuietPolicy.reason(category: .routines, source: "routine.1", id: "therapy.routine.1.2.3.4", fireAt: inPause, settings: single, calendar: calendar) != nil, "One occurrence can be skipped")
        try expect(QuietPolicy.reason(category: .routines, source: "routine.1", id: "therapy.routine.1.2.3.5", fireAt: inPause, settings: single, calendar: calendar) == nil, "Skipping one occurrence keeps the others")
        QuietPolicy.silence(&single, key: "routine.1", wholeSource: true, title: "Tablette", category: .routines, until: now.addingTimeInterval(86400), now: now)
        try expect(QuietPolicy.reason(category: .routines, source: "routine.1", id: "other", fireAt: inPause, settings: single, calendar: calendar) != nil, "A whole source can rest for 24 hours")
        try expect(QuietPolicy.reason(category: .routines, source: "routine.1", id: "other", fireAt: afterPause, settings: single, calendar: calendar) == nil, "Source silence expires")
        QuietPolicy.prune(&single, now: now.addingTimeInterval(86400 * 3))
        try expect(single.silenced.count == 1 && single.silenced[0].until == nil, "Expired silences are pruned, open ones kept")

        // Quiet hours across the daylight-saving switch (29 March 2026) and New Year.
        var hours = QuietHours(); hours.enabled = true
        for day in ["2026-03-28", "2026-03-29", "2026-10-25", "2026-12-31", "2027-01-01"] {
            let late = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: Int(day.prefix(4))!, month: Int(day.dropFirst(5).prefix(2))!, day: Int(day.suffix(2))!, hour: 23, minute: 30))!
            let early = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: Int(day.prefix(4))!, month: Int(day.dropFirst(5).prefix(2))!, day: Int(day.suffix(2))!, hour: 6, minute: 59))!
            let open = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: Int(day.prefix(4))!, month: Int(day.dropFirst(5).prefix(2))!, day: Int(day.suffix(2))!, hour: 7, minute: 0))!
            try expect(hours.contains(late, calendar: calendar) && hours.contains(early, calendar: calendar) && !hours.contains(open, calendar: calendar), "Overnight quiet hours hold on " + day)
        }

        // MARK: Task reminders under quiet mode
        let slot = TaskReminderSlot(taskID: UUID(), weekday: nil, hour: 18, minute: 0)
        try expect(ReminderInventory.taskPlan(slot, settings: QuietModeSettings(), now: now, calendar: calendar) == .repeating, "Without rest a task repeats")
        var dayRest = QuietModeSettings(); QuietPolicy.pause(&dayRest, categories: [], until: now.addingTimeInterval(86400), now: now)
        let expected = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 5, hour: 18))!
        try expect(ReminderInventory.taskPlan(slot, settings: dayRest, now: now, calendar: calendar) == .once(expected), "A 24 h rest delivers the first task reminder after it once")
        var mutedTasks = QuietModeSettings(); mutedTasks.mutedCategories = [.tasks]
        try expect(ReminderInventory.taskPlan(slot, settings: mutedTasks, now: now, calendar: calendar) == .none, "Muted tasks schedule nothing")
        var nightly = QuietModeSettings(); nightly.quietHours.enabled = true; nightly.quietHours.startHour = 17
        try expect(ReminderInventory.taskPlan(slot, settings: nightly, now: now, calendar: calendar) == .none, "A task inside daily quiet hours never fires")
        let dstDates = ReminderInventory.nextDates(weekday: nil, hour: 2, minute: 30, after: date("2026-03-28T12:00:00Z"), count: 3, calendar: calendar)
        try expect(dstDates.count == 3 && Set(dstDates.map { calendar.component(.day, from: $0) }).count == 3, "Daily dates skip nothing and never double across DST")

        // MARK: Alarms honour quiet mode
        var alarmData = AppData()
        alarmData.schedule.weekday = 5; alarmData.schedule.hour = 15; alarmData.schedule.therapyAlarmsEnabled = true
        alarmData.schedule.reminderOffsetsMinutes = [60]
        let raw = CompanionAlarmPlanner.rawCandidates(alarmData, now: now, calendar: calendar)
        try expect(!raw.isEmpty && CompanionAlarmPlanner.candidates(alarmData, now: now, calendar: calendar).count == raw.count, "Therapy alarms are planned without rest")
        QuietPolicy.pause(&alarmData.quietMode, categories: [.therapy], until: nil, now: now)
        try expect(CompanionAlarmPlanner.candidates(alarmData, now: now, calendar: calendar).isEmpty, "Resting therapy alarms removes them from AlarmKit")
        let planned = ReminderInventory.upcoming(alarmData, now: now, days: 7, calendar: calendar)
        try expect(!planned.isEmpty && planned.allSatisfy { $0.category != .therapy || $0.isQuiet }, "The overview shows silenced alarms as resting")

        // MARK: Betreutes Wohnen planning
        var bewo = AppData()
        let anchor = date("2026-10-26T09:00:00Z")
        let visit = AssistedLivingRegularVisit(weekday: 3, hour: 10, minute: 0, everyWeeks: 2, anchor: anchor, durationMinutes: 90)
        bewo.assistedLivingSettings.regularVisits = [visit]
        let visits = AssistedLivingPlanner.upcoming(bewo, now: now, days: 42, calendar: calendar)
        try expect(visits.count == 3, "Bi-weekly visits over six weeks")
        try expect(visits.allSatisfy { calendar.component(.weekday, from: $0.date) == 3 && calendar.component(.hour, from: $0.date) == 10 }, "Regular visits keep their weekday and wall clock")
        try expect(visits[0].date == calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 10, hour: 10)), "Rhythm counts ISO weeks from its anchor")
        let springVisit = AssistedLivingRegularVisit(weekday: 2, hour: 10, minute: 0, everyWeeks: 1, anchor: date("2026-03-16T09:00:00Z"))
        let spring = AssistedLivingPlanner.regularDates(springVisit, from: date("2026-03-20T00:00:00Z"), to: date("2026-04-10T00:00:00Z"), calendar: calendar)
        try expect(spring.count == 3 && spring.allSatisfy { calendar.component(.hour, from: $0) == 10 }, "Weekly visits stay at 10:00 across the DST change")
        let winterVisit = AssistedLivingRegularVisit(weekday: 2, hour: 9, minute: 30, everyWeeks: 1, anchor: date("2026-12-01T09:00:00Z"))
        let winter = AssistedLivingPlanner.regularDates(winterVisit, from: date("2026-12-27T00:00:00Z"), to: date("2027-01-12T00:00:00Z"), calendar: calendar)
        try expect(winter.count == 3 && calendar.component(.year, from: winter[0]) == 2026 && calendar.component(.year, from: winter[2]) == 2027 && winter.allSatisfy { calendar.component(.minute, from: $0) == 30 }, "Visits continue across the year boundary")
        bewo.assistedLivingSettings.skippedRegularDates = [visits[0].date]
        try expect(AssistedLivingPlanner.upcoming(bewo, now: now, days: 42, calendar: calendar).count == 2, "A skipped visit disappears")
        bewo.assistedLivingSettings.skippedRegularDates = []
        var stored = AssistedLivingPlanner.materialize(visits[0], settings: bewo.assistedLivingSettings, now: now)
        stored.topicIDs = [UUID()]
        bewo.assistedLivingAppointments = [stored]
        let merged = AssistedLivingPlanner.upcoming(bewo, now: now, days: 42, calendar: calendar)
        try expect(merged.count == 3 && merged[0].appointmentID == stored.id, "An opened visit replaces its regular slot instead of doubling")
        bewo.assistedLivingSettings.reminderOffsetsMinutes = [1440, 60, 60, 99999]
        let reminders = AssistedLivingPlanner.reminderSlots(bewo, now: now, calendar: calendar)
        try expect(reminders.count == 4 && reminders.allSatisfy { $0.fireAt > now } && reminders[0].fireAt == merged[0].date.addingTimeInterval(-86400), "BeWo reminders deduplicate and validate offsets")
        bewo.assistedLivingSettings.remindersEnabled = false
        try expect(AssistedLivingPlanner.reminderSlots(bewo, now: now, calendar: calendar).isEmpty, "BeWo reminders can be switched off")

        var topic = AssistedLivingTopic(title: "Antrag Wohngeld", priority: 3, status: .next)
        let openTopic = AssistedLivingTopic(title: "Wäsche", priority: 1, status: .open)
        bewo.assistedLivingTopics = [openTopic, topic]
        try expect(AssistedLivingPlanner.openTopics(bewo).map(\.title) == ["Antrag Wohngeld", "Wäsche"], "Topics for the next visit come first")
        AssistedLivingPlanner.discuss(topic.id, in: stored.id, data: &bewo, outcome: "Formular ausgefüllt", now: now)
        topic = bewo.assistedLivingTopics.first { $0.id == topic.id }!
        try expect(topic.status == .discussed && topic.appointmentID == stored.id && topic.outcome == "Formular ausgefüllt" && bewo.assistedLivingAppointments[0].topicIDs.contains(topic.id), "Discussing links topic and visit")
        bewo.assistedLivingAppointments[0].agreements = [AssistedLivingAgreement(title: "Unterlagen kopieren", owner: .me, dueDate: now.addingTimeInterval(86400 * 5)), AssistedLivingAgreement(title: "Termin beim Amt", owner: .caregiver), AssistedLivingAgreement(title: "Erledigt", done: true)]
        let agreements = AssistedLivingPlanner.openAgreements(bewo)
        try expect(agreements.count == 2 && agreements[0].agreement.title == "Unterlagen kopieren", "Open agreements sorted by due date")
        let goal = AssistedLivingGoal(title: "Post öffnen", steps: [AssistedLivingStep(title: "Briefkasten", done: true), AssistedLivingStep(title: "Sortieren")])
        try expect(abs(goal.progress - 0.5) < 0.001, "Goal progress follows steps")

        bewo.remindersQuietCheck()

        // MARK: Backup round-trip and readable mirror
        var full = bewo
        full.assistedLivingGoals = [goal]
        full.surface.style = .solid; full.surface.coverage = 0.9
        full.quietMode = quiet; full.quietMode.quietHours.enabled = true
        QuietPolicy.silence(&full.quietMode, key: "task.1", wholeSource: true, title: "Aufgabe", category: .tasks, until: nil, now: now)
        let restored = try decoder.decode(AppData.self, from: encoder.encode(full))
        let restoredJSON = try JSONSerialization.jsonObject(with: encoder.encode(restored)) as! NSDictionary
        let fullJSON = try JSONSerialization.jsonObject(with: encoder.encode(full)) as! NSDictionary
        try expect(restoredJSON == fullJSON && restored.assistedLivingTopics.count == 2 && restored.quietMode.silenced.count == 1 && restored.surface.style == .solid, "All Kompass fields survive encoding")
        let root = try BackupArchive.privateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReadableBackup.writeEntries(data: full, root: root)
        let topicFile = root.appendingPathComponent("Eintraege/assistedLivingTopics/" + topic.id.uuidString + ".txt")
        try expect(try String(contentsOf: topicFile, encoding: .utf8).contains("Formular ausgefüllt"), "BeWo topics appear in the readable mirror")
        let appointmentFile = root.appendingPathComponent("Eintraege/assistedLivingAppointments/" + stored.id.uuidString + ".txt")
        try expect(try String(contentsOf: appointmentFile, encoding: .utf8).contains("Absprachen"), "BeWo visits list their agreements readably")
        let quietFile = try String(contentsOf: root.appendingPathComponent("Eintraege/Einstellungen/quietMode.txt"), encoding: .utf8)
        try expect(quietFile.contains("Ruhephasen") && quietFile.contains("Bereiche") && quietFile.contains("Einzeln stummgeschaltet"), "Quiet mode appears in the readable mirror")
        let surfaceFile = try String(contentsOf: root.appendingPathComponent("Eintraege/Einstellungen/surface.txt"), encoding: .utf8)
        try expect(surfaceFile.contains("Deckkraft der Karten"), "Glass preferences appear in the readable mirror")

        print("Passed \(count) Kompass checks: schema 19 migration, quiet mode (rest, early end, areas, single reminders, quiet hours across DST/New Year), task and alarm planning, BeWo rhythms, topics, agreements and readable backup.")
    }
}

extension AppData {
    /// BeWo reminders must also respect quiet mode in the shared overview.
    mutating func remindersQuietCheck() {
        assistedLivingSettings.remindersEnabled = true
        assistedLivingSettings.reminderOffsetsMinutes = [60]
        let now = assistedLivingAppointments.first?.date.addingTimeInterval(-86400) ?? Date()
        QuietPolicy.pause(&quietMode, categories: [.assistedLiving], until: nil, now: now)
        let items = ReminderInventory.upcoming(self, now: now, days: 7).filter { $0.category == .assistedLiving }
        precondition(!items.isEmpty && items.allSatisfy(\.isQuiet), "BeWo reminders rest with their area")
        QuietPolicy.endAll(&quietMode, now: now)
    }
}
