import Foundation

@main
struct PersonalizationChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !condition() { throw Failure.assertion(message) }
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        var calendar = Calendar.therapyCalendar; calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-10-01T12:00:00Z")
        var data = AppData(); data.profile.onboardingCompleted = true
        data.dashboard.cardOrder = ["routines", "routines", "not-a-card", "appointment"]
        data.dashboard.hiddenCards = ["welcome", "latest"]
        data.dashboard.pinnedCards = ["appointment"]
        data.dashboard.pinnedRecordIDs = ["note-abc"]
        data.archivePreferences = ArchivePreferences(grouping: .month, oldestFirst: true)
        try expect(data.dashboard.visibleCards.first == .appointment, "Pinned card goes first")
        try expect(Set(data.dashboard.orderedCards).count == HomeCard.allCases.count, "Duplicate/unknown cards ignored and new cards included")
        try expect(!data.dashboard.visibleCards.contains(.welcome), "Hidden card is excluded")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoded = try encoder.encode(data)
        try expect(try decoder.decode(AppData.self, from: encoded) == data, "Settings persist exactly")
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["schemaVersion"] = 8; legacy.removeValue(forKey: "dashboard"); legacy.removeValue(forKey: "archivePreferences")
        let migrated = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(migrated.schemaVersion == 15 && migrated.dashboard == DashboardPreferences(), "Schema 8 receives safe defaults")
        try expect(migrated.archivePreferences == ArchivePreferences(), "Legacy archive defaults")
        try expect(try decoder.decode(DashboardPreferences.self, from: Data("{}".utf8)) == DashboardPreferences(), "Partial settings migrate")
        legacy["schemaVersion"] = 999
        do { _ = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacy)); throw Failure.assertion("Future data accepted") } catch is DecodingError { count += 1 }
        let spring = date("2026-03-29T12:00:00Z"), autumn = date("2026-10-25T12:00:00Z")
        for day in [spring, autumn] {
            let start = calendar.startOfDay(for: day), end = calendar.date(byAdding: .day, value: 1, to: start)!
            try expect(ArchiveDateFilter.includes(end.addingTimeInterval(-1), day: nil, from: day, through: day, calendar: calendar), "Full DST day included")
            try expect(!ArchiveDateFilter.includes(end, day: nil, from: day, through: day, calendar: calendar), "Next day excluded across DST")
        }
        try expect(ArchiveGrouping.week.start(of: date("2026-01-01T12:00:00Z"), calendar: calendar) == calendar.date(from: DateComponents(year: 2025, month: 12, day: 29)), "ISO week starts in previous year")
        let routine = DailyRoutine(title: "PRIVATE ROUTINE", times: [RoutineTime(hour: 6, minute: 30)])
        data.routines = [routine]
        data.notes = [TherapyNote(createdAt: now, title: "PRIVATE NOTE", text: "SECRET ANSWER", tags: ["findme"])]
        data.media = [MediaItem(createdAt: now, kind: .audio, title: "Audio", note: "", tags: ["audio-tag"], relativePath: "Recordings/private.m4a")]
        let all = ArchiveRecord.all(in: data)
        try expect(all.contains { $0.kind == .notes } && all.contains { $0.kind == .audio }, "Archive includes notes and audio")
        try expect(all.contains { $0.subtitle.contains("audio-tag") }, "Media tags searchable")
        let cache = TherapyWidgetSnapshotBuilder.make(data: data, now: now, calendar: calendar)
        let cacheText = String(decoding: try encoder.encode(cache), as: UTF8.self)
        try expect(!cacheText.contains("PRIVATE") && !cacheText.contains("SECRET") && !cacheText.contains("private.m4a"), "Widget cache excludes private titles, journal text and paths by default")
        try expect(cache.nextAppointments.count == 8 && cache.nextAppointments.allSatisfy { $0 >= now }, "Eight actual future therapy dates")
        let due = cache.dueRoutines(at: now)
        try expect(due.count == 1, "Routine due now")
        let occurrence = RoutinePlanner.occurrences([routine], settings: data.companionSettings, now: now, days: 1, calendar: calendar).first { $0.due <= now }!
        data.routineCompletions = [RoutineCompletion(routineID: routine.id, timeID: occurrence.timeID, scheduledAt: occurrence.due)]
        try expect(TherapyWidgetSnapshotBuilder.make(data: data, now: now, calendar: calendar).dueRoutines(at: now).isEmpty, "Completed routine removed from widget")
        data.dashboard.showWidgetTitles = true
        try expect(TherapyWidgetSnapshotBuilder.make(data: data, now: now, calendar: calendar).reminders.contains { $0.title == routine.title }, "Explicit title opt-in applies")
        data.routines[0].pausedUntil = now.addingTimeInterval(86400)
        try expect(TherapyWidgetSnapshotBuilder.make(data: data, now: now, calendar: calendar).reminders.isEmpty, "Paused routine is absent")
        try expect(cache.dueRoutines(at: now.addingTimeInterval(9 * 86400)).isEmpty, "Expired cached routine never remains overdue")
        print("Passed \(count) personalization, schema, archive/DST, widget privacy and routine checks.")
    }
}
