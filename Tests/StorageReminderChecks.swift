import Foundation

@main
struct StorageReminderChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ test: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !test() { throw Failure.assertion(message) } }
    static func rejects(_ message: String, _ work: () throws -> Void) throws { do { try work() } catch { count += 1; return }; throw Failure.assertion(message) }
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        let fm = FileManager.default, base = try BackupArchive.privateDirectory()
        defer { try? fm.removeItem(at: base) }
        let support = base.appendingPathComponent("Support"), documents = base.appendingPathComponent("Documents")
        let legacy = support.appendingPathComponent("Therapie")
        for folder in ["Media", "Recordings"] { try fm.createDirectory(at: legacy.appendingPathComponent(folder), withIntermediateDirectories: true) }
        var data = AppData()
        data.profile = UserProfile(userName: "Robin", therapistName: "Therapeutin", onboardingCompleted: true)
        data.reminderPreferences.energyReviewEnabled = true
        data.notes = [TherapyNote(title: "Lesbare Notiz", text: "Meine wichtige Zeile\nzweite Zeile", tags: ["wichtig"], isImportant: true)]
        data.therapyFolders = [TherapyFolder(title: "Meine Themen")]
        data.weeklyEnergyReviews = [WeeklyEnergyReview(periodEnd: now, energy: 4, gives: [WeeklyEnergyFactor(title: "Freunde", impact: 4)], takes: [WeeklyEnergyFactor(title: "Viele Reize", impact: 2)], therapyQuestion: "Wie kann ich Pausen planen?")]
        let week = now.therapyWeek
        data.weeklyTasks = [WeeklyTask(createdAt: now, weekOfYear: week.week, yearForWeekOfYear: week.year, title: "Meine Aufgabe", details: "Kleiner Schritt", reminder: TaskReminder(), smallStep: "Erst anfangen", support: "Therapie", progress: 20)]
        let photo = Data((0..<(BackupArchive.chunkSize * 2 + 5)).map { UInt8($0 % 251) })
        try photo.write(to: legacy.appendingPathComponent("Media/p.jpg"))
        try Data().write(to: legacy.appendingPathComponent("Recordings/empty.m4a"))
        data.media = [MediaItem(kind: .photo, title: "Bild", note: "Wichtige Beschreibung", tags: ["Privat"], relativePath: "Media/p.jpg"), MediaItem(kind: .audio, title: "Leer", note: "", tags: [], relativePath: "Recordings/empty.m4a")]
        try BackupArchive.encoder().encode(data).write(to: legacy.appendingPathComponent("therapy-data.json"))
        let root = try AppFileStorage.root(applicationSupport: support, documents: documents, folder: "Therapie")
        try expect(root == documents.appendingPathComponent("Therapiedaten"), "Documents location is stable")
        try expect(!fm.fileExists(atPath: legacy.path), "Legacy storage migrated")
        try expect(try Data(contentsOf: root.appendingPathComponent("Media/p.jpg")) == photo, "Migration preserves exact photo bytes")
        try expect(try BackupArchive.decoder().decode(AppData.self, from: Data(contentsOf: root.appendingPathComponent("therapy-data.json"))).notes.count == 1, "Migration retains original data")
        try expect(try AppFileStorage.root(applicationSupport: support, documents: documents, folder: "Therapie") == root, "Migration is idempotent")
        try ReadableBackup.writeEntries(data: data, root: root)
        let noteFile = root.appendingPathComponent("Eintraege/notes/" + data.notes[0].id.uuidString + ".txt")
        try expect(try String(contentsOf: noteFile, encoding: .utf8).contains("zweite Zeile"), "Human-readable multiline note retained")
        try expect(try String(contentsOf: root.appendingPathComponent("UEBERSICHT.md"), encoding: .utf8).contains("Lesbare Notiz"), "Human-readable index contains titles")
        let energyFile = root.appendingPathComponent("Eintraege/weeklyEnergyReviews/" + data.weeklyEnergyReviews[0].id.uuidString + ".txt")
        try expect(try String(contentsOf: energyFile, encoding: .utf8).contains("Freunde"), "Weekly energy factors human-readable")
        var removed = data; removed.notes = []
        try ReadableBackup.writeEntries(data: removed, root: root)
        try expect(!fm.fileExists(atPath: noteFile.path), "Deleted records removed from readable mirror")
        try ReadableBackup.writeEntries(data: data, root: root)
        let preferences = PortablePreferences(appearance: "dark", calmInterface: true, haptics: false, confetti: true)
        let zip = try ReadableBackup.export(data: data, root: root, preferences: preferences, options: BackupOptions(), version: "3003.0.0")
        defer { try? fm.removeItem(at: zip.deletingLastPathComponent()) }
        let prepared = try ReadableBackup.prepareImport(url: zip); defer { prepared.discard() }
        try expect(try BackupArchive.encoder().encode(prepared.manifest.data) == BackupArchive.encoder().encode(data), "Plain ZIP preserves all AppData fields")
        try expect(prepared.manifest.preferences == preferences, "Plain ZIP preserves portable settings")
        try expect(try Data(contentsOf: prepared.directory.appendingPathComponent("Media/p.jpg")) == photo, "ZIP streams multiple attachment blocks")
        try expect(try Data(contentsOf: prepared.directory.appendingPathComponent("Recordings/empty.m4a")).isEmpty, "ZIP supports empty attachments")
        try expect(fm.fileExists(atPath: prepared.directory.appendingPathComponent("UEBERSICHT.md").path), "ZIP contains readable overview")
        let checkURL = URL(fileURLWithPath: "/tmp/therapie-portable-check.zip")
        try? fm.removeItem(at: checkURL); try fm.copyItem(at: zip, to: checkURL)
        var noPhotos = BackupOptions(); noPhotos.includePhotos = false
        let slim = try ReadableBackup.export(data: data, root: root, preferences: preferences, options: noPhotos, version: "3003.0.0")
        defer { try? fm.removeItem(at: slim.deletingLastPathComponent()) }
        let small = try ReadableBackup.prepareImport(url: slim); defer { small.discard() }
        try expect(small.manifest.omittedAttachments == 1 && small.manifest.data.media[0].attachmentOmitted == true, "ZIP image exclusion explicit")
        try expect(small.manifest.data.media[0].note == data.media[0].note, "Excluded attachment metadata retained")
        try expect(!fm.fileExists(atPath: small.directory.appendingPathComponent("Media/p.jpg").path), "Excluded photo absent from ZIP")
        for path in ["../x", "/x", "a//b", "a/../b", "a\\b", "a/./b", "a/", "a\0b"] { try rejects("Unsafe ZIP path accepted") { try StoredZIP.path(path) } }
        let raw = try Data(contentsOf: zip), corrupt = base.appendingPathComponent("bad.zip")
        try raw.prefix(raw.count - 1).write(to: corrupt)
        try rejects("Truncated ZIP accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        var changed = raw; changed[100] ^= 1; try changed.write(to: corrupt)
        try rejects("Modified ZIP accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        try (raw + Data([0])).write(to: corrupt)
        try rejects("Appended bytes accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        var attacked = raw
        let originalName = Data("Media/p.jpg".utf8), unsafeName = Data("../xx/p.jpg".utf8)
        while let range = attacked.range(of: originalName) { attacked.replaceSubrange(range, with: unsafeName) }
        try attacked.write(to: corrupt)
        try rejects("ZIP traversal accepted") { let value = try ReadableBackup.prepareImport(url: corrupt); value.discard() }
        let legacy2 = base.appendingPathComponent("Support2/Therapie"), docs2 = base.appendingPathComponent("Documents2")
        try fm.createDirectory(at: legacy2, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: legacy2.appendingPathComponent("therapy-data.json"))
        try fm.createDirectory(at: docs2.appendingPathComponent("Therapiedaten"), withIntermediateDirectories: true)
        try rejects("Occupied target silently replaced") { _ = try AppFileStorage.root(applicationSupport: legacy2.deletingLastPathComponent(), documents: docs2, folder: "Therapie") }
        try expect(try String(contentsOf: legacy2.appendingPathComponent("therapy-data.json"), encoding: .utf8) == "original", "Failed migration keeps original")
        let task = data.weeklyTasks[0]
        let daily = TaskReminderPlanner.slots(tasks: [task], schedule: data.schedule, now: now)
        try expect(daily.count == 1 && daily[0].weekday == nil, "Seven weekdays use one repeating daily notification")
        var done = task; done.completed = true
        try expect(TaskReminderPlanner.slots(tasks: [done], schedule: data.schedule, now: now).isEmpty, "Completed task has no reminder")
        var off = task; off.reminder?.enabled = false
        try expect(TaskReminderPlanner.slots(tasks: [off], schedule: data.schedule, now: now).isEmpty, "Disabled task has no reminder")
        var chosen = task; chosen.reminder = TaskReminder(weekdays: [2, 2, 6, 99], hour: 30, minute: -1)
        let selected = TaskReminderPlanner.slots(tasks: [chosen], schedule: data.schedule, now: now)
        try expect(selected.count == 2 && Set(selected.compactMap(\.weekday)) == Set([2, 6]), "Weekdays deduplicate and validate")
        try expect(selected.allSatisfy { $0.hour == 23 && $0.minute == 0 }, "Reminder clock clamped")
        var older = task; older.reminder = nil
        try expect(TaskReminderPlanner.slots(tasks: [older], schedule: data.schedule, now: now).count == 2, "Legacy task inherits global weekdays")
        var future = task; let futureWeek = now.therapyAddingWeeks(1).therapyWeek; future.weekOfYear = futureWeek.week; future.yearForWeekOfYear = futureWeek.year
        try expect(TaskReminderPlanner.slots(tasks: [future], schedule: data.schedule, now: now).isEmpty, "Future task not prematurely reminded")
        try expect(TaskReminderPlanner.slots(tasks: [future], schedule: data.schedule, now: now.therapyAddingWeeks(1)).count == 1, "Future week task becomes active")
        var shifted = task; TaskReminderPlanner.postpone(&shifted, schedule: data.schedule, minutes: 60, now: now)
        try expect(shifted.reminder?.hour == 15 && shifted.reminderShiftedAt == now.addingTimeInterval(3600), "Postpone updates repeating clock and history")
        var tomorrow = task; TaskReminderPlanner.postpone(&tomorrow, schedule: data.schedule, minutes: 1440, now: now)
        try expect(tomorrow.reminderShiftedAt == now.addingTimeInterval(86400) && tomorrow.reminder?.hour == 14, "Tomorrow updates schedule")
        let unchanged = done; TaskReminderPlanner.postpone(&done, schedule: data.schedule, minutes: 60, now: now)
        try expect(done == unchanged, "Done tasks cannot be postponed")
        let periodEnd = TherapyReviewPeriod.latestTherapyDay(schedule: data.schedule, now: now)
        try expect(Calendar.therapyCalendar.component(.weekday, from: periodEnd) == data.schedule.weekday && periodEnd <= now, "Most recent therapy day selected")
        let review = WeeklyEnergyReview(periodEnd: now)
        try expect(Calendar.therapyCalendar.dateComponents([.day], from: review.periodStart, to: Calendar.therapyCalendar.startOfDay(for: now)).day == 7, "Review has exactly seven completed calendar days")
        let dst = ISO8601DateFormatter().date(from: "2026-03-31T12:00:00Z")!
        let dstReview = WeeklyEnergyReview(periodEnd: dst)
        try expect(Calendar.therapyCalendar.dateComponents([.day], from: dstReview.periodStart, to: Calendar.therapyCalendar.startOfDay(for: dst)).day == 7, "Review crosses daylight-saving using calendar days")
        var justEnergy = AppData(); justEnergy.weeklyEnergyReviews = [WeeklyEnergyReview(periodEnd: now)]
        try expect(WellnessAnalytics.streak(WellnessAnalytics.activityDates(justEnergy), now: now).thisWeekRecorded, "Weekly energy contributes to weekly streak")
        print("Passed \(count) readable ZIP, Documents migration, reminder schedule and weekly energy checks.")
    }
}
