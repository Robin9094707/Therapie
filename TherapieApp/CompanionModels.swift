import Foundation

enum GuidedCheckInKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning, noon, afternoon, evening, night, therapy, free
    var id: String { rawValue }
    var title: String {
        switch self { case .morning: "Morgen-Check-in"; case .noon: "Mittags-Check-in"; case .afternoon: "Nachmittags-Check-in"; case .night: "Nacht-Check-in"; case .evening: "Abend-Check-in"; case .therapy: "Therapie-Check-in"; case .free: "Freier Check-in" }
    }
    var symbol: String {
        switch self { case .morning: "sun.max.fill"; case .noon: "sun.max"; case .afternoon: "sun.haze.fill"; case .night: "moon.fill"; case .evening: "moon.stars.fill"; case .therapy: "leaf.fill"; case .free: "sparkles" }
    }
}
struct CheckInTaskDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var details = ""
    var source = "Von mir"
    var smallStep = ""
    var dueDate: Date?
}
struct GuidedCheckIn: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var kind: GuidedCheckInKind = .free
    var sessionID: UUID?
    var mood: Int?
    var batteryPercent: Int?
    var stress: Int?
    var sensoryLoad: Int?
    var sleepHours: Double?
    var summary = ""
    var givesEnergy = ""
    var takesEnergy = ""
    var smallWin = ""
    var nextNeed = ""
    var therapyQuestion = ""
    var tasks: [CheckInTaskDraft] = []
    var mediaIDs: [UUID] = []
    var taskIDs: [UUID] = []
    var isDraft = true
    var step = 0
    var moodPercent: Int?
    var energyPoints: [BatteryPoint]?
    var daySlotID: UUID?
    var customTitle: String?
    var displayTitle: String { customTitle ?? kind.title }
}
struct RoutineTime: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var weekdays = Array(1...7)
    var hour = 6
    var minute = 30
    var weekendHour: Int?
    var weekendMinute: Int?
    func clock(weekday: Int) -> (hour: Int, minute: Int) {
        let weekend = weekday == 1 || weekday == 7
        return (max(0, min(23, weekend ? weekendHour ?? hour : hour)), max(0, min(59, weekend ? weekendMinute ?? minute : minute)))
    }
}
struct DailyRoutine: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var symbol = "checkmark.circle"
    var details = ""
    var enabled = true
    var pausedUntil: Date?
    var pauseOnVacation = true
    var goalID: UUID?
    var times = [RoutineTime()]
    var remindersEnabled = true
    var urgentAlarm = false
    var retryMinutes = 20
    var escalationHour: Int? = 23
    var escalationMinutes = 5
    var quietStartHour: Int?
    var quietEndHour = 7
}
enum RoutineOutcome: String, Codable, Hashable { case done, skipped }
struct RoutineCompletion: Codable, Equatable, Identifiable {
    var id = UUID()
    var routineID: UUID
    var timeID: UUID
    var scheduledAt: Date
    var recordedAt = Date()
    var outcome: RoutineOutcome = .done
    var note = ""
    var routineTitle: String?
    var timeTitle: String?
    var corrections: [RoutineCorrection]?
}
struct RoutineCorrection: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var previousOutcome: RoutineOutcome
    var previousNote: String
    var outcome: RoutineOutcome
    var note: String
    var reason: String
}
struct RoutineSnooze: Codable, Equatable, Identifiable {
    var id: String
    var until: Date
}
struct CompanionSettings: Codable, Equatable {
    var vacationUntil: Date?
    var privateRoutineTitles = true
    var offerTherapyCheckIn = true
    // Optional additions retain schema-7 backups and existing local snapshots.
    var checkInReminders: [CheckInReminder]?
    var dayCheckInSlots: [DailyCheckInSlot]?
    var taskAlarmsEnabled: Bool?
    var energyReviewAlarm: Bool?
    var sessionPhaseAlarmsEnabled: Bool?
    var sessionAlarmsEnabled: Bool?
    var wellnessAlarmEnabled: Bool?
}
struct RoutineOccurrence: Identifiable, Equatable {
    var routineID: UUID
    var timeID: UUID
    var due: Date
    var end: Date
    var id: String { "\(routineID).\(timeID).\(Int(due.timeIntervalSince1970))" }
}
struct RoutineReminderSlot: Identifiable, Equatable {
    var occurrence: RoutineOccurrence
    var fireAt: Date
    var id: String { "therapy.routine.\(occurrence.id).\(Int(fireAt.timeIntervalSince1970))" }
}
enum RoutinePlanner {
    static func active(_ routine: DailyRoutine, settings: CompanionSettings, at date: Date) -> Bool {
        routine.enabled && !(routine.pausedUntil.map { $0 > date } ?? false) && !(routine.pauseOnVacation && (settings.vacationUntil.map { $0 > date } ?? false))
    }
    static func resolved(_ occurrence: RoutineOccurrence, completions: [RoutineCompletion]) -> Bool {
        completions.contains { $0.routineID == occurrence.routineID && $0.timeID == occurrence.timeID && $0.scheduledAt == occurrence.due }
    }
    static func occurrences(_ routines: [DailyRoutine], settings: CompanionSettings, now: Date, days: Int = 7, calendar: Calendar = .current) -> [RoutineOccurrence] {
        let today = calendar.startOfDay(for: now)
        var output: [RoutineOccurrence] = []
        for offset in -1..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            for routine in routines {
                for time in routine.times where time.weekdays.contains(weekday) {
                    let clock = time.clock(weekday: weekday)
                    guard let due = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                          calendar.isDate(due, inSameDayAs: day), active(routine, settings: settings, at: due),
                          let end = calendar.date(byAdding: .day, value: 1, to: due), end > now else { continue }
                    var closes = end
                    // An earlier weekday/weekend clock replaces yesterday's occurrence instead of overlapping it.
                    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) {
                        let nextWeekday = calendar.component(.weekday, from: tomorrow)
                        if time.weekdays.contains(nextWeekday) {
                            let nextClock = time.clock(weekday: nextWeekday)
                            if let nextDue = calendar.date(bySettingHour: nextClock.hour, minute: nextClock.minute, second: 0, of: tomorrow, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) { closes = min(closes, nextDue) }
                        }
                    }
                    if closes > now { output.append(RoutineOccurrence(routineID: routine.id, timeID: time.id, due: due, end: closes)) }
                }
            }
        }
        return output.sorted { $0.due == $1.due ? $0.id < $1.id : $0.due < $1.due }
    }
    static func slots(data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [RoutineReminderSlot] {
        var output: [RoutineReminderSlot] = []
        for occurrence in occurrences(data.routines, settings: data.companionSettings, now: now, calendar: calendar) {
            guard !resolved(occurrence, completions: data.routineCompletions),
                  let routine = data.routines.first(where: { $0.id == occurrence.routineID }), routine.remindersEnabled,
                  active(routine, settings: data.companionSettings, at: max(now, occurrence.due)) else { continue }
            let snooze = data.routineSnoozes.first { $0.id == occurrence.id }?.until
            var fire = occurrence.due
            if let snooze, snooze > fire { fire = snooze }
            // A finite OS queue is replenished on launch and every notification action.
            for _ in 0..<300 {
                guard fire < occurrence.end else { break }
                let hour = calendar.component(.hour, from: fire)
                let quiet = routine.quietStartHour.map { start in
                    start == routine.quietEndHour ? true : (start > routine.quietEndHour ? hour >= start || hour < routine.quietEndHour : hour >= start && hour < routine.quietEndHour)
                } ?? false
                if fire > now && !quiet { output.append(RoutineReminderSlot(occurrence: occurrence, fireAt: fire)) }
                let escalated = routine.escalationHour.map { hour >= $0 } ?? false
                let minutes = max(5, min(180, escalated ? routine.escalationMinutes : routine.retryMinutes))
                fire = fire.addingTimeInterval(Double(minutes) * 60)
            }
        }
        return output.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
    /// Give each upcoming occurrence a first hint before spending the remaining capacity on retries.
    static func admittedSlots(_ candidates: [RoutineReminderSlot], budget: Int) -> [RoutineReminderSlot] {
        var seen = Set<String>(), selected: [RoutineReminderSlot] = []
        let capacity = max(0, budget)
        for slot in candidates where seen.insert(slot.occurrence.id).inserted {
            if selected.count < capacity { selected.append(slot) }
        }
        var identifiers = Set(selected.map(\.id))
        for slot in candidates where selected.count < capacity {
            if identifiers.insert(slot.id).inserted { selected.append(slot) }
        }
        return selected.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
    static func due(data: AppData, now: Date = Date()) -> [RoutineOccurrence] {
        occurrences(data.routines, settings: data.companionSettings, now: now, days: 1).filter {
            $0.due <= now && !resolved($0, completions: data.routineCompletions)
        }.filter { occurrence in
            guard let routine = data.routines.first(where: { $0.id == occurrence.routineID }) else { return false }
            return active(routine, settings: data.companionSettings, at: now)
        }
    }
}

/// One snapshot mutation makes draft completion and task creation atomic and idempotent.
enum GuidedCheckInMutation {
    static func apply(_ entry: GuidedCheckIn, complete: Bool, to data: inout AppData) {
        var clean = entry
        if complete {
            clean.isDraft = false
            let previous = data.guidedCheckIns.first { $0.id == clean.id }
            let previousIDs = Set(previous?.taskIDs ?? [])
            let week = clean.date.therapyWeek
            var links: [UUID] = []
            for draft in clean.tasks where !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = draft.details + "\nAufgabe: " + draft.source
                if let index = data.weeklyTasks.firstIndex(where: { $0.id == draft.id }) {
                    // Only synchronize content after explicit Save, preserving task progress/completion.
                    data.weeklyTasks[index].title = title
                    data.weeklyTasks[index].details = details
                    data.weeklyTasks[index].smallStep = draft.smallStep
                    data.weeklyTasks[index].dueDate = draft.dueDate
                    links.append(draft.id)
                } else if !previousIDs.contains(draft.id) {
                    data.weeklyTasks.insert(WeeklyTask(id: draft.id, weekOfYear: week.week, yearForWeekOfYear: week.year, title: title, details: details, dueDate: draft.dueDate, smallStep: draft.smallStep), at: 0)
                    links.append(draft.id)
                } else {
                    // A task deleted independently is never resurrected by editing its old check-in.
                    links.append(draft.id)
                }
            }
            clean.taskIDs = links
            if let points = clean.energyPoints {
                let valid = points.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { point in
                    var point = point; point.date = clean.date; point.checkInID = clean.id
                    point.title = point.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    point.impact = max(1, min(5, point.impact)); return point
                }
                data.batteryPoints.removeAll { $0.checkInID == clean.id }
                data.batteryPoints.append(contentsOf: valid)
                clean.energyPoints = valid
            }
        }
        data.guidedCheckIns.removeAll { $0.id == clean.id }
        data.guidedCheckIns.insert(clean, at: 0)
    }
}


struct CheckInReminder: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: GuidedCheckInKind = .morning
    var enabled = true
    var time = RoutineTime(hour: 7, minute: 0, weekendHour: 9, weekendMinute: 0)
    var pauseOnVacation = true
    var alarmEnabled: Bool?
    var slotID: UUID?
}
struct CheckInReminderSlot: Equatable, Identifiable {
    var reminderID: UUID
    var kind: GuidedCheckInKind
    var fireAt: Date
    var slotID: UUID?
    var title: String?
    var id: String { "therapy.checkin.\(reminderID).\(kind.rawValue).\(Int(fireAt.timeIntervalSince1970))" }
}
enum CheckInReminderPlanner {
    static func slots(data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [CheckInReminderSlot] {
        var output: [CheckInReminderSlot] = []
        let today = calendar.startOfDay(for: now)
        var seen = Set<String>()
        for reminder in data.companionSettings.checkInReminders ?? [] where reminder.enabled {
            let configured = DayCheckInPolicy.slot(kind: reminder.kind, id: reminder.slotID, settings: data.companionSettings)
            guard let configured, configured.enabled, seen.insert(configured.id.uuidString).inserted else { continue }
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let weekday = calendar.component(.weekday, from: day), clock = reminder.time.clock(weekday: weekday)
                guard reminder.time.weekdays.contains(weekday),
                      let date = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                      calendar.isDate(date, inSameDayAs: day), date > now, configured.contains(date, calendar: calendar) else { continue }
                if reminder.pauseOnVacation, let until = data.companionSettings.vacationUntil, date < until { continue }
                if data.guidedCheckIns.contains(where: { !$0.isDraft && ($0.daySlotID == configured.id || ($0.daySlotID == nil && $0.kind == reminder.kind && reminder.kind != .free)) && configured.anchor(for: $0.date, calendar: calendar) == configured.anchor(for: date, calendar: calendar) }) { continue }
                output.append(CheckInReminderSlot(reminderID: reminder.id, kind: reminder.kind, fireAt: date, slotID: configured.id, title: configured.title))
            }
        }
        return output.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
}
enum RoutineHistoryMutation {
    static func preserveTitles(in data: inout AppData, routine: DailyRoutine) {
        for index in data.routineCompletions.indices where data.routineCompletions[index].routineID == routine.id {
            if data.routineCompletions[index].routineTitle == nil { data.routineCompletions[index].routineTitle = routine.title }
            if data.routineCompletions[index].timeTitle == nil { data.routineCompletions[index].timeTitle = routine.times.first { $0.id == data.routineCompletions[index].timeID }?.title }
        }
    }
    @discardableResult
    static func correct(id: UUID, outcome: RoutineOutcome, note: String, reason: String, in data: inout AppData, now: Date = Date()) -> Bool {
        guard let index = data.routineCompletions.firstIndex(where: { $0.id == id }),
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let old = data.routineCompletions[index]
        guard old.outcome != outcome || old.note != note else { return false }
        let correction = RoutineCorrection(date: now, previousOutcome: old.outcome, previousNote: old.note, outcome: outcome, note: note, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
        data.routineCompletions[index].corrections = (old.corrections ?? []) + [correction]
        data.routineCompletions[index].outcome = outcome
        data.routineCompletions[index].note = note
        // Keep the original occurrence and confirmation timestamp; corrections never reopen reminders.
        return true
    }
    static func title(_ log: RoutineCompletion, data: AppData) -> String {
        log.routineTitle ?? data.routines.first { $0.id == log.routineID }?.title ?? "Gelöschte Routine"
    }
}
struct TherapyReportOptions {
    var start: Date
    var end: Date
    var includeCheckIns = true
    var includeMoodEntries = true
    var includeTasks = true
    var includeGoals = true
    var includeRoutines = false
    var includeNotes = false
    var includeNames = false
    var excludedCheckInIDs = Set<UUID>()
}
enum TherapyReport {
    static func checkIns(data: AppData, options: TherapyReportOptions) -> [GuidedCheckIn] {
        data.guidedCheckIns.filter { !$0.isDraft && $0.date >= options.start && $0.date < options.end && !options.excludedCheckInIDs.contains($0.id) }.sorted { $0.date < $1.date }
    }
    static func meanBattery(_ entries: [GuidedCheckIn]) -> Double? {
        let values = entries.compactMap(\.batteryPercent)
        return values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
    }
    static func text(data: AppData, options: TherapyReportOptions) -> String {
        func included(_ date: Date) -> Bool { date >= options.start && date < options.end }
        func stamp(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
        var lines = ["Meine Therapieübersicht", "Zeitraum: " + options.start.formatted(date: .abbreviated, time: .omitted) + " – " + options.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)]
        if options.includeNames {
            if !data.profile.userName.isEmpty { lines.append("Name: " + data.profile.userName) }
            if !data.profile.therapistName.isEmpty { lines.append("Therapie bei: " + data.profile.therapistName) }
        }
        if options.includeCheckIns {
            let entries = checkIns(data: data, options: options)
            lines.append("CHECK-INS · \(entries.count) abgeschlossen")
            if let mean = meanBattery(entries) { lines.append("Akku-Mittelwert: \(Int(mean.rounded())) % aus \(entries.compactMap(\.batteryPercent).count) Angaben. Übersprungene Antworten sind nicht eingerechnet.") }
            for entry in entries {
                lines.append("\(stamp(entry.date)) · \(entry.displayTitle)")
                if let value = entry.mood { lines.append("Stimmung: " + MoodCheckIn.moodTitles[max(0, min(4, value - 1))]) }
                if let value = entry.batteryPercent { lines.append("Akku: \(value) %") }
                if let value = entry.stress { lines.append("Stress: \(value)/5") }
                if let value = entry.sensoryLoad { lines.append("Reize: \(value)/5") }
                if let value = entry.sleepHours { lines.append("Schlaf: \(value.formatted()) Stunden") }
                for (label, value) in [("Rückblick", entry.summary), ("Energiegeber", entry.givesEnergy), ("Energienehmer", entry.takesEnergy), ("Erfolg", entry.smallWin), ("Bedürfnis", entry.nextNeed), ("Therapiefrage", entry.therapyQuestion)] where !value.isEmpty { lines.append(label + ": " + value) }
                if options.includeMoodEntries, let value = entry.moodPercent { lines.append("Stimmungsbarometer: \(value)/100") }
                for point in entry.energyPoints ?? [] { lines.append("\(point.direction.title): \(point.title) · \(point.impact)/5" + (point.note.isEmpty ? "" : " · " + point.note)) }
                if !entry.mediaIDs.isEmpty { lines.append("\(entry.mediaIDs.count) verknüpfte Fotos · Bilddateien separat teilen") }
                // Tasks are shared only through the separately selected task section.
            }
        }
        if options.includeMoodEntries {
            lines.append("STIMMUNGSEINTRÄGE")
            for entry in data.moodCheckIns.filter({ included($0.date) }).sorted(by: { $0.date < $1.date }) {
                lines.append("\(stamp(entry.date)) · \(entry.moodTitle) · Akku \(entry.battery)/5")
                if !entry.note.isEmpty { lines.append(entry.note) }
                if !entry.nextNeed.isEmpty { lines.append("Bedürfnis: " + entry.nextNeed) }
            }
        }
        if options.includeTasks {
            lines.append("AUFGABEN · aktueller Stand")
            let excludedTaskIDs = Set(data.guidedCheckIns.filter { options.excludedCheckInIDs.contains($0.id) }.flatMap { $0.taskIDs + $0.tasks.map(\.id) })
            for task in data.weeklyTasks.filter({ !excludedTaskIDs.contains($0.id) && (included($0.createdAt) || ($0.completedAt.map(included) ?? false) || ($0.dueDate.map(included) ?? false)) }).sorted(by: { $0.createdAt < $1.createdAt }) {
                lines.append("\(task.completed ? "Erledigt" : "Offen"): \(task.title)")
                if !task.details.isEmpty { lines.append(task.details) }
                if let value = task.smallStep, !value.isEmpty { lines.append("Kleiner Schritt: " + value) }
                if let value = task.dueDate { lines.append("Fällig: " + stamp(value)) }
            }
        }
        if options.includeGoals {
            lines.append("ZIELE · aktueller Stand")
            for goal in data.therapyGoals {
                lines.append("\(goal.title) · \(goal.status.rawValue) · \(goal.progress) %")
                if !goal.smallStep.isEmpty { lines.append("Kleiner Schritt: " + goal.smallStep) }
                if !goal.support.isEmpty { lines.append("Unterstützung: " + goal.support) }
            }
        }
        if options.includeRoutines {
            lines.append("ROUTINEN · protokollierte Angaben, keine Einnahmeprüfung")
            let logs = data.routineCompletions.filter { included($0.scheduledAt) }.sorted { $0.scheduledAt < $1.scheduledAt }
            lines.append("\(logs.filter { $0.outcome == .done }.count) erledigt · \(logs.filter { $0.outcome == .skipped }.count) ausgelassen. Fehlende Bestätigungen werden nicht als ausgelassen gewertet.")
            for log in logs {
                lines.append("\(stamp(log.scheduledAt)) · \(RoutineHistoryMutation.title(log, data: data))\(log.timeTitle.map { $0.isEmpty ? "" : " · " + $0 } ?? "") · \(log.outcome == .done ? "Erledigt" : "Ausgelassen")")
                if !log.note.isEmpty { lines.append(log.note) }
                for correction in log.corrections ?? [] { lines.append("Korrektur \(stamp(correction.date)): \(correction.previousOutcome.rawValue) → \(correction.outcome.rawValue) · \(correction.reason)") }
            }
        }
        if options.includeNotes {
            lines.append("NOTIZEN")
            for note in data.notes.filter({ included($0.createdAt) }).sorted(by: { $0.createdAt < $1.createdAt }) { lines.append(note.title + "\n" + note.text) }
        }
        lines.append("Selbstbericht. Nur die gewählten Bereiche sind enthalten; keine automatische Übermittlung.")
        return lines.joined(separator: "\n\n")
    }
}

/// Editors may outlive their row during deletion, animation or keyboard callbacks.
/// Read by identity and ignore writes for removed records instead of indexing stale positions.
enum IdentifiedDraftAccess {
    static func read<Value: Identifiable>(id: Value.ID, fallback: Value, from values: [Value]) -> Value {
        values.first { $0.id == id } ?? fallback
    }
    @discardableResult
    static func replace<Value: Identifiable>(_ value: Value, id: Value.ID, in values: inout [Value]) -> Bool {
        guard value.id == id, let index = values.firstIndex(where: { $0.id == id }) else { return false }
        values[index] = value
        return true
    }
}
