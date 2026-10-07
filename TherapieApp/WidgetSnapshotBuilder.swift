import Foundation

enum TherapyWidgetSnapshotBuilder {
    static func make(data: AppData, now: Date = Date(), calendar: Calendar = .current) -> TherapyWidgetSnapshot {
        var result = TherapyWidgetSnapshot(generatedAt: now, configured: data.profile.onboardingCompleted)
        result.accentName = data.accentTheme.rawValue
        result.showsPersonalTitles = data.dashboard.showWidgetTitles
        let privateTitles = !data.dashboard.showWidgetTitles
        var cursor = now
        for _ in 0..<8 {
            guard let date = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: cursor, calendar: calendar) else { break }
            result.nextAppointments.append(date); cursor = date.addingTimeInterval(1)
        }
        for occurrence in RoutinePlanner.occurrences(data.routines, settings: data.companionSettings, now: now, days: 7, calendar: calendar) {
            guard !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions),
                  let routine = data.routines.first(where: { $0.id == occurrence.routineID }),
                  RoutinePlanner.active(routine, settings: data.companionSettings, at: now) else { continue }
            result.reminders.append(TherapyWidgetReminder(id: occurrence.id, kind: "routine", title: privateTitles ? "Deine Routine" : routine.title, due: occurrence.due, expiresAt: occurrence.end, route: "therapie://routine/" + routine.id.uuidString))
        }
        for task in data.weeklyTasks where !task.completed {
            let slots = TaskReminderPlanner.slots(tasks: [task], schedule: data.schedule, now: now)
            let taskWeek = Calendar.therapyCalendar.date(from: DateComponents(weekOfYear: task.weekOfYear, yearForWeekOfYear: task.yearForWeekOfYear))
            guard taskWeek.map({ $0 <= now }) ?? false else { continue }
            var candidates: [Date] = []
            for slot in slots {
                var parts = DateComponents(); parts.hour = slot.hour; parts.minute = slot.minute; parts.second = 0; parts.weekday = slot.weekday
                if let date = calendar.nextDate(after: now.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first) { candidates.append(date) }
            }
            let due = task.dueDate ?? candidates.min() ?? now
            result.reminders.append(TherapyWidgetReminder(id: task.id.uuidString, kind: "task", title: privateTitles ? "Offene Aufgabe" : task.title, due: due, expiresAt: now.addingTimeInterval(8 * 86400), route: "therapie://task/" + task.id.uuidString))
        }
        if let session = data.currentSession, session.endedAt == nil {
            var cursor = session.clockStart
            var phases: [TherapyWidgetPhase] = []
            for phase in session.phases {
                let end = cursor.addingTimeInterval(TimeInterval(max(1, phase.minutes) * 60))
                phases.append(TherapyWidgetPhase(title: privateTitles ? "Therapieabschnitt" : phase.title, start: cursor, end: end)); cursor = end
            }
            if session.pausedAt != nil || session.expectedEnd > now {
                result.session = TherapyWidgetSession(title: privateTitles ? "Therapiezeit" : session.title, end: session.expectedEnd, paused: session.pausedAt != nil, pausedRemaining: session.remaining(at: now), phases: phases)
            }
        }
        return result
    }
}
