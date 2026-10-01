import Foundation

struct DailyCheckInSlot: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: GuidedCheckInKind = .free
    var name = "Eigener Check-in"
    var enabled = true
    var startHour = 5
    var endHour = 11
    var title: String { kind == .free ? name : kind.title }
    var windowText: String { startHour == endHour ? "Ganztägig" : String(format: "%02d:00 – %02d:00", startHour, endHour) + (startHour > endHour ? " am Folgetag" : "") }
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return startHour == endHour || (startHour < endHour ? hour >= startHour && hour < endHour : hour >= startHour || hour < endHour)
    }
    func anchor(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        if startHour > endHour && calendar.component(.hour, from: date) < endHour { return calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        return day
    }
    static let defaults: [DailyCheckInSlot] = [
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, kind: .morning, name: "Morgen", startHour: 5, endHour: 11),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, kind: .noon, name: "Mittag", startHour: 11, endHour: 18),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, kind: .afternoon, name: "Nachmittag", enabled: false, startHour: 14, endHour: 18),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, kind: .evening, name: "Abend", startHour: 18, endHour: 23),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, kind: .night, name: "Nacht", enabled: true, startHour: 23, endHour: 5)
    ]
}
enum DayCheckInPolicy {
    static func slots(_ settings: CompanionSettings) -> [DailyCheckInSlot] { settings.dayCheckInSlots ?? DailyCheckInSlot.defaults }
    static func slot(kind: GuidedCheckInKind, id: UUID? = nil, settings: CompanionSettings) -> DailyCheckInSlot? {
        let all = slots(settings)
        if let id { return all.first { $0.id == id && $0.kind == kind } }
        return kind == .free || kind == .therapy ? nil : all.first { $0.kind == kind }
    }
    static func allows(kind: GuidedCheckInKind, id: UUID? = nil, settings: CompanionSettings, at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        if id == nil && [.free, .therapy].contains(kind) { return true }
        guard let value = slot(kind: kind, id: id, settings: settings) else { return false }
        return value.enabled && value.contains(date, calendar: calendar)
    }
    static func existing(for entry: GuidedCheckIn, in data: AppData, calendar: Calendar = .current) -> GuidedCheckIn? {
        guard data.companionSettings.allowMultipleCheckInsPerSlot != true else { return nil }
        let configured = slot(kind: entry.kind, id: entry.daySlotID, settings: data.companionSettings)
        return data.guidedCheckIns.filter { saved in
            if entry.kind == .therapy, let sessionID = entry.sessionID { return saved.kind == .therapy && saved.sessionID == sessionID }
            guard saved.kind == entry.kind else { return false }
            if let slotID = entry.daySlotID {
                guard saved.daySlotID == slotID || (saved.daySlotID == nil && entry.kind != .free) else { return false }
            } else if saved.daySlotID != nil && entry.kind == .free { return false }
            let anchor: (Date) -> Date = { configured?.anchor(for: $0, calendar: calendar) ?? calendar.startOfDay(for: $0) }
            return anchor(saved.date) == anchor(entry.date)
        }.sorted { a, b in a.isDraft != b.isDraft ? !a.isDraft : a.date > b.date }.first
    }
    static func reopen(_ entry: GuidedCheckIn, in data: AppData) -> GuidedCheckIn { existing(for: entry, in: data) ?? entry }
    static func entry(_ slot: DailyCheckInSlot, at date: Date = Date()) -> GuidedCheckIn {
        GuidedCheckIn(date: date, kind: slot.kind, daySlotID: slot.id, customTitle: slot.kind == .free ? slot.title : nil)
    }
}
enum MoodBarometer {
    static func score(_ percent: Int) -> Int { max(1, min(5, 1 + Int((Double(max(0, min(100, percent))) / 25).rounded()))) }
    static func title(_ percent: Int) -> String { MoodCheckIn.moodTitles[score(percent) - 1] }
}
struct BatteryKeywordInsight: Identifiable {
    var id: String { direction.rawValue + ":" + keyword.lowercased() }
    var keyword: String
    var direction: BatteryDirection
    var count: Int
    var impact: Int
    var points: [BatteryPoint]
}
struct MoodComparison {
    var latest: Double
    var reference: Double?
    var previousDays: Int
    var difference: Double? { reference.map { latest - $0 } }
    var message: String {
        guard let difference, previousDays >= 5 else { return "Für einen persönlichen Vergleich fehlen noch 5 frühere Tage mit Stimmungseinträgen." }
        if difference >= 1 { return "Zuletzt deutlich höher als dein persönlicher Vergleichswert." }
        if difference <= -1 { return "Zuletzt deutlich niedriger als dein persönlicher Vergleichswert." }
        return "Zuletzt in der Nähe deines persönlichen Vergleichswerts."
    }
}
enum InsightsAnalytics {
    static func keywords(data: AppData, period: WellnessPeriod) -> [BatteryKeywordInsight] {
        let groups = Dictionary(grouping: data.batteryPoints.filter { period.contains($0.date) }, by: { $0.direction.rawValue + ":" + $0.title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE")) })
        return groups.values.compactMap { values in
            let sorted = values.sorted { $0.date > $1.date }
            guard let first = sorted.first, !first.title.isEmpty else { return nil }
            return BatteryKeywordInsight(keyword: first.title, direction: first.direction, count: values.count, impact: values.reduce(0) { $0 + max(1, min(5, $1.impact)) }, points: sorted)
        }.sorted { $0.impact == $1.impact ? $0.id < $1.id : $0.impact > $1.impact }
    }
    static func comparison(data: AppData, now: Date = Date()) -> MoodComparison? {
        let daily = WellnessAnalytics.daily(data, period: .rolling(days: 30, now: now)).filter { $0.mood != nil }
        guard let latest = daily.last, let value = latest.mood else { return nil }
        let previous = daily.dropLast().suffix(14).compactMap(\.mood)
        return MoodComparison(latest: value, reference: previous.count >= 5 ? WellnessAnalytics.average(previous) : nil, previousDays: previous.count)
    }
    static func trend(data: AppData, period: WellnessPeriod) -> Double? {
        let rows = WellnessAnalytics.daily(data, period: period).compactMap(\.mood)
        guard rows.count >= 4 else { return nil }
        let split = rows.count / 2
        return WellnessAnalytics.average(Array(rows.suffix(rows.count - split)))! - WellnessAnalytics.average(Array(rows.prefix(split)))!
    }
}
enum PersonalGreeting {
    static func title(at date: Date, name: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let text = hour < 5 ? "Gute Nacht" : hour < 11 ? "Guten Morgen" : hour < 14 ? "Guten Mittag" : hour < 18 ? "Guten Nachmittag" : "Guten Abend"
        return text + (name.isEmpty ? "" : ", " + name)
    }
    static func sentence(at date: Date, calendar: Calendar = .current) -> String {
        let phrases = ["Du darfst in deinem Tempo ankommen.", "Ein kleiner Schritt ist auch ein Schritt.", "Wie geht es deinem Akku gerade?", "Hier ist Raum für das, was dich beschäftigt.", "Was hat dir heute gutgetan?", "Du musst nicht jede Frage beantworten.", "Dein Überblick wächst mit deinen Einträgen."]
        return phrases[(calendar.component(.day, from: date) + calendar.component(.hour, from: date) / 4) % phrases.count]
    }
}

struct CompanionAlarmSlot: Equatable, Identifiable {
    var id: String
    var group: String
    var fireAt: Date
    var title: String
    var route: String
}
enum CompanionAlarmPlanner {
    static func candidates(_ data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [CompanionAlarmSlot] {
        var slots = RoutinePlanner.slots(data: data, now: now, calendar: calendar).compactMap { slot -> CompanionAlarmSlot? in
            guard let routine = data.routines.first(where: { $0.id == slot.occurrence.routineID }), routine.urgentAlarm else { return nil }
            let detail = routine.times.first { $0.id == slot.occurrence.timeID }?.title ?? ""
            return .init(id: slot.id, group: "routine.\(routine.id).\(slot.occurrence.timeID)", fireAt: slot.fireAt, title: data.companionSettings.alarmShowsActualTitles == false ? "Deine wichtige Routine" : routine.title + (detail.isEmpty ? "" : " · " + detail), route: "routine|\(routine.id)")
        }
        for slot in CheckInReminderPlanner.slots(data: data, now: now, calendar: calendar) {
            guard let reminder = data.companionSettings.checkInReminders?.first(where: { $0.id == slot.reminderID }), reminder.alarmEnabled == true else { continue }
            slots.append(.init(id: slot.id, group: "checkin.\(slot.slotID?.uuidString ?? slot.kind.rawValue)", fireAt: slot.fireAt, title: slot.title ?? slot.kind.title, route: "checkin|\(slot.kind.rawValue)|\(slot.slotID?.uuidString ?? "")"))
        }
        for slot in TaskReminderPlanner.slots(tasks: data.weeklyTasks, schedule: data.schedule, now: now) {
            guard let task = data.weeklyTasks.first(where: { $0.id == slot.taskID }), task.reminder?.alarmEnabled ?? data.companionSettings.taskAlarmsEnabled ?? false else { continue }
            var components = DateComponents(hour: slot.hour, minute: slot.minute, second: 0)
            components.weekday = slot.weekday
            var cursor = now
            let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86400)
            for _ in 0..<7 {
                guard let date = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first), date <= horizon else { break }
                slots.append(.init(id: slot.identifier + ".\(Int(date.timeIntervalSince1970))", group: "task.\(task.id)", fireAt: date, title: data.reminderPreferences.privateTaskTitles ? "Dein nächster kleiner Schritt" : task.title, route: "task|\(task.id)"))
                // Starting the next search on the following local day prevents a repeated DST hour from ringing twice.
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86400)
                cursor = nextDay.addingTimeInterval(-0.001)
            }
        }
        if data.reminderPreferences.energyReviewEnabled, data.companionSettings.energyReviewAlarm == true,
           let next = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: now) {
            let date = next.addingTimeInterval(-Double(max(0, min(1440, data.reminderPreferences.energyReviewMinutesBeforeTherapy))) * 60)
            if date > now { slots.append(.init(id: "energy.\(Int(date.timeIntervalSince1970))", group: "energy", fireAt: date, title: "Deine Wochenenergie", route: "energy")) }
        }
        if data.wellnessSettings.reminderEnabled, data.companionSettings.wellnessAlarmEnabled == true {
            let settings = data.wellnessSettings
            let components = DateComponents(hour: max(0, min(23, settings.reminderHour)), minute: max(0, min(59, settings.reminderMinute)), second: 0, weekday: max(1, min(7, settings.reminderWeekday)))
            if let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first) {
                slots.append(.init(id: "wellness.\(Int(date.timeIntervalSince1970))", group: "wellness", fireAt: date, title: "Ein Moment für deine Stimmung", route: "wellness"))
            }
        }
        if data.schedule.therapyAlarmsEnabled ?? !data.schedule.alarmIDs.isEmpty {
            for appointment in TherapyDateHelper.occurrences(schedule: data.schedule, after: now, count: 8, calendar: calendar) {
                for offset in Set(data.schedule.reminderOffsetsMinutes).filter({ (0...10080).contains($0) }).sorted() {
                    let fire = appointment.addingTimeInterval(-Double(offset) * 60)
                    if fire > now { slots.append(.init(id: "therapy.\(Int(appointment.timeIntervalSince1970)).\(offset)", group: "therapy", fireAt: fire, title: offset == 0 ? "Dein Therapietermin beginnt" : "Therapie in \(offset) Minuten", route: "therapy")) }
                }
            }
        }
        let phaseAlarms = data.companionSettings.sessionPhaseAlarmsEnabled ?? (data.companionSettings.sessionAlarmsEnabled == true && data.sessionPreferences.notifyAtPhases)
        if let session = data.currentSession, session.pausedAt == nil, session.endedAt == nil {
            if (data.companionSettings.sessionAlarmsEnabled == true || phaseAlarms), session.expectedEnd > now {
                slots.append(.init(id: "session.end.\(session.id).\(Int(session.expectedEnd.timeIntervalSince1970))", group: "session", fireAt: session.expectedEnd, title: "Deine Therapiezeit ist beendet", route: "session|\(session.id)"))
            }
            if phaseAlarms {
                var boundary = session.clockStart
                for (index, phase) in session.phases.dropLast().enumerated() {
                    boundary = boundary.addingTimeInterval(Double(max(1, phase.minutes)) * 60)
                    let title = data.sessionPreferences.usesPrivateLiveActivity ? "Abschnitt \(index + 1) beendet · weiter mit Abschnitt \(index + 2)" : String(phase.title.prefix(35)) + " beendet · " + String(session.phases[index + 1].title.prefix(35))
                    if boundary > now { slots.append(.init(id: "session.phase.\(session.id).\(phase.id).\(Int(boundary.timeIntervalSince1970))", group: "session.phase", fireAt: boundary, title: title, route: "session|\(session.id)")) }
                }
            }
        }
        return slots.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
    static func admitted(_ all: [CompanionAlarmSlot], budget: Int = 24) -> [CompanionAlarmSlot] {
        var groups = Set<String>(), ids = Set<String>(), selected: [CompanionAlarmSlot] = []
        // Reserve the imminent running session boundaries before recurring inventories.
        for slot in all where slot.group.hasPrefix("session") && selected.count < max(0, budget) { if ids.insert(slot.id).inserted { selected.append(slot); groups.insert(slot.group) } }
        for slot in all where !slot.group.hasPrefix("session") && groups.insert(slot.group).inserted && selected.count < max(0, budget) {
            if ids.insert(slot.id).inserted { selected.append(slot) }
        }
        for slot in all where selected.count < max(0, budget) { if ids.insert(slot.id).inserted { selected.append(slot) } }
        return selected.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
}

/// Device-independent decision, shared with alarm regression checks.
enum AlarmOwnershipPolicy {
    static func keepAlerting(key: String, data: AppData) -> Bool {
        if key.hasPrefix("therapy.routine.") {
            guard let routine = data.routines.first(where: { key.hasPrefix("therapy.routine.\($0.id).") }), routine.urgentAlarm,
                  RoutinePlanner.active(routine, settings: data.companionSettings, at: Date()) else { return false }
            return !data.routineCompletions.contains { key.hasPrefix("therapy.routine.\($0.routineID).\($0.timeID).\(Int($0.scheduledAt.timeIntervalSince1970)).") }
        }
        if key.hasPrefix("therapy.task.") { return data.weeklyTasks.contains { !$0.completed && key.hasPrefix("therapy.task.\($0.id).") } }
        if key.hasPrefix("session.") { return data.currentSession.map { $0.pausedAt == nil && $0.endedAt == nil } ?? false }
        if key.hasPrefix("therapy.") { return data.schedule.therapyAlarmsEnabled ?? false }
        return true
    }
}
