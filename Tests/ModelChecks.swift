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
        try expect(migrated.schemaVersion == 17, "Schema migration")
        try expect(migrated.entryLocations.isEmpty && migrated.buddySuggestions.isEmpty && migrated.captureEntryLocation == nil && migrated.suggestionsEnabled == nil, "Legacy defaults never invent locations or suggestions")
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
        var supportData = old
        supportData.copingMethods = [.asmrExample, .thoughtStopExample]
        try expect(supportData.copingMethods[0].matches(category: .sensory, stage: .calm, query: "laut", data: supportData), "Personal method mapping matches situation, category and stage")
        try expect(!supportData.copingMethods[0].matches(category: .work, stage: .prevent, query: "", data: supportData), "Methods do not invent unrelated assignments")
        var supportPrevious = try JSONSerialization.jsonObject(with: encoder.encode(supportData)) as! [String: Any]
        supportPrevious["schemaVersion"] = 14
        for key in ["copingMethods", "emergencyPlan", "groundingPractices", "showerEntries"] { supportPrevious.removeValue(forKey: key) }
        let migratedSupport = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: supportPrevious))
        try expect(migratedSupport.notes == old.notes && migratedSupport.copingMethods.isEmpty && !migratedSupport.emergencyPlan.hasContent, "Previous release preserves records and starts with empty support areas")
        var dashboard = DashboardPreferences(); dashboard.pinnedCards = ["appointment"]
        try expect(dashboard.visibleCards.first == .welcome, "Greeting is above all other cards by default")
        dashboard.welcomeFirst = false
        try expect(dashboard.visibleCards.first == .appointment, "User can move the greeting behind pinned cards")
        let weekNow = now.therapyWeek
        supportData.weeklyTasks = [WeeklyTask(weekOfYear: weekNow.week, yearForWeekOfYear: weekNow.year, title: "Visible without notifications", details: "", reminder: TaskReminder(enabled: false))]
        supportData.profile.onboardingCompleted = true
        let widget = TherapyWidgetSnapshotBuilder.make(data: supportData, now: now)
        try expect(widget.reminders.contains { $0.kind == "task" }, "Widget shows open tasks even when notifications are disabled")
        try expect(widget.accentName == supportData.accentTheme.rawValue, "Widget receives the selected app accent")
        let widgetText = String(decoding: try encoder.encode(widget), as: UTF8.self)
        try expect(!widgetText.contains("Meine Notiz"), "Widget snapshot never exports diary content")

        var oldShower = try JSONSerialization.jsonObject(with: encoder.encode(supportData)) as! [String: Any]
        oldShower["schemaVersion"] = 15
        oldShower.removeValue(forKey: "showerPreferences"); oldShower.removeValue(forKey: "routineDeferrals")
        let showerMigrated = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: oldShower))
        try expect(showerMigrated.showerPreferences.weeklyGoal == 3 && showerMigrated.routineDeferrals.isEmpty && showerMigrated.showerEntries == supportData.showerEntries, "Schema15 shower history survives new scheduling defaults")
        let monday = date("2026-10-05T10:00:00Z"), tuesday = date("2026-10-06T17:00:00Z")
        var showerData = AppData(); showerData.profile.onboardingCompleted = true
        let showerRoutine = ShowerPlanner.defaultRoutine(at: monday)
        showerData.routines = [showerRoutine]
        let showerOccurrence = ShowerPlanner.today(showerData, at: monday).first!
        try expect(showerOccurrence.due > monday, "Shower day visible before scheduled clock")
        try expect(RoutineDayMutation.postpone(showerOccurrence, until: tuesday, in: &showerData, at: monday), "Single shower occurrence can move to tomorrow")
        try expect(ShowerPlanner.today(showerData, at: monday).isEmpty && ShowerPlanner.today(showerData, at: tuesday).first?.id == showerOccurrence.id, "Deferral hides original day and preserves occurrence identity tomorrow")
        try expect(showerData.routines[0].times[0].weekdays == [2,4,6] && ShowerPlanner.today(showerData, at: date("2026-10-07T10:00:00Z")).count == 1, "One-day deferral preserves regular weekdays")
        let deferred = ShowerPlanner.today(showerData, at: tuesday).first!
        showerData.routines[0].urgentAlarm = true
        let deferredAlarmKey = "therapy.routine." + showerOccurrence.id + "." + String(Int(tuesday.timeIntervalSince1970))
        try expect(AlarmOwnershipPolicy.keepAlerting(key: deferredAlarmKey, data: showerData, now: tuesday.addingTimeInterval(60)), "Deferred alarm survives refresh on a non-regular weekday")
        let deferredWidget = TherapyWidgetSnapshotBuilder.make(data: showerData, now: tuesday.addingTimeInterval(60))
        try expect(deferredWidget.reminders.contains { $0.id == showerOccurrence.id }, "Deferred off-weekday reaches widget and reminder inventory")
        try expect(RoutineDayMutation.resolve(deferred, outcome: .done, note: "", in: &showerData, at: tuesday), "Deferred occurrence resolves using original scheduled identity")
        try expect(!AlarmOwnershipPolicy.keepAlerting(key: deferredAlarmKey, data: showerData, now: tuesday.addingTimeInterval(60)), "Resolved deferred alarm no longer owns an alert")
        let afterShower = showerData
        try expect(!RoutineDayMutation.resolve(deferred, outcome: .done, note: "", in: &showerData, at: tuesday) && showerData == afterShower, "Repeated shower tap is idempotent")
        showerData.showerEntries = [ShowerEntry(date: tuesday, note: "Extra")]
        try expect(ShowerPlanner.weekCount(showerData, at: tuesday) == 1, "Week target counts unique completed days, not duplicate logs")
        try expect(RoutinePlanner.slots(data: showerData, now: tuesday).allSatisfy { $0.occurrence.id != showerOccurrence.id }, "Resolved deferral cancels all remaining reminders")
        var merged = AppData(); merged.routines = [showerRoutine]
        try expect(RoutineDayMutation.postpone(showerOccurrence, until: date("2026-10-07T17:00:00Z"), in: &merged, at: monday), "Move to official shower day accepted")
        try expect(merged.routineDeferrals.isEmpty && merged.routineCompletions.first?.outcome == .skipped && ShowerPlanner.today(merged, at: date("2026-10-07T10:00:00Z")).count == 1, "Moving to next official day creates no duplicate obligation")
        try expect(ShowerPlanner.weekCount(merged, at: monday) == 0, "Skipping never counts as showering")
        var interval = AppData(); interval.routines = [ShowerPlanner.defaultRoutine(at: date("2026-10-24T10:00:00Z"), everyTwoDays: true)]
        let intervalDates = RoutinePlanner.occurrences(data: interval, now: date("2026-10-24T00:00:00Z"), days: 5).map(\.due)
        try expect(intervalDates == [date("2026-10-24T17:00:00Z"), date("2026-10-26T18:00:00Z"), date("2026-10-28T18:00:00Z")], "Every-two-days rhythm retains local clock across autumn DST")
        let snapshotWithShower = TherapyWidgetSnapshotBuilder.make(data: showerData, now: tuesday)
        try expect(snapshotWithShower.showerWeekCount == 1 && snapshotWithShower.showerWeekGoal == 3 && snapshotWithShower.showerDays?.first?.status == "done", "Minimal widget cache receives real shower state and goal")
        let profileXML = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Entitlements</key><dict><key>com.apple.security.application-groups</key><array><string>group.signer.therapie</string><string>group.unrelated</string></array></dict></dict></plist>"
        try expect(TherapyWidgetStorage.candidates(profile: Data(profileXML.utf8)) == [TherapyWidgetSnapshot.appGroup, "group.signer.therapie"], "Signed group discovery uses only related declared groups")
        var appleData = AppData()
        let wakeClock = date("2026-10-05T04:00:00Z")
        let wakeAlarm = WakeAlarm(title: "Aufstehen", hour: 6, minute: 30, weekdays: [2,3,4,5,6], followUpCount: 3, followUpMinutes: 2)
        appleData.wakeAlarms = [wakeAlarm]
        let firstWake = WakePlanner.occurrences(data: appleData, now: wakeClock).first { $0.date > wakeClock }!
        try expect(Calendar.current.component(.weekday, from: firstWake.date) == 2, "Wake alarm respects selected weekdays")
        let firstSlots = WakePlanner.slots(data: appleData, now: wakeClock)
        try expect(firstSlots.filter { $0.id.hasPrefix(firstWake.id + ".") }.count == 4, "Wake follow-ups are bounded and scheduled in advance")
        appleData.wakeRuns = [WakeRun(id:firstWake.id, alarmID:wakeAlarm.id, scheduledAt:firstWake.date, outcome:.completed)]
        try expect(!WakePlanner.slots(data:appleData,now:wakeClock).contains { $0.id.hasPrefix(firstWake.id + ".") }, "Completion removes every follow-up for this occurrence")
        appleData.wakeRuns = []; appleData.wakeAlarms[0].excludedDays = [firstWake.date]
        try expect(!WakePlanner.occurrences(data:appleData,now:wakeClock).contains { $0.id == firstWake.id }, "Excluded local calendar day never schedules")
        appleData.wakeAlarms[0].excludedDays = []
        appleData.wakeRuns = [WakeRun(id:firstWake.id,alarmID:wakeAlarm.id,scheduledAt:firstWake.date,snoozes:1,snoozedUntil:firstWake.date.addingTimeInterval(300),revision:1)]
        try expect(!AlarmOwnershipPolicy.keepAlerting(key:firstWake.id + ".r0.0",data:appleData,now:firstWake.date.addingTimeInterval(60)), "Snoozing permits cancellation of the old ringing alarm")
        try expect(WakePlanner.slots(data:appleData,now:firstWake.date).contains { $0.id.hasPrefix(firstWake.id + ".r1.") && $0.fireAt == firstWake.date.addingTimeInterval(300) }, "Snooze replaces the alarm generation and fire time")
        try expect(MedicalPass(birthDate:date("2000-10-08T00:00:00Z")).age(at:date("2026-10-07T12:00:00Z")) == 25, "Pass age changes on the birthday rather than storing stale age")
        var appleRoutine = DailyRoutine(title:"Frühstück",times:[RoutineTime(weekdays:[2],hour:6,minute:30)],urgentAlarm:true,repeatUntilDone:false,escalationHour:nil,appleReminders:true,alarmDelayMinutes:10)
        appleData = AppData(); appleData.appleIntegration.remindersEnabled = true; appleData.routines = [appleRoutine]
        let drafts = AppleReminderPlanner.drafts(data:appleData,now:wakeClock)
        try expect(drafts.first?.title == "Deine Routine", "System reminders are private by default")
        let breakfast = drafts.first!.routineOccurrence!
        let delayed = CompanionAlarmPlanner.candidates(appleData,now:breakfast.due.addingTimeInterval(60))
        try expect(delayed.contains { $0.route == "routine|\(appleRoutine.id)" && $0.fireAt == breakfast.due.addingTimeInterval(600) }, "Grace-period alarm is still planned after initial due time")
        appleData.routineCompletions = [.init(routineID:appleRoutine.id,timeID:breakfast.timeID,scheduledAt:breakfast.scheduledAt)]
        try expect(!AppleReminderPlanner.drafts(data:appleData,now:wakeClock).contains { $0.id == drafts.first!.id }, "Confirmed reminder is removed from managed desired inventory")
        try expect(!CompanionAlarmPlanner.candidates(appleData,now:breakfast.due.addingTimeInterval(60)).contains { $0.fireAt == breakfast.due.addingTimeInterval(600) }, "Confirmed routine cancels grace alarm")
        appleRoutine.enabled = false; appleData.routines = [appleRoutine]
        try expect(AppleReminderPlanner.drafts(data:appleData,now:wakeClock).isEmpty, "Paused routine does not publish reminders")
        var previousApple = try JSONSerialization.jsonObject(with:encoder.encode(AppData())) as! [String:Any]
        previousApple["schemaVersion"] = 16
        for key in ["medicalPass","appleIntegration","wakeAlarms","wakeRuns"] { previousApple.removeValue(forKey:key) }
        let migratedApple = try decoder.decode(AppData.self,from:JSONSerialization.data(withJSONObject:previousApple))
        try expect(migratedApple.medicalPass == MedicalPass() && !migratedApple.appleIntegration.remindersEnabled && migratedApple.wakeAlarms.isEmpty, "Existing data gains empty pass and opt-in integrations without requesting permission")
        let copySource = TherapyWidgetSnapshot(generatedAt:wakeClock, reminders:[TherapyWidgetReminder(id:"copy",kind:"routine",title:"Hinweis",due:wakeClock,expiresAt:wakeClock.addingTimeInterval(86400),route:"therapie://routines")],configured:true)
        let copyCode = try encoder.encode(copySource).base64EncodedString()
        try expect(TherapyWidgetStorage.copiedSnapshot(copyCode)?.reminders.first?.title == "Hinweis", "Copied widget data works independently of App Group storage")
        var invalidCopy = copySource; invalidCopy.reminders[0].route = "https://example.com"
        try expect(TherapyWidgetStorage.copiedSnapshot(try encoder.encode(invalidCopy).base64EncodedString()) == nil, "Widget copy cannot supply external deep links")
        print("Passed \(checks) migration, streak, chart aggregation and export checks.")
    }
}
