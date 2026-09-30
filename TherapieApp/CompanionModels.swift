import Foundation

enum GuidedCheckInKind: String, Codable, CaseIterable, Identifiable {
    case morning, evening, therapy, free
    var id: String { rawValue }
    var title: String {
        switch self { case .morning: "Morgen-Check-in"; case .evening: "Abend-Check-in"; case .therapy: "Therapie-Check-in"; case .free: "Freier Check-in" }
    }
    var symbol: String {
        switch self { case .morning: "sun.max.fill"; case .evening: "moon.stars.fill"; case .therapy: "leaf.fill"; case .free: "sparkles" }
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
enum RoutineOutcome: String, Codable { case done, skipped }
struct RoutineCompletion: Codable, Equatable, Identifiable {
    var id = UUID()
    var routineID: UUID
    var timeID: UUID
    var scheduledAt: Date
    var recordedAt = Date()
    var outcome: RoutineOutcome = .done
    var note = ""
}
struct RoutineSnooze: Codable, Equatable, Identifiable {
    var id: String
    var until: Date
}
struct CompanionSettings: Codable, Equatable {
    var vacationUntil: Date?
    var privateRoutineTitles = true
    var offerTherapyCheckIn = true
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
                    output.append(RoutineOccurrence(routineID: routine.id, timeID: time.id, due: due, end: end))
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
        }
        data.guidedCheckIns.removeAll { $0.id == clean.id }
        data.guidedCheckIns.insert(clean, at: 0)
    }
}
