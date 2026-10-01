import Foundation

final class BuddyMockProtocol: URLProtocol {
    static var responses: [Data] = []
    static var requests: [[String: Any]] = []
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let body = request.httpBody, let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { Self.requests.append(value) }
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
        print("Passed \(count) duplicate, flexible recurrence, therapy discussion, alarm lifecycle, AI privacy/action and offline network checks.")
    }
}
