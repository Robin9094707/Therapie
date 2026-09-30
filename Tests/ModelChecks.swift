import Foundation

@main
struct ModelChecks {
    static var checks = 0
    enum Failure: Error { case assertion(String) }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw Failure.assertion(message) }
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        // Stable calendar fixtures, independent of the runner's local timezone.
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-09-30T12:00:00Z")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var old = AppData()
        old.profile = UserProfile(userName: "Robin", therapistName: "Therapeutin", onboardingCompleted: true)
        old.energyEntries = [EnergyEntry(createdAt: now, level: 4, givesEnergy: "Musik", takesEnergy: "Lärm", note: "Alt")]
        old.notes = [TherapyNote(createdAt: now, title: "Erhalten", text: "Meine Notiz", tags: ["wichtig"])]
        old.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: 40, yearForWeekOfYear: 2026, title: "Aufgabe", details: "Erhalten")]
        old.media = [MediaItem(createdAt: now, kind: .audio, title: "Aufnahme", note: "", tags: [], relativePath: "Recordings/example.m4a")]
        old.reflections = [TherapySessionReflection(date: now, summary: "Rückblick", whatHelped: "Ruhe", nextFocus: "Nächster Schritt")]
        var fixture = try JSONSerialization.jsonObject(with: encoder.encode(old)) as! [String: Any]
        fixture["schemaVersion"] = 1
        for key in ["moodCheckIns", "batteryPoints", "weekReviews", "wellnessSettings", "therapyFolders", "therapyTopics", "therapyGoals", "sessionTemplates", "currentSession", "sessionHistory", "sessionPreferences", "weeklyEnergyReviews", "reminderPreferences"] { fixture.removeValue(forKey: key) }
        let migrated = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: fixture))
        try expect(migrated.schemaVersion == 6, "Schema migration")
        try expect(migrated.profile == old.profile && migrated.notes == old.notes, "Names and notes preserved")
        try expect(migrated.weeklyTasks == old.weeklyTasks && migrated.media == old.media, "Tasks and media paths preserved")
        try expect(migrated.energyEntries == old.energyEntries && migrated.reflections == old.reflections, "Legacy energy and reflections preserved")
        try expect(migrated.moodCheckIns.isEmpty && migrated.wellnessSettings.weeklyGoal == 1, "New fields default safely")
        fixture["schemaVersion"] = 999
        do { _ = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: fixture)); throw Failure.assertion("Future schema accepted") }
        catch is DecodingError { checks += 1 }
        do { _ = try decoder.decode(AppData.self, from: Data("{}".utf8)); throw Failure.assertion("Empty corrupt file accepted") }
        catch is DecodingError { checks += 1 }

        let week = now.therapyWeekStart
        try expect(week.therapyWeek.week == 40 && Calendar.therapyCalendar.component(.weekday, from: week) == 2, "ISO Monday week")
        try expect(date("2021-01-01T12:00:00Z").therapyWeek.year == 2020, "ISO year boundary")
        let dates = [week, week.therapyAddingWeeks(-1), week.therapyAddingWeeks(-1), week.therapyAddingWeeks(-2)]
        try expect(WellnessAnalytics.streak(dates, now: now) == WellnessStreak(current: 3, longest: 3, thisWeekRecorded: true), "Deduplicated streak")
        let grace = WellnessAnalytics.streak(Array(dates.dropFirst()), now: now)
        try expect(grace.current == 2 && !grace.thisWeekRecorded, "Current open week keeps previous streak")
        try expect(WellnessAnalytics.streak([week.therapyAddingWeeks(-2)], now: now).current == 0, "Skipped week breaks current streak")
        try expect(WellnessAnalytics.streak([now.addingTimeInterval(3600)], now: now).current == 0, "Future entries excluded")
        let boundary = date("2021-01-04T12:00:00Z")
        try expect(WellnessAnalytics.streak([boundary, boundary.therapyAddingWeeks(-1)], now: boundary).current == 2, "Streak crosses year")
        let dst = date("2026-03-30T12:00:00Z")
        try expect(WellnessAnalytics.streak([dst, dst.therapyAddingWeeks(-1)], now: dst).current == 2, "Streak crosses daylight saving")

        var data = migrated
        data.moodCheckIns = [MoodCheckIn(date: now, mood: 2, battery: 2, stress: 4), MoodCheckIn(date: now.addingTimeInterval(-60), mood: 4, battery: 3)]
        let period = WellnessPeriod.rolling(days: 7, now: now)
        let daily = WellnessAnalytics.daily(data, period: period)
        try expect(daily.count == 1 && daily[0].mood == 3 && daily[0].battery == 3, "Multiple same-day entries average correctly")
        try expect(daily[0].stress == 4 && daily[0].sensory == nil, "Optional values not imputed")
        try expect(WellnessAnalytics.recordedDays(data, period: period) == 1, "Weekly goal counts unique days")
        data.moodCheckIns.append(MoodCheckIn(date: Calendar.therapyCalendar.date(byAdding: .day, value: -3, to: now)!))
        let withGap = WellnessAnalytics.daily(data, period: period)
        try expect(withGap.count == 2 && withGap[0].segment != withGap[1].segment, "Missing calendar days break chart lines")
        var legacyOnly = AppData(); legacyOnly.energyEntries = old.energyEntries
        try expect(WellnessAnalytics.daily(legacyOnly, period: period)[0].mood == nil, "Old battery values never invent mood")
        try expect(!period.contains(now.addingTimeInterval(1)) && period.contains(now), "Period excludes future dates")
        data.batteryPoints = [BatteryPoint(date: now, title: "Wald", direction: .gives, category: .rest, impact: 4),
                              BatteryPoint(date: now, title: "Ruhe", direction: .gives, category: .rest, impact: 2),
                              BatteryPoint(date: now, title: "Lärm", direction: .takes, category: .sensory, impact: 5)]
        let totals = WellnessAnalytics.categoryTotals(data.batteryPoints)
        try expect(totals.first { $0.category == .rest }?.impact == 6, "Battery givers add individually")
        try expect(totals.first { $0.category == .sensory }?.impact == -5, "Battery takers remain negative")
        data.weekReviews = [WeekReview(weekStart: week, summary: "Gut", therapyQuestion: "Besprechen")]
        let encoded = try encoder.encode(data)
        let decoded = try decoder.decode(AppData.self, from: encoded)
        let reencoded = try encoder.encode(decoded)
        let first = try JSONSerialization.jsonObject(with: encoded) as! NSDictionary
        let second = try JSONSerialization.jsonObject(with: reencoded) as! NSDictionary
        try expect(first == second, "New fields round-trip at ISO timestamp precision")
        try expect(WellnessExport.cell("=SUM(A1)").hasPrefix("\"'="), "CSV formula injection protected")
        try expect(WellnessExport.cell("a;\"b").contains("\"\""), "CSV quotes escaped")
        let csv = WellnessExport.csv(data, period: period)
        try expect(csv.hasPrefix("\u{FEFF}") && csv.contains("Wald") && csv.contains("Check-in"), "CSV includes both check-ins and individual points")
        // Version 3000 must retain all check-ins and migrate new therapy fields independently.
        var previous = try JSONSerialization.jsonObject(with: encoder.encode(data)) as! [String: Any]
        previous["schemaVersion"] = 3
        for key in ["therapyFolders", "therapyTopics", "therapyGoals", "sessionTemplates", "currentSession", "sessionHistory", "sessionPreferences"] { previous.removeValue(forKey: key) }
        let upgraded = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: previous))
        try expect(upgraded.moodCheckIns.map(\.id) == data.moodCheckIns.map(\.id), "Version 3000 check-ins preserved")
        try expect(upgraded.batteryPoints == data.batteryPoints, "Version 3000 battery points preserved")
        try expect(upgraded.sessionTemplates.count == 1 && upgraded.sessionTemplates[0].totalMinutes == 60, "Default session template created on migration")
        try expect(upgraded.notes[0].author == nil && upgraded.media[0].folderID == nil, "Legacy optional metadata defaults safely")
        let template = TherapySessionTemplate()
        try expect(template.isValid && template.totalMinutes == 60, "Default example adds up to one hour")
        var invalid = template; invalid.phases[0].minutes = 0
        try expect(!invalid.isValid, "Zero-length phase rejected")
        invalid = template; invalid.phases = []
        try expect(!invalid.isValid, "Empty session rejected")
        invalid = template; invalid.phases = Array(repeating: SessionPhase(title: "Phase", minutes: 180), count: 3)
        try expect(!invalid.isValid, "Sessions above four hours rejected")
        var session = RunningTherapySession.start(template, at: now)
        try expect(session.remaining(at: now) == 3600 && session.phaseIndex(at: now) == 0, "Timer starts at full duration")
        try expect(session.phaseIndex(at: now.addingTimeInterval(299)) == 0 && session.phaseIndex(at: now.addingTimeInterval(300)) == 1, "Exact first phase boundary")
        try expect(session.phaseIndex(at: now.addingTimeInterval(600)) == 2 && session.phaseIndex(at: now.addingTimeInterval(1200)) == 3, "Subsequent phase boundaries")
        try expect(session.remaining(at: now.addingTimeInterval(5000)) == 0 && session.phaseIndex(at: now.addingTimeInterval(3600)) == nil, "Expired session does not run negative")
        session.pause(at: now.addingTimeInterval(120))
        session.pause(at: now.addingTimeInterval(200))
        try expect(session.elapsed(at: now.addingTimeInterval(5000)) == 120, "Pause freezes elapsed time and is idempotent")
        session.resume(at: now.addingTimeInterval(420))
        session.resume(at: now.addingTimeInterval(500))
        try expect(session.accumulatedPause == 300 && session.expectedEnd == now.addingTimeInterval(3900), "Resume extends timeline exactly once")
        try expect(session.phaseIndex(at: now.addingTimeInterval(599)) == 0 && session.phaseIndex(at: now.addingTimeInterval(600)) == 1, "Phase schedule incorporates pause")
        let persistedSession = try decoder.decode(RunningTherapySession.self, from: encoder.encode(session))
        try expect(persistedSession.remaining(at: now.addingTimeInterval(1800)) == 2100, "Timer restored from timestamps after app termination")
        session.endedAt = now.addingTimeInterval(900)
        try expect(session.elapsed(at: now.addingTimeInterval(10000)) == 600, "Finished session freezes its duration")
        var task = old.weeklyTasks[0]
        task.toggleCompletion(at: now)
        try expect(task.completed && task.completedAt == now, "Task completion records date")
        task.toggleCompletion(at: now.addingTimeInterval(1))
        try expect(!task.completed && task.completedAt == nil, "Completed task can be resumed")
        let parent = TherapyFolder(title: "Alltag")
        let child = TherapyFolder(title: "Arbeit", parentID: parent.id)
        let grandchild = TherapyFolder(title: "Kommunikation", parentID: child.id)
        var hierarchy = data
        hierarchy.therapyFolders = [parent, child, grandchild]
        let topic = TherapyTopic(title: "Absprachen", folderID: child.id, status: .active, isCurrent: true)
        hierarchy.therapyTopics = [topic]
        hierarchy.therapyGoals = [TherapyGoal(title: "Eigener Schritt", topicID: topic.id)]
        hierarchy.notes[0].folderID = child.id; hierarchy.notes[0].topicID = topic.id; hierarchy.notes[0].isImportant = true; hierarchy.notes[0].author = NoteAuthor.therapist.rawValue
        hierarchy.media[0].folderID = child.id; hierarchy.media[0].topicID = topic.id
        hierarchy.weeklyTasks[0].topicID = topic.id
        try expect(TherapyHierarchy.descendants(of: parent.id, folders: hierarchy.therapyFolders) == Set([child.id, grandchild.id]), "Nested folder descendants")
        try expect(TherapyHierarchy.path(for: grandchild.id, folders: hierarchy.therapyFolders) == "Alltag / Arbeit / Kommunikation", "Nested folder breadcrumb")
        var cyclic = parent; cyclic.parentID = grandchild.id
        try expect(TherapyHierarchy.path(for: cyclic.id, folders: [cyclic, child, grandchild]).count < 100, "Corrupt cyclic hierarchy cannot loop forever")
        TherapyHierarchy.removeFolder(child.id, data: &hierarchy)
        try expect(hierarchy.therapyFolders.first { $0.id == grandchild.id }?.parentID == parent.id, "Deleting folder reparents children")
        try expect(hierarchy.notes[0].folderID == parent.id && hierarchy.media[0].folderID == parent.id && hierarchy.therapyTopics[0].folderID == parent.id, "Deleting folder preserves and moves contents")
        TherapyHierarchy.removeTopic(topic.id, data: &hierarchy)
        try expect(hierarchy.therapyGoals[0].topicID == nil && hierarchy.notes[0].topicID == nil && hierarchy.weeklyTasks[0].topicID == nil, "Deleting topic detaches preserved linked records")
        let finalData = try decoder.decode(AppData.self, from: encoder.encode(hierarchy))
        try expect(finalData.notes[0].author == NoteAuthor.therapist.rawValue && finalData.notes[0].isImportant == true, "Important clinician contributions persist")
        print("Passed \(checks) migration, streak, chart aggregation and export checks.")
    }
}
