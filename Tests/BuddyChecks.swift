import Foundation

final class BuddyMockProtocol: URLProtocol {
    static var responses: [Data] = []
    static var requests: [[String: Any]] = []
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody
        if bytes == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096), body = Data()
            while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; body.append(contentsOf: buffer.prefix(size)) }
            bytes = body
        }
        if let body = bytes, let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { Self.requests.append(value) }
        let raw = Self.responses.isEmpty ? Data("{}".utf8) : Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: raw); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct BuddyChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !value() { throw Failure.assertion(message) } }
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    static func response(_ reply: AIBuddyReply) throws -> Data {
        let text = String(decoding: try JSONEncoder().encode(reply), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]], "usage": ["input_tokens": 500, "output_tokens": 200]])
    }
    static func main() async throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        var cal = Calendar.therapyCalendar; cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-10-01T12:00:00Z")
        var data = AppData()
        let morning = DailyCheckInSlot.defaults[0], night = DailyCheckInSlot.defaults[4]
        let first = DayCheckInPolicy.entry(morning, at: date("2026-10-01T05:00:00Z"))
        try expect(GuidedCheckInMutation.apply(first, complete: true, to: &data), "First check-in saved")
        let duplicate = DayCheckInPolicy.entry(morning, at: date("2026-10-01T06:00:00Z"))
        let preserved = data
        try expect(!GuidedCheckInMutation.apply(duplicate, complete: true, to: &data) && data == preserved, "Duplicate rejected atomically, no lost original or extra tasks")
        try expect(DayCheckInPolicy.reopen(duplicate, in: data).id == first.id, "Every entry point reopens completed check-in")
        var edit = first; edit.summary = "Korrigiert"
        try expect(GuidedCheckInMutation.apply(edit, complete: true, to: &data) && data.guidedCheckIns.count == 1 && data.guidedCheckIns[0].summary == "Korrigiert", "Explicit edits preserve identity")
        let tomorrow = DayCheckInPolicy.entry(morning, at: date("2026-10-02T05:00:00Z"))
        try expect(GuidedCheckInMutation.apply(tomorrow, complete: true, to: &data), "Following day remains available")
        var shifted = first; shifted.date = tomorrow.date
        let beforeShift = data
        try expect(!GuidedCheckInMutation.apply(shifted, complete: true, to: &data) && data == beforeShift, "Moving an existing check-in into an occupied day cannot create a duplicate")
        let beforeMidnight = DayCheckInPolicy.entry(night, at: date("2026-09-30T21:30:00Z"))
        try expect(GuidedCheckInMutation.apply(beforeMidnight, complete: true, to: &data), "Night before midnight saved")
        let afterMidnight = DayCheckInPolicy.entry(night, at: date("2026-10-01T01:00:00Z"))
        try expect(!GuidedCheckInMutation.apply(afterMidnight, complete: true, to: &data), "Night spans midnight without duplicate")
        let customA = DailyCheckInSlot(name: "A", startHour: 0, endHour: 0), customB = DailyCheckInSlot(name: "B", startHour: 0, endHour: 0)
        data.companionSettings.dayCheckInSlots = [customA, customB]
        try expect(GuidedCheckInMutation.apply(DayCheckInPolicy.entry(customA, at: now), complete: false, to: &data) && GuidedCheckInMutation.apply(DayCheckInPolicy.entry(customB, at: now), complete: false, to: &data), "Custom slots counted independently")
        data.companionSettings.allowMultipleCheckInsPerSlot = true
        try expect(GuidedCheckInMutation.apply(DayCheckInPolicy.entry(customA, at: now), complete: true, to: &data), "Explicit multiple-entry preference respected")
        data = AppData()
        let rawMood = MoodCheckIn(date: date("2026-10-01T05:00:00Z"), mood: 4)
        data.moodCheckIns = [rawMood]
        try expect(MoodDailyPolicy.existing(for: MoodCheckIn(date: date("2026-10-01T06:00:00Z")), in: data)?.id == rawMood.id, "Standalone mood check-in reopens its daily slot")
        try expect(MoodDailyPolicy.existing(for: MoodCheckIn(date: date("2026-10-01T12:00:00Z")), in: data) == nil, "Another daily mood slot is available")
        data = AppData()
        data.schedule.recurrence = TherapyRecurrence(interval: 2, anchor: date("2026-09-29T08:00:00Z"), additionalWeeklySlots: [TherapyWeeklySlot(weekday: 5, hour: 10)])
        let dates = TherapyDateHelper.occurrences(schedule: data.schedule, after: now, count: 4, calendar: cal)
        try expect(dates == [date("2026-10-13T13:00:00Z"), date("2026-10-15T08:00:00Z"), date("2026-10-27T14:00:00Z"), date("2026-10-29T09:00:00Z")], "Twice per active fortnight, local clocks survive DST")
        data.schedule.extraAppointments = [TherapyExtraAppointment(date: dates[0].addingTimeInterval(7200), title: "Zweites Gespräch")]
        TherapyScheduleActions.cancel(TherapyCancellation(date: dates[0], exactTime: true), schedule: &data.schedule, calendar: cal)
        try expect(TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: now, calendar: cal) == dates[0].addingTimeInterval(7200), "Exact cancellation preserves another same-day appointment")
        data.schedule = TherapySchedule(); data.schedule.recurrence = TherapyRecurrence(unit: .days, interval: 3, anchor: date("2026-10-01T08:00:00Z"))
        try expect(TherapyDateHelper.occurrences(schedule: data.schedule, after: now, count: 2, calendar: cal) == [date("2026-10-01T13:00:00Z"), date("2026-10-04T13:00:00Z")], "Every three days from anchor")
        data.schedule.recurrence = TherapyRecurrence(unit: .months, anchor: date("2027-01-31T09:00:00Z"))
        let monthly = TherapyDateHelper.occurrences(schedule: data.schedule, after: date("2027-01-31T12:00:00Z"), count: 3, calendar: cal)
        try expect(monthly == [date("2027-01-31T14:00:00Z"), date("2027-02-28T14:00:00Z"), date("2027-03-31T13:00:00Z")], "Monthly clamp does not drift permanently and DST is stable")
        data = AppData()
        data.guidedCheckIns = [GuidedCheckIn(date: now, summary: "Ein ruhiger Tag", therapyQuestion: "Wie kann ich Pausen planen?", isDraft: false, moodPercent: 75)]
        data.weekReviews = [WeekReview(weekStart: now.therapyWeekStart, therapyQuestion: "Grenzen üben")]
        let points = TherapyDiscussionPlanner.points(in: data)
        try expect(points.count == 2 && points.last?.date == now, "All sources gathered with original dates")
        data.therapyDiscussionAcknowledgedIDs = [points[0].id]
        try expect(TherapyDiscussionPlanner.points(in: data).count == 1 && TherapyDiscussionPlanner.points(in: data, includeDiscussed: true).count == 2, "Discussed state hides without destroying original")
        let routine = DailyRoutine(title: "Tabletten", times: [RoutineTime(hour: 10)], urgentAlarm: true)
        data.routines = [routine]
        let key = "therapy.routine.\(routine.id).\(routine.times[0].id).\(Int(now.timeIntervalSince1970)).retry.hash"
        try expect(AlarmOwnershipPolicy.keepAlerting(key: key, data: data), "Elapsed active alarm stays ringing on refresh")
        data.routineCompletions = [RoutineCompletion(routineID: routine.id, timeID: routine.times[0].id, scheduledAt: now)]
        try expect(!AlarmOwnershipPolicy.keepAlerting(key: key, data: data), "Actual completion cancels its alerting occurrence")
        data.routineCompletions = []
        let slots = CompanionAlarmPlanner.candidates(data, now: now, calendar: cal)
        try expect(slots.contains { $0.title == "Tabletten" }, "AlarmKit shows actual routine title by default")
        data.companionSettings.alarmShowsActualTitles = false
        try expect(CompanionAlarmPlanner.candidates(data, now: now, calendar: cal).allSatisfy { !$0.title.contains("Tabletten") }, "Neutral AlarmKit titles selectable independently")
        data.aiSettings.enabled = true
        data.notes = [TherapyNote(createdAt: now, title: "Mein Tagebuch", text: "Musik half mir", tags: ["Tagebuch"]), TherapyNote(createdAt: now.addingTimeInterval(86400), title: "FUTURE-SECRET", text: "", tags: [])]
        data.media = [MediaItem(createdAt: now, kind: .photo, title: "PHOTO-SECRET", note: "IMAGE-NOTE-SECRET", tags: [], relativePath: "Media/secret.jpg")]
        var context = AIBuddyContext.make(data: data, days: 7, end: now, calendar: cal)
        try expect(context.days == 7 && context.text.contains("Musik half mir") && !context.text.contains("PHOTO-SECRET") && !context.text.contains("FUTURE-SECRET") && !context.text.contains("secret.jpg"), "Text context excludes media bytes/paths and future records")
        data.aiSettings.includeJournal = false
        try expect(!AIBuddyContext.make(data: data, days: 7, end: now, calendar: cal).text.contains("Musik half mir"), "Journal opt-out respected")
        try expect(AIBuddyContext.resolvedDays(question: "Was war heute?", settings: data.aiSettings) == 1 && AIBuddyContext.resolvedDays(question: "Wochenrückblick", settings: data.aiSettings) == 7 && AIBuddyContext.resolvedDays(question: "letzte 14 Tage", settings: data.aiSettings) == 14, "Visible date inference matches question")
        data.notes = (0..<110).map { TherapyNote(createdAt: now, title: "Text \($0)", text: String(repeating: "a", count: 2000), tags: []) }; data.aiSettings.includeJournal = true
        context = AIBuddyContext.make(data: data, days: 7, end: now)
        try expect(context.recordCount <= 100 && context.omittedCount > 0 && context.text.count < 26000, "Large archives use bounded, disclosed context")
        try expect(AIBuddyText.plain("# Meine Woche\n**Gut** [Link](https://example.com)\n```\nText\n```") == "Meine Woche\nGut Link\nText", "Saved summaries have clean app text")
        let action = AIBuddyAction(kind: .note, title: "Ein guter Moment", text: "Musik half.", weekdays: [])
        let reply = AIBuddyReply(title: "Meine Woche", message: "Ein ruhiger Tag.", sections: [AIBuddySection(heading: "Ein Schritt", text: "Eine Pause planen.")], actions: [action], suggestedDays: nil)
        data.aiMessages = [AIBuddyMessage(role: "assistant", text: reply.journalText, reply: reply)]
        let messageID = data.aiMessages[0].id, oldNotes = data.notes.count
        try AIBuddyMutation.apply(action, originalID: action.id, messageID: messageID, to: &data, now: now)
        try expect(data.notes.count == oldNotes + 1 && data.notes[0].category == "Therapietagebuch", "Native AI action saves normal journal record")
        let after = data
        do { try AIBuddyMutation.apply(action, originalID: action.id, messageID: messageID, to: &data, now: now); throw Failure.assertion("Repeated action allowed") } catch is AIBuddyAPIError { count += 1 }
        try expect(data == after, "Repeated tap cannot create duplicate")
        let invalid = AIBuddyAction(kind: .completeTask, title: "Stale task", text: "", targetID: UUID().uuidString, weekdays: [])
        do { try AIBuddyMutation.apply(invalid, originalID: invalid.id, messageID: messageID, to: &data); throw Failure.assertion("Unknown target mutated") } catch is AIBuddyAPIError { count += 1 }
        try expect(data == after, "Unknown action target leaves full snapshot intact")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        // Codable dates have second precision; normalize for exact comparison.
        let raw = try enc.encode(data), restored = try dec.decode(AppData.self, from: raw)
        try expect(restored.aiSettings == data.aiSettings && restored.aiMessages[0].reply == reply && restored.therapyDiscussionAcknowledgedIDs == data.therapyDiscussionAcknowledgedIDs, "AI settings, actionable replies and discussion state round-trip")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [BuddyMockProtocol.self]
        let api = AIBuddyAPI(session: URLSession(configuration: configuration))
        BuddyMockProtocol.responses = [try response(reply)]; BuddyMockProtocol.requests = []
        let answer = try await api.answer(question: "Meine Woche", context: context, history: [], settings: data.aiSettings, key: "fake-test-key")
        try expect(answer.reply == reply && answer.inputTokens == 500 && answer.outputTokens == 200, "Offline mocked Responses API parses structured native actions and usage")
        try expect(BuddyMockProtocol.requests.count == 1 && BuddyMockProtocol.requests[0]["store"] as? Bool == false, "API request avoids remote conversation storage")
        let format = (BuddyMockProtocol.requests[0]["text"] as! [String: Any])["format"] as! [String: Any]
        try expect(format["strict"] as? Bool == true && format["type"] as? String == "json_schema", "Strict schema contract sent to OpenAI")
        BuddyMockProtocol.responses = [Data("{\"output\":[]}".utf8), try response(reply)]
        let repaired = try await api.answer(question: "Reparieren", context: context, history: [], settings: data.aiSettings, key: "fake-test-key")
        try expect(repaired.repaired, "One bounded structured-output repair succeeds")
        BuddyMockProtocol.responses = [Data("{}".utf8), Data("{}".utf8)]
        let fallback = try await api.answer(question: "Mein Gedanke", context: context, history: [], settings: data.aiSettings, key: "fake-test-key")
        try expect(fallback.reply.actions.count == 3 && fallback.reply.actions.allSatisfy(\.valid), "Malformed replies fall back to safe manual entry buttons")
        BuddyMockProtocol.status = 401; BuddyMockProtocol.responses = [Data("{}".utf8)]
        do { _ = try await api.answer(question: "Fehler", context: context, history: [], settings: data.aiSettings, key: "fake-test-key"); throw Failure.assertion("Authentication failure accepted") } catch is AIBuddyAPIError { count += 1 }
        BuddyMockProtocol.status = 200
        var disabled = data.aiSettings; disabled.enabled = false
        let beforeRequests = BuddyMockProtocol.requests.count
        do { _ = try await api.answer(question: "Aus", context: context, history: [], settings: disabled, key: "fake-test-key"); throw Failure.assertion("Disabled API sent") } catch is AIBuddyAPIError { count += 1 }
        try expect(BuddyMockProtocol.requests.count == beforeRequests, "Disabled AI sends no network request")
        var chats = AppData()
        chats.notes = [TherapyNote(title: "Alt", text: "", tags: ["Familie"])]
        chats.aiMessages = [AIBuddyMessage(role: "user", text: "Bisheriger Gedanke")]
        let oldID = chats.aiMessages[0].id
        AIConversationMutation.migrate(&chats)
        try expect(chats.aiConversations.count == 1 && chats.aiConversations[0].id == oldID && chats.aiMessages[0].conversationID == oldID, "Legacy chat retains every message and deterministic identity")
        AIConversationMutation.migrate(&chats)
        try expect(chats.aiConversations.count == 1, "Chat migration is idempotent")
        let newID = AIConversationMutation.create(in: &chats)
        chats.aiMessages.append(AIBuddyMessage(role: "user", text: "Separates Thema", conversationID: newID))
        try expect(chats.aiMessages.filter { $0.conversationID == oldID }.count == 1, "Conversation history stays isolated")
        AIConversationMutation.save(newID, in: &chats)
        let savedID = chats.aiConversations.first { $0.id == newID }!.savedNoteID!
        AIConversationMutation.save(newID, in: &chats)
        try expect(chats.notes.filter { $0.id == savedID }.count == 1, "Saving conversation twice updates one diary note")
        chats.aiMessages.append(AIBuddyMessage(role: "assistant", text: "Antwort", conversationID: newID))
        AIConversationMutation.save(newID, in: &chats)
        try expect(chats.notes.first { $0.id == savedID }!.text.contains("Antwort") && !chats.notes.first { $0.id == savedID }!.text.contains("Bisheriger Gedanke"), "Conversation export includes full own transcript, no other chat")
        AIConversationMutation.delete(newID, in: &chats)
        try expect(chats.aiMessages.count == 1 && chats.aiMessages[0].id == oldID && chats.notes.contains { $0.id == savedID }, "Deleting a chat preserves other chats and saved diary")
        try expect(AppHashtags.clean(["#familie", "Familie", "  Technik  "], known: ["Familie"]) == ["Familie", "Technik"], "Canonical hashtags reuse existing names")
        var draft = GuidedCheckIn(kind: .morning)
        let conversation = AIConversationMutation.create(in: &chats, checkIn: draft)
        try expect(AIConversationMutation.create(in: &chats, checkIn: draft) == conversation && chats.guidedCheckIns.count == 1, "Guided chat reopens same saved draft")
        let proposal = AIBuddyCheckInProposal(moodPercent: 80, batteryPercent: 0, stress: 2, sensoryLoad: 3, sleepHours: 7.5, summary: "Meine Schwester", givesEnergy: "Musik", takesEnergy: "Lärm", smallWin: "Pause gemacht", nextNeed: "Ruhe", therapyQuestion: "Grenzen", tasks: ["Tee trinken"], tags: ["familie"])
        for step in 0..<7 {
            draft.step = step
            try expect(AICheckInGuide.apply(proposal, to: &draft, known: ["Familie"]) && draft.step == step + 1, "Guide persists standard question step \(step)")
            _ = GuidedCheckInMutation.apply(draft, complete: false, to: &chats)
            try expect(chats.weeklyTasks.isEmpty, "Guided draft never creates tasks before confirmation")
        }
        try expect(draft.moodPercent == 80 && draft.batteryPercent == 0 && draft.sleepHours == 7.5 && draft.therapyQuestion == "Grenzen" && draft.tags == ["Familie"], "Structured guide preserves zero, fields and canonical tags")
        chats.aiMessages.append(AIBuddyMessage(role: "user", text: "Meine Schwester hilft mir", conversationID: conversation))
        try expect(GuidedCheckInMutation.apply(draft, complete: true, to: &chats) && chats.weeklyTasks.count == 1, "Confirmed guided overview creates one normal task")
        let completed = chats.guidedCheckIns[0]
        try expect(completed.conversationTranscript?.contains("Meine Schwester hilft mir") == true, "Completing a guided check-in snapshots its full source conversation")
        var noEdit = completed
        try expect(!AICheckInGuide.apply(proposal, to: &noEdit, known: []) && noEdit == completed, "AI cannot rewrite completed check-ins")
        var invalidDraft = GuidedCheckIn()
        try expect(!AICheckInGuide.apply(AIBuddyCheckInProposal(moodPercent: 101), to: &invalidDraft, known: []) && invalidDraft.step == 0, "Invalid structured values leave draft untouched")
        let restoredChats = try dec.decode(AppData.self, from: enc.encode(chats))
        try expect(restoredChats.aiConversations.map(\.id) == chats.aiConversations.map(\.id) && restoredChats.guidedCheckIns[0].tags == ["Familie"], "Schema 11 chat links and check-in tags round-trip")
        try expect(AIBuddyContext.resolvedDays(question: "Heute vergleiche die letzten 14 Tage", settings: chats.aiSettings) == 14, "Explicit numeric period overrides incidental today")
        try expect(AIBuddyContext.resolvedDays(question: "2 Wochen", settings: chats.aiSettings) == 14 && AIBuddyContext.resolvedDays(question: "2 Monate", settings: chats.aiSettings) == 60, "Numeric week/month scopes resolve to visible bounded days")
        try expect(!AIBuddyAction(kind: .task, title: "Aufgabe", text: "", weekdays: [], tags: ["Familie"]).valid, "Unsupported tag targets are rejected instead of silently losing hashtags")
        try expect(AIBuddyContext.requestDays(question: "Heute", settings: chats.aiSettings, chosenDays: 30) == 1 && AIBuddyContext.requestDays(question: "Wie geht es mir?", settings: chats.aiSettings, chosenDays: 14) == 14, "Context preview and request share the same selection policy")
        var manualScope = chats.aiSettings; manualScope.automaticRange = false
        try expect(AIBuddyContext.requestDays(question: "Heute", settings: manualScope, chosenDays: 30) == 30, "Automatic text inference can be disabled")
        let strict = AIBuddyAPI.schema["properties"] as! [String: Any]
        let guideSchema = strict["checkIn"] as! [String: Any]
        try expect(guideSchema["additionalProperties"] as? Bool == false && (guideSchema["required"] as! [String]).count == 16, "Structured check-in schema requires every nullable field")
        var interactive = AppData()
        let msg = AIBuddyMessage(role: "assistant", text: "Vorschau"); interactive.aiMessages = [msg]
        AIConversationMutation.migrate(&interactive)
        let stamp = ISO8601DateFormatter().string(from: now)
        let repeating = AIBuddyAction(kind: .task, title: "Wöchentlicher Schritt", text: "Kurz beginnen", dateISO: stamp, weekdays: [2], options: AIBuddyActionOptions(remindersEnabled: true, alarmEnabled: false, repeatEveryWeeks: 2, repeatCount: 3))
        try AIBuddyMutation.apply(repeating, originalID: repeating.id, messageID: msg.id, to: &interactive, now: now)
        try expect(interactive.weeklyTasks.count == 3 && Set(interactive.weeklyTasks.map(\.id)).count == 3 && interactive.weeklyTasks.allSatisfy { $0.reminder?.weekdays == [2] }, "Confirmed weekly plan creates exactly three individually editable tasks with reminders")
        let originalCount = interactive.weeklyTasks.count
        do { try AIBuddyMutation.apply(repeating, originalID: repeating.id, messageID: msg.id, to: &interactive, now: now); throw Failure.assertion("Repeated action executed") } catch is AIBuddyAPIError { count += 1 }
        try expect(interactive.weeklyTasks.count == originalCount, "Repeated tap does not duplicate planned tasks")
        let taskID = interactive.weeklyTasks[0].id
        let editTask = AIBuddyAction(kind: .updateTask, title: "Geänderter Schritt", text: "Neue Beschreibung", targetID: taskID.uuidString, weekdays: [])
        let previousReminder = interactive.weeklyTasks[0].reminder
        try AIBuddyMutation.apply(editTask, originalID: editTask.id, messageID: msg.id, to: &interactive)
        try expect(interactive.weeklyTasks[0].id == taskID && interactive.weeklyTasks[0].reminder == previousReminder, "Editing a task preserves ID and unnamed reminder settings")
        let setting = AIBuddyAction(kind: .setting, title: "Kontext", text: "14 Tage", targetID: "ai.contextDays", weekdays: [], options: AIBuddyActionOptions(valueInt: 14))
        try AIBuddyMutation.apply(setting, originalID: setting.id, messageID: msg.id, to: &interactive)
        try expect(interactive.aiSettings.contextDays == 14 && !AIBuddyAction(kind: .setting, title: "Schlüssel", text: "", targetID: "ai.apiKey", weekdays: [], options: AIBuddyActionOptions(valueBool: true)).valid, "Settings changes are bounded and credentials cannot be changed by AI")
        let energy = AIBuddyAction(kind: .energy, title: "Schwester", text: "Gibt mir Ruhe", targetID: "gives", weekdays: [])
        try AIBuddyMutation.apply(energy, originalID: energy.id, messageID: msg.id, to: &interactive)
        try expect(interactive.batteryPoints[0].direction == .gives && interactive.batteryPoints[0].note == "Gibt mir Ruhe", "Confirmed energy suggestion creates a regular editable energy point")
        let emptyChat = AIConversationMutation.create(in: &interactive)
        AIConversationMutation.removeIfEmpty(emptyChat, in: &interactive)
        try expect(!interactive.aiConversations.contains { $0.id == emptyChat }, "Opening an empty chat never leaves a saved draft")
        let draftChat = AIConversationMutation.create(in: &interactive)
        interactive.aiConversations[0].draftText = "Unfertiger Gedanke"
        AIConversationMutation.removeIfEmpty(draftChat, in: &interactive)
        try expect(interactive.aiConversations.contains { $0.id == draftChat }, "Explicitly saved unsent text survives cleanup")
        var noAdvance = GuidedCheckIn(summary: "Gedanke", step: 2)
        _ = AICheckInGuide.apply(AIBuddyCheckInProposal(advance: false), to: &noAdvance, known: [])
        try expect(noAdvance.step == 2, "Clarifying questions never skip the current guided step")
        interactive.editorDrafts = [try AppEditorDraft.make(noAdvance, id: noAdvance.id, kind: "guided", title: "Entwurf")]
        let restoredInteractive = try dec.decode(AppData.self, from: enc.encode(interactive))
        try expect((try JSONSerialization.jsonObject(with: enc.encode(restoredInteractive)) as! NSDictionary) == (try JSONSerialization.jsonObject(with: enc.encode(interactive)) as! NSDictionary) && restoredInteractive.editorDrafts[0].decode(GuidedCheckIn.self) == noAdvance, "All new draft, action and reminder values round-trip through AppData")
        let available = AIBuddyContext.make(data: interactive, days: 7, end: now)
        try expect(available.text.contains("CHECK-IN-FENSTER") && available.text.contains("ai.contextDays"), "AI receives current check-in availability and supported setting values")
        var recurringRoutine = DailyRoutine(title: "Alle zwei Wochen", recurrenceAnchor: now, repeatEveryWeeks: 2)
        let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)!
        let secondWeek = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now)!
        try expect(!RoutineRecurrence.includes(recurringRoutine, date: nextWeek) && RoutineRecurrence.includes(recurringRoutine, date: secondWeek), "Routine interval skips inactive weeks")
        recurringRoutine.endsAt = nextWeek
        try expect(!RoutineRecurrence.includes(recurringRoutine, date: secondWeek), "Finite routine stops after its end date")
        try expect(!BuddyInteraction.withoutPinnedQuestion(AICheckInGuide.questions[1], step: 1).contains(AICheckInGuide.questions[1]), "A repeated model standard question is shown only once in the pinned bar")
        try expect(BuddyInteraction.wantsOverview("Bitte den Check-in speichern") && !BuddyInteraction.wantsOverview("Check-in noch nicht speichern"), "Explicit finish intent and negative intent are distinct")
        var early = GuidedCheckIn()
        try expect(AICheckInGuide.apply(AIBuddyCheckInProposal(advance: false, finish: true, batteryPercent: 0), to: &early, known: []) && early.step == 7 && early.batteryPercent == 0 && early.isDraft, "Early finish preserves values and never bypasses confirmation")
        try expect(AICheckInGuide.apply(AIBuddyCheckInProposal(advance: false, batteryPercent: 68), to: &early, known: []) && early.step == 7 && early.batteryPercent == 68, "Last step remains conversational and editable")
        let longHistory = (0..<80).map { AIBuddyMessage(role: $0 % 2 == 0 ? "user" : "assistant", text: String(repeating: "Langer Gedanke", count: 1000)) }
        let bounded = BuddyInteraction.history(longHistory)
        try expect(bounded.count <= 8 && bounded.reduce(0) { $0 + ($1["content"]?.count ?? 0) } <= 6500, "History has a fixed total budget even in very long chats")
        try expect(BuddyInteraction.boundedTranscript(longHistory).count <= 14000 && BuddyInteraction.transcript(longHistory).count > 14000, "Summary request is bounded, full local details preserved")
        try expect(BuddyInteraction.window(question: "Übersicht über vorgestern", days: 1, now: now, calendar: cal) < cal.startOfDay(for: now).addingTimeInterval(-86400), "Historical day retrieval does not use today")
        var profileData = AppData(); profileData.energyEntries = [EnergyEntry(createdAt: now, level: 3, percent: 62, givesEnergy: "", takesEnergy: "", note: "")]
        let battery = WellbeingProfile.battery(profileData, now: now)!
        let onlyEnergy = WellbeingProfile.snapshot(profileData, range: 0, now: now)
        try expect(onlyEnergy.metrics.map(\.title) == ["Akku"] && onlyEnergy.metrics[0].value == 62, "Live profile never creates mood, stress or satisfaction from an energy-only entry")
        try expect(battery.value == 62 && WellbeingProfile.estimatedBattery(profileData, reading: battery, now: now.addingTimeInterval(3600)) == 62, "Exact battery percentage, no default invented decline")
        profileData.wellbeingPreferences.estimateBattery = true; profileData.wellbeingPreferences.hourlyDecline = 2
        try expect(WellbeingProfile.estimatedBattery(profileData, reading: battery, now: now.addingTimeInterval(3600)) == 60, "Only explicit opt-in enables defined hourly estimate")
        var summaryData = AppData(); let summaryChat = AIConversationMutation.create(in: &summaryData)
        summaryData.aiMessages.append(AIBuddyMessage(role: "user", text: "Meine Schwester hilft mir", conversationID: summaryChat))
        AIConversationMutation.saveSummary(summaryChat, title: "Familie", summary: "Unterstützung hilft.", tags: ["Familie"], in: &summaryData)
        let summaryNote = summaryData.notes[0]
        AIConversationMutation.delete(summaryChat, in: &summaryData)
        try expect(summaryNote.text == "Unterstützung hilft." && summaryData.notes[0].conversationTranscript?.contains("Meine Schwester") == true, "Readable summary and complete details survive chat deletion")
        let restoredNew = try dec.decode(AppData.self, from: enc.encode(summaryData))
        try expect(restoredNew.notes[0].conversationTranscript == summaryNote.conversationTranscript, "Conversation details round-trip through complete snapshot")
        var actionData = AppData(); let instruction = AIBuddyMessage(role: "assistant", text: "Prüfbarer Vorschlag"); actionData.aiMessages = [instruction]
        let batteryAction = AIBuddyAction(kind: .battery, title: "Mein Akku", text: "Pause", moodPercent: 68, weekdays: [])
        try AIBuddyMutation.apply(batteryAction, originalID: batteryAction.id, messageID: instruction.id, to: &actionData, now: now)
        try expect(actionData.energyEntries[0].percent == 68 && actionData.moodCheckIns.isEmpty, "Battery action stores real energy without fabricating mood")
        let palette = AIBuddyAction(kind: .setting, title: "Lila", text: "", targetID: "appearance.accent", weekdays: [], options: AIBuddyActionOptions(valueString: "purple"))
        try AIBuddyMutation.apply(palette, originalID: palette.id, messageID: instruction.id, to: &actionData)
        try expect(actionData.accentTheme == .purple && !AIBuddyAction(kind: .setting, title: "Schwarz", text: "", targetID: "appearance.accent", weekdays: [], options: AIBuddyActionOptions(valueString: "black")).valid, "Only readable curated accent palettes accepted")
        let multiTime = AIBuddyAction(kind: .routine, title: "Meine Erinnerung", text: "", dateISO: ISO8601DateFormatter().string(from: now), weekdays: [], options: AIBuddyActionOptions(times: [480, 1200]))
        try AIBuddyMutation.apply(multiTime, originalID: multiTime.id, messageID: instruction.id, to: &actionData, now: now)
        try expect(actionData.routines[0].times.map(\.hour) == [8, 20] && actionData.routines[0].times.allSatisfy { $0.weekdays.count == 7 }, "Confirmed twice-daily routine keeps both real clocks")
        try expect(AIBuddyActionOptions(remindersEnabled: true).stableIdentity == "AIBuddyActionOptions(remindersEnabled: Optional(true), alarmEnabled: nil, retryMinutes: nil, repeatEveryWeeks: nil, repeatCount: nil, enabled: nil, valueBool: nil, valueInt: nil)", "Pre-3011 confirmed proposal identities stay stable after migration")
        let startRound = AIBuddyAction(kind: .startSession, title: "Runde", text: "", targetID: actionData.sessionTemplates[0].id.uuidString, weekdays: [])
        try AIBuddyMutation.apply(startRound, originalID: startRound.id, messageID: instruction.id, to: &actionData, now: now)
        try expect(actionData.currentSession?.title == actionData.sessionTemplates[0].title, "Only actual reviewed therapy template can start")
        print("Passed \(count) duplicate, flexible recurrence, therapy discussion, alarm lifecycle, AI privacy/action and offline network checks.")
    }
}
