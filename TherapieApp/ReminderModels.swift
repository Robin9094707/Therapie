import Foundation

struct TaskReminder: Codable, Equatable {
    var enabled = true
    var weekdays = Array(1...7)
    var hour = 18
    var minute = 0
}

struct ReminderPreferences: Codable, Equatable {
    var privateTaskTitles = true
    var taskSound = true
    var energyReviewEnabled = false
    var energyReviewMinutesBeforeTherapy = 30
}

struct TaskReminderSlot: Equatable {
    var taskID: UUID
    var weekday: Int? // nil means daily, requiring just one recurring request.
    var hour: Int
    var minute: Int
    var identifier: String { "therapy.task.\(taskID).\(weekday.map(String.init) ?? "daily")" }
}

enum TaskReminderPlanner {
    static let requestBudget = 40 // Leave room for the session and weekly notifications.
    static func settings(for task: WeeklyTask, schedule: TherapySchedule) -> TaskReminder {
        task.reminder ?? TaskReminder(enabled: schedule.taskReminderEnabled, weekdays: schedule.taskReminderWeekdays,
                                      hour: schedule.taskReminderHour, minute: schedule.taskReminderMinute)
    }
    static func slots(tasks: [WeeklyTask], schedule: TherapySchedule, now: Date = Date()) -> [TaskReminderSlot] {
        var result: [TaskReminderSlot] = []
        let ordered = tasks.sorted {
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for task in ordered where !task.completed {
            let start = Calendar.therapyCalendar.date(from: DateComponents(weekOfYear: task.weekOfYear, yearForWeekOfYear: task.yearForWeekOfYear))
            guard start.map({ $0 <= now }) ?? false else { continue }
            let settings = settings(for: task, schedule: schedule)
            let days = Set(settings.weekdays.filter { (1...7).contains($0) }).sorted()
            guard settings.enabled, !days.isEmpty else { continue }
            let slotDays: [Int?] = days.count == 7 ? [nil] : days.map { Optional($0) }
            for day in slotDays {
                result.append(TaskReminderSlot(taskID: task.id, weekday: day, hour: max(0, min(23, settings.hour)), minute: max(0, min(59, settings.minute))))
            }
        }
        return result
    }
    static func postpone(_ task: inout WeeklyTask, schedule: TherapySchedule, minutes: Int, now: Date = Date()) {
        guard !task.completed else { return }
        let shifted = minutes == 1440 ? (Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)) : now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let components = Calendar.current.dateComponents([.hour, .minute, .weekday], from: shifted)
        var reminder = settings(for: task, schedule: schedule)
        reminder.enabled = true
        reminder.hour = components.hour ?? 18; reminder.minute = components.minute ?? 0
        reminder.weekdays = Set(reminder.weekdays + [components.weekday ?? 1]).filter { (1...7).contains($0) }.sorted()
        task.reminder = reminder
        task.reminderShiftedAt = shifted
    }
    static func admittedSlots(_ all: [TaskReminderSlot]) -> [TaskReminderSlot] {
        var result: [TaskReminderSlot] = [], considered = Set<UUID>()
        for slot in all where considered.insert(slot.taskID).inserted {
            let group = all.filter { $0.taskID == slot.taskID }
            if result.count + group.count <= requestBudget { result += group }
        }
        return result
    }
}

struct WeeklyEnergyReview: Codable, Equatable, Identifiable {
    var id = UUID()
    var periodEnd = Date()
    var createdAt = Date()
    var energy = 3
    var gives: [WeeklyEnergyFactor] = []
    var takes: [WeeklyEnergyFactor] = []
    var note = ""
    var nextStep = ""
    var therapyQuestion = ""
    var periodStart: Date { Calendar.therapyCalendar.date(byAdding: .day, value: -7, to: Calendar.therapyCalendar.startOfDay(for: periodEnd))! }
}

struct WeeklyEnergyFactor: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var impact = 3
    var category: BatteryCategory = .other
    var note = ""
}

enum TherapyReviewPeriod {
    static func latestTherapyDay(schedule: TherapySchedule, now: Date = Date()) -> Date {
        let calendar = Calendar.therapyCalendar
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        return calendar.date(byAdding: .day, value: -((weekday - schedule.weekday + 7) % 7), to: today) ?? today
    }
}
