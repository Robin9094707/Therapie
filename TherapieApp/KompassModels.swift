import Foundation

// MARK: - Kompass 6 shared models
//
// Pure Foundation code: quiet mode, the unified reminder inventory and the surface (glass) preferences.
// Everything here is part of `AppData`, so it is encoded by the encrypted backup, the readable ZIP and the
// human-readable mirror without a second hand-maintained list.

extension KeyedDecodingContainer {
    /// Decodes an optional key and falls back to the given default, so new fields never break older files.
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

// MARK: - Surface (Liquid Glass) preferences

enum SurfaceStyle: String, Codable, CaseIterable, Identifiable {
    /// Liquid Glass with a calm, mostly opaque body: the default since Kompass 6.
    case soft
    /// The clear Liquid Glass of Therapie 5.
    case glass
    /// Opaque cards without glass refraction.
    case solid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .soft: "Sanftes Glas"
        case .glass: "Klares Glas"
        case .solid: "Matt"
        }
    }
    var subtitle: String {
        switch self {
        case .soft: "Glas-Kanten, ruhige Flächen"
        case .glass: "Durchsichtig wie Therapie 5"
        case .solid: "Deckend, ohne Spiegelung"
        }
    }
    var symbol: String {
        switch self {
        case .soft: "circle.lefthalf.filled"
        case .glass: "drop.fill"
        case .solid: "square.fill"
        }
    }
}

struct SurfacePreferences: Codable, Equatable {
    var style: SurfaceStyle = .soft
    /// How much of the card body covers the background (0 = clear glass, 1 = fully covered).
    var coverage = 0.72
    /// Strength of the accent tint on emphasized cards and chips.
    var tintStrength = 0.5
    /// Strength of the ambient colour field behind all screens.
    var backgroundIntensity = 0.55
    /// Interactive glass (touch highlight) on tiles and buttons.
    var interactiveGlass = true
    /// Softer, rounder cards.
    var roundedCards = true

    init() {}
    enum CodingKeys: String, CodingKey { case style, coverage, tintStrength, backgroundIntensity, interactiveGlass, roundedCards }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = try c.value(.style, .soft)
        coverage = max(0, min(1, try c.value(.coverage, 0.72)))
        tintStrength = max(0, min(1, try c.value(.tintStrength, 0.5)))
        backgroundIntensity = max(0, min(1, try c.value(.backgroundIntensity, 0.55)))
        interactiveGlass = try c.value(.interactiveGlass, true)
        roundedCards = try c.value(.roundedCards, true)
    }

    static let presets: [(title: String, value: SurfacePreferences)] = {
        var calm = SurfacePreferences(); calm.coverage = 0.86; calm.backgroundIntensity = 0.35; calm.tintStrength = 0.35
        var balanced = SurfacePreferences()
        var vivid = SurfacePreferences(); vivid.style = .glass; vivid.coverage = 0.25; vivid.backgroundIntensity = 0.85; vivid.tintStrength = 0.75
        var plain = SurfacePreferences(); plain.style = .solid; plain.coverage = 1; plain.backgroundIntensity = 0.2; plain.tintStrength = 0.3
        return [("Ruhig", calm), ("Ausgewogen", balanced), ("Lebendig", vivid), ("Schlicht", plain)]
    }()
}

// MARK: - Quiet mode

enum ReminderCategory: String, Codable, CaseIterable, Identifiable {
    case tasks, routines, checkIns, therapy, session, wake, wellbeing, assistedLiving

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: "Aufgaben"
        case .routines: "Routinen"
        case .checkIns: "Check-ins"
        case .therapy: "Therapietermine"
        case .session: "Therapiestunde"
        case .wake: "Aufsteh-Wecker"
        case .wellbeing: "Stimmung & Energie"
        case .assistedLiving: "Betreutes Wohnen"
        }
    }
    var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .routines: "repeat"
        case .checkIns: "sun.horizon.fill"
        case .therapy: "calendar.badge.clock"
        case .session: "timer"
        case .wake: "alarm.fill"
        case .wellbeing: "bolt.heart.fill"
        case .assistedLiving: "house.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .tasks: "Wochenaufgaben, Mitteilung & Wecker"
        case .routines: "Routine-Hinweise und wichtige Routinen"
        case .checkIns: "Morgens, mittags, abends …"
        case .therapy: "Wecker vor deinen Terminen"
        case .session: "Abschnitte und Ende der Stunde"
        case .wake: "Wecker mit Aufgabe zum Aufstehen"
        case .wellbeing: "Wochenenergie und Stimmungsmoment"
        case .assistedLiving: "Erinnerungen an BeWo-Termine"
        }
    }
}

struct QuietPause: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Empty means everything (wake alarms and a running session follow their own exemptions).
    var categories: [ReminderCategory] = []
    var start = Date()
    /// `nil` keeps the pause until it is ended by hand.
    var until: Date?
    var endedAt: Date?
    var note = ""

    init(id: UUID = UUID(), categories: [ReminderCategory] = [], start: Date = Date(), until: Date? = nil, endedAt: Date? = nil, note: String = "") {
        self.id = id; self.categories = categories; self.start = start; self.until = until; self.endedAt = endedAt; self.note = note
    }
    // "areas" keeps the readable mirror unambiguous ("categories" already names battery themes there).
    enum CodingKeys: String, CodingKey { case id, categories = "areas", start, until, endedAt, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        categories = try c.value(.categories, [])
        start = try c.value(.start, Date.distantPast)
        until = try c.decodeIfPresent(Date.self, forKey: .until)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        note = try c.value(.note, "")
    }

    var isGlobal: Bool { categories.isEmpty }
    /// The moment the pause stops silencing anything.
    var end: Date? {
        switch (until, endedAt) {
        case let (until?, ended?): min(until, ended)
        case let (until?, nil): until
        case let (nil, ended?): ended
        default: nil
        }
    }
    func covers(_ category: ReminderCategory) -> Bool { categories.isEmpty || categories.contains(category) }
    func isActive(at date: Date) -> Bool { start <= date && (end.map { date < $0 } ?? true) }
    var title: String {
        if categories.isEmpty { return "Alles in Ruhe" }
        return categories.map(\.title).joined(separator: ", ")
    }
}

struct SilencedReminder: Codable, Equatable, Identifiable {
    var id = UUID()
    /// A reminder id (single occurrence) or a source key such as `routine.<id>` (everything from that source).
    var key: String
    var wholeSource = false
    var title = ""
    var category: ReminderCategory = .tasks
    var until: Date?
    var createdAt = Date()

    init(id: UUID = UUID(), key: String, wholeSource: Bool = false, title: String = "", category: ReminderCategory = .tasks, until: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.key = key; self.wholeSource = wholeSource; self.title = title; self.category = category; self.until = until; self.createdAt = createdAt
    }
    enum CodingKeys: String, CodingKey { case id, key, wholeSource, title, category, until, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        key = try c.value(.key, "")
        wholeSource = try c.value(.wholeSource, false)
        title = try c.value(.title, "")
        category = try c.value(.category, .tasks)
        until = try c.decodeIfPresent(Date.self, forKey: .until)
        createdAt = try c.value(.createdAt, Date.distantPast)
    }
}

struct QuietHours: Codable, Equatable {
    var enabled = false
    var startHour = 22
    var startMinute = 0
    var endHour = 7
    var endMinute = 0
    var categories: [ReminderCategory] = [.tasks, .routines, .checkIns, .wellbeing, .assistedLiving]

    init() {}
    enum CodingKeys: String, CodingKey { case enabled, startHour, startMinute, endHour, endMinute, categories = "areas" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, false)
        startHour = max(0, min(23, try c.value(.startHour, 22)))
        startMinute = max(0, min(59, try c.value(.startMinute, 0)))
        endHour = max(0, min(23, try c.value(.endHour, 7)))
        endMinute = max(0, min(59, try c.value(.endMinute, 0)))
        categories = try c.value(.categories, [.tasks, .routines, .checkIns, .wellbeing, .assistedLiving])
    }

    /// Local wall-clock window; overnight windows (22:00–07:00) wrap around midnight.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let start = startHour * 60 + startMinute, end = endHour * 60 + endMinute
        if start == end { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
    var label: String { String(format: "%02d:%02d – %02d:%02d", startHour, startMinute, endHour, endMinute) }
}

struct QuietModeSettings: Codable, Equatable {
    var pauses: [QuietPause] = []
    var silenced: [SilencedReminder] = []
    var mutedCategories: [ReminderCategory] = []
    var quietHours = QuietHours()
    /// Wake alarms keep ringing during a general pause unless they are paused explicitly.
    var wakeAlarmsIgnorePause = true
    /// A running therapy session keeps its phase hints during a general pause unless paused explicitly.
    var runningSessionIgnoresPause = true
    /// Send one quiet notification when a timed pause ends, as a cue to reopen the app.
    var announceEnd = true

    init() {}
    enum CodingKeys: String, CodingKey { case pauses, silenced, mutedCategories, quietHours, wakeAlarmsIgnorePause, runningSessionIgnoresPause, announceEnd }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pauses = try c.value(.pauses, [])
        silenced = try c.value(.silenced, [])
        mutedCategories = try c.value(.mutedCategories, [])
        quietHours = try c.value(.quietHours, QuietHours())
        wakeAlarmsIgnorePause = try c.value(.wakeAlarmsIgnorePause, true)
        runningSessionIgnoresPause = try c.value(.runningSessionIgnoresPause, true)
        announceEnd = try c.value(.announceEnd, true)
    }
}

enum QuietPolicy {
    /// Source key and category of a planned reminder, derived from its route and group.
    static func classify(group: String, route: String) -> (category: ReminderCategory, source: String) {
        let parts = route.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch parts.first ?? "" {
        case "routine": return (.routines, "routine." + (parts.count > 1 ? parts[1] : ""))
        case "task": return (.tasks, "task." + (parts.count > 1 ? parts[1] : ""))
        case "checkin": return (.checkIns, "checkin." + (parts.count > 1 ? parts[1] : ""))
        case "wake": return (.wake, "wake." + (parts.count > 1 ? parts[1] : ""))
        case "therapy": return (.therapy, "therapy")
        case "session": return (.session, group.hasPrefix("session.phase") ? "session.phase" : "session")
        case "energy": return (.wellbeing, "energy")
        case "wellness": return (.wellbeing, "wellness")
        case "bewo": return (.assistedLiving, "bewo")
        default: return (.tasks, group)
        }
    }

    /// `nil` when the reminder may fire, otherwise a short German reason.
    static func reason(category: ReminderCategory, source: String, id: String, fireAt: Date, settings: QuietModeSettings, calendar: Calendar = .current) -> String? {
        if settings.mutedCategories.contains(category) { return "Dauerhaft stumm" }
        if let item = settings.silenced.first(where: { ($0.wholeSource ? $0.key == source : $0.key == id) && ($0.until.map { fireAt < $0 } ?? true) }) {
            return item.until.map { "Stumm bis " + shortStamp($0, calendar: calendar) } ?? (item.wholeSource ? "Stummgeschaltet" : "Übersprungen")
        }
        for pause in settings.pauses where pause.isActive(at: fireAt) && pause.covers(category) {
            if pause.isGlobal && category == .wake && settings.wakeAlarmsIgnorePause { continue }
            if pause.isGlobal && category == .session && settings.runningSessionIgnoresPause { continue }
            return pause.end.map { "Ruhe bis " + shortStamp($0, calendar: calendar) } ?? "Ruhe aktiv"
        }
        if settings.quietHours.contains(fireAt, calendar: calendar) && settings.quietHours.categories.contains(category) { return "Ruhezeit " + settings.quietHours.label }
        return nil
    }

    static func allows(_ slot: CompanionAlarmSlot, settings: QuietModeSettings, calendar: Calendar = .current) -> Bool {
        let kind = classify(group: slot.group, route: slot.route)
        return reason(category: kind.category, source: kind.source, id: slot.id, fireAt: slot.fireAt, settings: settings, calendar: calendar) == nil
    }

    static func activePauses(_ settings: QuietModeSettings, at date: Date = Date()) -> [QuietPause] {
        settings.pauses.filter { $0.isActive(at: date) }.sorted { ($0.end ?? .distantFuture) > ($1.end ?? .distantFuture) }
    }
    static func globalPause(_ settings: QuietModeSettings, at date: Date = Date()) -> QuietPause? {
        activePauses(settings, at: date).first { $0.isGlobal }
    }
    static func isQuiet(_ category: ReminderCategory, settings: QuietModeSettings, at date: Date = Date()) -> Bool {
        settings.mutedCategories.contains(category) || activePauses(settings, at: date).contains { $0.covers(category) && !($0.isGlobal && category == .wake && settings.wakeAlarmsIgnorePause) }
    }

    /// Adds a pause. A new general pause replaces an older general one instead of stacking.
    static func pause(_ settings: inout QuietModeSettings, categories: [ReminderCategory], until: Date?, now: Date = Date(), note: String = "") {
        let clean = Array(Set(categories)).sorted { $0.rawValue < $1.rawValue }
        for index in settings.pauses.indices where settings.pauses[index].isActive(at: now) && Set(settings.pauses[index].categories) == Set(clean) {
            settings.pauses[index].endedAt = now
        }
        settings.pauses.insert(QuietPause(categories: clean, start: now, until: until.map { max($0, now.addingTimeInterval(60)) }, note: note), at: 0)
        prune(&settings, now: now)
    }
    /// Ends a pause early. The pause stays in the history with its real end.
    static func end(_ id: UUID, in settings: inout QuietModeSettings, now: Date = Date()) {
        guard let index = settings.pauses.firstIndex(where: { $0.id == id }) else { return }
        settings.pauses[index].endedAt = now
    }
    static func endAll(_ settings: inout QuietModeSettings, now: Date = Date()) {
        for index in settings.pauses.indices where settings.pauses[index].isActive(at: now) { settings.pauses[index].endedAt = now }
    }
    static func extend(_ id: UUID, in settings: inout QuietModeSettings, by seconds: TimeInterval, now: Date = Date()) {
        guard let index = settings.pauses.firstIndex(where: { $0.id == id }), settings.pauses[index].isActive(at: now) else { return }
        settings.pauses[index].until = max(settings.pauses[index].until ?? now, now).addingTimeInterval(seconds)
    }
    static func silence(_ settings: inout QuietModeSettings, key: String, wholeSource: Bool, title: String, category: ReminderCategory, until: Date?, now: Date = Date()) {
        settings.silenced.removeAll { $0.key == key && $0.wholeSource == wholeSource }
        settings.silenced.insert(SilencedReminder(key: key, wholeSource: wholeSource, title: String(title.prefix(120)), category: category, until: until, createdAt: now), at: 0)
        prune(&settings, now: now)
    }
    static func restore(_ id: UUID, in settings: inout QuietModeSettings) {
        settings.silenced.removeAll { $0.id == id }
    }
    /// Keeps the history short: ended pauses older than 30 days and expired silences disappear.
    static func prune(_ settings: inout QuietModeSettings, now: Date = Date()) {
        let horizon = now.addingTimeInterval(-30 * 86400)
        settings.pauses.removeAll { pause in pause.end.map { $0 < horizon } ?? false }
        settings.pauses = Array(settings.pauses.prefix(40))
        settings.silenced.removeAll { item in item.until.map { $0 < now.addingTimeInterval(-86400) } ?? false }
        settings.silenced = Array(settings.silenced.prefix(200))
    }

    /// Next quiet-relevant moment: the end of the latest active timed pause.
    static func resumeDate(_ settings: QuietModeSettings, now: Date = Date()) -> Date? {
        activePauses(settings, at: now).compactMap(\.until).filter { $0 > now }.max()
    }

    static func shortStamp(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EE d. MMM, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Unified reminder inventory

enum ReminderChannel: String, Codable { case notification, alarm }

/// One upcoming reminder as the app plans it, before the operating system receives it.
struct PlannedReminder: Identifiable, Equatable {
    var id: String
    /// The identifier quiet mode matches when a single occurrence is skipped.
    var key: String
    var source: String
    var category: ReminderCategory
    var channel: ReminderChannel
    var fireAt: Date
    var title: String
    var detail: String
    var route: String
    var repeats = false
    var quietReason: String?
    var isQuiet: Bool { quietReason != nil }
}

/// Tasks use repeating notification triggers. Under a timed pause one occurrence is delivered after the pause
/// instead; the repeating trigger returns the next time the app refreshes its reminders.
enum TaskReminderQuietPlan: Equatable {
    case repeating
    case once(Date)
    case none
}

enum ReminderInventory {
    static func nextDates(weekday: Int?, hour: Int, minute: Int, after now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var components = DateComponents(hour: hour, minute: minute, second: 0)
        components.weekday = weekday
        var result: [Date] = [], cursor = now
        for _ in 0..<max(0, count) {
            guard let date = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { break }
            result.append(date)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86400)
            cursor = nextDay.addingTimeInterval(-0.001)
        }
        return result
    }

    static func taskPlan(_ slot: TaskReminderSlot, settings: QuietModeSettings, now: Date = Date(), calendar: Calendar = .current) -> TaskReminderQuietPlan {
        let dates = nextDates(weekday: slot.weekday, hour: slot.hour, minute: slot.minute, after: now, count: slot.weekday == nil ? 21 : 6, calendar: calendar)
        let source = "task.\(slot.taskID)"
        let allowed = dates.filter { date in
            QuietPolicy.reason(category: .tasks, source: source, id: slot.identifier + ".\(Int(date.timeIntervalSince1970))", fireAt: date, settings: settings, calendar: calendar) == nil
        }
        if allowed.count == dates.count { return .repeating }
        if let first = allowed.first { return .once(first) }
        return .none
    }

    /// Everything the app would schedule in the coming days, each annotated with its quiet state.
    static func upcoming(_ data: AppData, now: Date = Date(), days: Int = 7, calendar: Calendar = .current) -> [PlannedReminder] {
        let horizon = calendar.date(byAdding: .day, value: max(1, days), to: now) ?? now.addingTimeInterval(Double(days) * 86400)
        let quiet = data.quietMode
        var items: [PlannedReminder] = []
        func add(_ id: String, _ group: String, _ route: String, _ channel: ReminderChannel, _ fire: Date, _ title: String, _ detail: String, repeats: Bool = false) {
            guard fire > now, fire <= horizon else { return }
            let kind = QuietPolicy.classify(group: group, route: route)
            items.append(PlannedReminder(id: channel.rawValue + "." + id, key: id, source: kind.source, category: kind.category, channel: channel, fireAt: fire, title: title, detail: detail, route: route, repeats: repeats,
                                         quietReason: QuietPolicy.reason(category: kind.category, source: kind.source, id: id, fireAt: fire, settings: quiet, calendar: calendar)))
        }
        for slot in CompanionAlarmPlanner.rawCandidates(data, now: now, calendar: calendar) {
            add(slot.id, slot.group, slot.route, .alarm, slot.fireAt, slot.title, "Wecker")
        }
        for slot in TaskReminderPlanner.slots(tasks: data.weeklyTasks, schedule: data.schedule, now: now) {
            guard let task = data.weeklyTasks.first(where: { $0.id == slot.taskID }) else { continue }
            for date in nextDates(weekday: slot.weekday, hour: slot.hour, minute: slot.minute, after: now, count: days + 1, calendar: calendar) {
                add(slot.identifier + ".\(Int(date.timeIntervalSince1970))", "task.\(task.id)", "task|\(task.id)", .notification, date, task.title, slot.weekday == nil ? "Täglich bis erledigt" : "Wöchentlich bis erledigt", repeats: true)
            }
        }
        for slot in CheckInReminderPlanner.slots(data: data, now: now, calendar: calendar) {
            add(slot.id, "checkin.\(slot.slotID?.uuidString ?? slot.kind.rawValue)", "checkin|\(slot.kind.rawValue)|\(slot.slotID?.uuidString ?? "")", .notification, slot.fireAt, slot.title ?? slot.kind.title, "Check-in")
        }
        var seenOccurrences = Set<String>()
        let routineSlots = RoutinePlanner.slots(data: data, now: now, calendar: calendar).filter { slot in
            guard let routine = data.routines.first(where: { $0.id == slot.occurrence.routineID }) else { return false }
            return !(data.appleIntegration.remindersEnabled && routine.appleReminders != false)
        }
        for slot in routineSlots where seenOccurrences.insert(slot.occurrence.id).inserted {
            guard let routine = data.routines.first(where: { $0.id == slot.occurrence.routineID }) else { continue }
            let retries = routineSlots.filter { $0.occurrence.id == slot.occurrence.id }.count - 1
            let time = routine.times.first { $0.id == slot.occurrence.timeID }?.title ?? ""
            add(slot.id, "routine.\(routine.id).\(slot.occurrence.timeID)", "routine|\(routine.id)", .notification, slot.fireAt, routine.title + (time.isEmpty ? "" : " · " + time), retries > 0 ? "Routine · danach \(retries)× erneut bis erledigt" : "Routine")
        }
        if data.reminderPreferences.energyReviewEnabled, let next = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: now, calendar: calendar) {
            let date = next.addingTimeInterval(-Double(max(0, min(1440, data.reminderPreferences.energyReviewMinutesBeforeTherapy))) * 60)
            add("therapy.energy-week", "energy", "energy", .notification, date, "Deine Wochenenergie", "Vor der Therapie")
        }
        if data.wellnessSettings.reminderEnabled {
            let settings = data.wellnessSettings
            for date in nextDates(weekday: max(1, min(7, settings.reminderWeekday)), hour: max(0, min(23, settings.reminderHour)), minute: max(0, min(59, settings.reminderMinute)), after: now, count: 2, calendar: calendar) {
                add("therapy.weekly-checkin.\(Int(date.timeIntervalSince1970))", "wellness", "wellness", .notification, date, "Ein Moment für dich", "Wöchentlich", repeats: true)
            }
        }
        if let session = data.currentSession, session.pausedAt == nil, session.endedAt == nil {
            var cursor = session.clockStart
            for (index, phase) in session.phases.enumerated() {
                cursor = cursor.addingTimeInterval(TimeInterval(max(1, phase.minutes) * 60))
                let last = index == session.phases.count - 1
                guard last ? data.sessionPreferences.notifyAtEnd : data.sessionPreferences.notifyAtPhases else { continue }
                add("therapy.session.\(session.id).\(index)", last ? "session" : "session.phase", "session|\(session.id)", .notification, cursor, last ? "Deine geplante Zeit ist um" : "Nächster Zeitabschnitt", "Laufende Stunde")
            }
        }
        for slot in AssistedLivingPlanner.reminderSlots(data, now: now, calendar: calendar) {
            add(slot.id, "bewo", slot.route, .notification, slot.fireAt, slot.title, slot.detail)
        }
        return items.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
}
