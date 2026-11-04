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

        // MARK: AI: Kompass actions, context and local date detection
        var ai = AppData()
        ai.assistedLivingSettings.caregiverName = "Frau Beispiel"
        let reply = AIBuddyMessage(role: "assistant", text: "Vorschlag")
        ai.aiMessages = [reply]
        let visitISO = "2026-11-10T09:00:00Z"
        let bewoVisit = AIBuddyAction(kind: .bewoAppointment, title: "Hausbesuch", text: "Post mitbringen", dateISO: visitISO, minutes: 90, weekdays: [], options: AIBuddyActionOptions(valueString: "homeVisit"))
        try expect(bewoVisit.valid, "BeWo appointment proposal is valid")
        try expect(!AIBuddyAction(kind: .bewoAppointment, title: "Ohne Zeit", text: "", weekdays: []).valid, "BeWo appointment needs a date")
        try expect(!AIBuddyAction(kind: .bewoTopic, title: "Thema", text: "", weekdays: [], options: AIBuddyActionOptions(categories: ["tasks"])).valid, "Quiet areas are rejected outside quietStart")
        try expect(!AIBuddyAction(kind: .method, title: "Methode", text: "", weekdays: [], options: AIBuddyActionOptions(categories: ["tasks"])).valid, "Methods keep battery categories only")
        try AIBuddyMutation.apply(bewoVisit, originalID: bewoVisit.id, messageID: reply.id, to: &ai, now: now)
        try expect(ai.assistedLivingAppointments.count == 1 && ai.assistedLivingAppointments[0].durationMinutes == 90 && ai.assistedLivingAppointments[0].caregiver == "Frau Beispiel" && ai.assistedLivingAppointments[0].preparation == "Post mitbringen", "AI creates a BeWo visit with defaults")
        do { try AIBuddyMutation.apply(bewoVisit, originalID: bewoVisit.id, messageID: reply.id, to: &ai, now: now); throw Failure.assertion("Applied twice") } catch is AIBuddyAPIError { count += 1 }
        let topicAction = AIBuddyAction(kind: .bewoTopic, title: "Brief vom Jobcenter", text: "Frist 20.11.", weekdays: [], options: AIBuddyActionOptions(valueString: "authorities", priority: "high"))
        try AIBuddyMutation.apply(topicAction, originalID: topicAction.id, messageID: reply.id, to: &ai, now: now)
        try expect(ai.assistedLivingTopics.first?.priority == 3 && ai.assistedLivingTopics.first?.category == .authorities && ai.assistedLivingTopics.first?.status == .next, "AI BeWo topic keeps category and priority")
        let duplicate = AIBuddyAction(kind: .bewoTopic, title: "brief vom jobcenter", text: "", weekdays: [])
        do { try AIBuddyMutation.apply(duplicate, originalID: duplicate.id, messageID: reply.id, to: &ai, now: now); throw Failure.assertion("Duplicate topic") } catch is AIBuddyAPIError { count += 1 }
        let agreement = AIBuddyAction(kind: .bewoAgreement, title: "Kopien machen", text: "", weekdays: [], options: AIBuddyActionOptions(valueString: "me"))
        try AIBuddyMutation.apply(agreement, originalID: agreement.id, messageID: reply.id, to: &ai, now: now)
        try expect(ai.assistedLivingAppointments[0].agreements.map(\.title) == ["Kopien machen"], "Agreement lands on the next visit when none is named")
        let discuss = AIBuddyAction(kind: .discussBewoTopic, title: "", text: "Antrag gestellt", targetID: ai.assistedLivingTopics[0].id.uuidString, weekdays: [])
        try AIBuddyMutation.apply(discuss, originalID: discuss.id, messageID: reply.id, to: &ai, now: now)
        try expect(ai.assistedLivingTopics[0].status == .discussed && ai.assistedLivingTopics[0].outcome == "Antrag gestellt", "AI marks a BeWo topic as discussed")
        let rest = AIBuddyAction(kind: .quietStart, title: "", text: "Krank", minutes: 1440, weekdays: [], options: AIBuddyActionOptions(categories: ["tasks", "routines"]))
        try expect(rest.valid, "Quiet proposal with areas is valid")
        try AIBuddyMutation.apply(rest, originalID: rest.id, messageID: reply.id, to: &ai, now: now)
        try expect(QuietPolicy.activePauses(ai.quietMode, at: now.addingTimeInterval(60)).first?.until == now.addingTimeInterval(86400) && QuietPolicy.isQuiet(.tasks, settings: ai.quietMode, at: now.addingTimeInterval(60)), "AI starts a 24 h rest for chosen areas")
        let wake = AIBuddyAction(kind: .quietEnd, title: "", text: "", weekdays: [])
        try AIBuddyMutation.apply(wake, originalID: wake.id, messageID: reply.id, to: &ai, now: now.addingTimeInterval(120))
        try expect(QuietPolicy.activePauses(ai.quietMode, at: now.addingTimeInterval(180)).isEmpty, "AI ends the rest early")
        let goalAction = AIBuddyAction(kind: .bewoGoal, title: "Post öffnen", text: "", weekdays: [], options: AIBuddyActionOptions(steps: ["Briefkasten leeren", "Sortieren"]))
        try AIBuddyMutation.apply(goalAction, originalID: goalAction.id, messageID: reply.id, to: &ai, now: now)
        try expect(ai.assistedLivingGoals.first?.steps.count == 2, "AI BeWo goal keeps its steps")
        try expect(ai.aiMessages[0].appliedActionIDs.count == 7, "Every applied proposal is recorded once")
        let schemaKinds = ((((AIBuddyAPI.schema["properties"] as! [String: Any])["actions"] as! [String: Any])["items"] as! [String: Any])["properties"] as! [String: Any])["kind"] as! [String: Any]
        try expect((schemaKinds["enum"] as! [String]).contains("bewoAppointment") && (schemaKinds["enum"] as! [String]).contains("quietStart"), "The response schema offers the new actions")
        try expect(AIBuddyAPI.fullInstructions.contains("TERMINERKENNUNG") && !AIBuddyAPI.fullInstructions.contains("Aktuelle Zeit:"), "Static, cacheable instructions include appointment detection")
        let bewoContext = AIBuddyContext.make(data: ai, days: 7, end: now, calendar: calendar, question: "Was steht beim BeWo an?", clock: now)
        try expect(bewoContext.text.contains("BETREUTES WOHNEN") && bewoContext.text.contains("Thema-ID " + ai.assistedLivingTopics[0].id.uuidString) == false && bewoContext.text.contains("Absprache offen"), "BeWo context lists open items with IDs")
        let plainContext = AIBuddyContext.make(data: ai, days: 7, end: now, calendar: calendar, question: "Ich habe Kopfschmerzen", clock: now)
        try expect(!plainContext.text.contains("BETREUTES WOHNEN") && plainContext.text.contains("nächster BeWo-Termin"), "Unrelated questions only get the one-line BeWo situation")
        QuietPolicy.pause(&ai.quietMode, categories: [], until: now.addingTimeInterval(3600), now: now)
        let quietContext = AIBuddyContext.make(data: ai, days: 1, end: now, calendar: calendar, question: "Die Wecker nerven", clock: now)
        try expect(quietContext.text.contains("RUHEMODUS") && quietContext.text.contains("Ruhe-ID"), "Quiet questions get quiet context")

        let wednesday = date("2026-11-04T10:00:00Z") // Wednesday 11:00 Berlin
        func detected(_ text: String) -> DetectedDate? { GermanDateDetector.detect(text, now: wednesday, calendar: calendar) }
        func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: y, month: m, day: d, hour: h, minute: min))! }
        try expect(detected("Dienstag um 10 kommt meine Betreuerin") == DetectedDate(date: local(2026, 11, 10, 10), hasTime: true, hint: .assistedLiving), "Weekday with time and BeWo hint")
        try expect(detected("morgen um 9:30 Jobcenter")?.date == local(2026, 11, 5, 9, 30), "Tomorrow with minutes")
        try expect(detected("Am 12.11. um 14 Uhr Therapie") == DetectedDate(date: local(2026, 11, 12, 14), hasTime: true, hint: .therapy), "Explicit date with therapy hint")
        try expect(detected("Arzttermin am 3. Januar 8 Uhr")?.date == local(2027, 1, 3, 8), "Month names roll into next year")
        try expect(detected("Mittwoch um 9 Termin")?.date == local(2026, 11, 11, 9), "A passed time today moves to next week")
        try expect(detected("Mittwoch um 18 Termin")?.date == local(2026, 11, 4, 18), "A later time today stays today")
        try expect(detected("nächste Woche Montag Termin beim Amt")?.date == local(2026, 11, 9, 9) && detected("nächste Woche Montag Termin beim Amt")?.hasTime == false, "Next week without time defaults to 9:00 and asks for the time")
        try expect(detected("Guten Morgen, heute war schön") == nil && detected("Ich bin müde") == nil, "Plain sentences are not appointments")
        try expect(detected("Freitag um 3 nachmittags Termin")?.date == local(2026, 11, 6, 15), "Afternoon hint shifts to 15:00")
        let springBoundary = GermanDateDetector.detect("Sonntag um 2:30 Termin", now: date("2026-03-27T12:00:00Z"), calendar: calendar)
        try expect(springBoundary != nil && calendar.component(.day, from: springBoundary!.date) == 29, "Detection survives the DST gap")

        print("Passed \(count) Kompass checks: schema 19 migration, quiet mode (rest, early end, areas, single reminders, quiet hours across DST/New Year), task and alarm planning, BeWo rhythms, topics, agreements, readable backup, AI actions, context and German date detection.")
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
