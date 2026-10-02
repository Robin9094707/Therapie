import Foundation

enum AIBuddyMutation {
    static func apply(_ action: AIBuddyAction, originalID: String, messageID: UUID, to data: inout AppData, now: Date = Date()) throws {
        guard action.valid, let message = data.aiMessages.firstIndex(where: { $0.id == messageID }), !data.aiMessages[message].appliedActionIDs.contains(originalID) else { throw AIBuddyAPIError(message: "Diese Aktion ist ungültig oder bereits gespeichert.") }
        var snapshot = data
        let title = AIBuddyText.plain(action.title), text = AIBuddyText.plain(action.text)
        let date = action.date ?? now
        switch action.kind {
        case .note:
            snapshot.notes.insert(TherapyNote(createdAt: min(date, now), title: title.isEmpty ? "Mein Therapietagebuch" : title, text: text, tags: AppHashtags.clean(["Tagebuch", "KI-Begleiter"] + (action.tags ?? []), known: AppHashtags.catalog(snapshot)), sessionID: snapshot.currentSession?.id, category: "Therapietagebuch"), at: 0)
        case .mood:
            guard let percent = action.moodPercent else { throw AIBuddyAPIError(message: "Bitte wähle deine Stimmung selbst, bevor du speicherst.") }
            var entry = MoodCheckIn(date: min(date, now), mood: MoodBarometer.score(percent), note: text, moodPercent: percent)
            entry.daySlotID = MoodDailyPolicy.slot(for: entry, data: snapshot)?.id
            guard MoodDailyPolicy.existing(for: entry, in: snapshot) == nil else { throw AIBuddyAPIError(message: "In diesem Zeitfenster gibt es bereits einen Stimmungs-Check-in. Bearbeite ihn im Insights-Bereich oder erlaube zusätzliche Einträge im Check-in-Rhythmus.") }
            snapshot.moodCheckIns.insert(entry, at: 0)
        case .topic:
            snapshot.therapyTopics.insert(TherapyTopic(title: title, isCurrent: true, description: text), at: 0)
        case .task:
            let week = date.therapyWeek
            snapshot.weeklyTasks.insert(WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: title, details: text, dueDate: action.date, smallStep: text), at: 0)
        case .appointment:
            guard date > now else { throw AIBuddyAPIError(message: "Der Termin liegt in der Vergangenheit. Bitte prüfe Datum und Uhrzeit.") }
            var appointments = snapshot.schedule.extraAppointments ?? []
            guard !appointments.contains(where: { abs($0.date.timeIntervalSince(date)) < 1 }) else { throw AIBuddyAPIError(message: "Dieser Zusatztermin ist bereits vorhanden.") }
            appointments.append(TherapyExtraAppointment(date: date, title: title)); snapshot.schedule.extraAppointments = appointments
        case .routine:
            let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
            snapshot.routines.insert(DailyRoutine(title: title, details: text, times: [RoutineTime(weekdays: action.weekdays.isEmpty ? Array(1...7) : Array(Set(action.weekdays)).sorted(), hour: clock.hour ?? 9, minute: clock.minute ?? 0)]), at: 0)
        case .goal:
            snapshot.therapyGoals.insert(TherapyGoal(title: title, why: text, smallStep: text, dueDate: action.date), at: 0)
        case .checkIn:
            var entry = GuidedCheckIn(date: min(date, now), summary: text, tags: AppHashtags.clean(action.tags ?? [], known: AppHashtags.catalog(snapshot)), customTitle: title.isEmpty ? nil : title)
            entry.moodPercent = action.moodPercent; entry.mood = action.moodPercent.map(MoodBarometer.score)
            guard GuidedCheckInMutation.apply(entry, complete: false, to: &snapshot) else { throw AIBuddyAPIError(message: "Heute gibt es schon einen freien Check-in. Öffne ihn im Check-in-Bereich zum Bearbeiten.") }
        case .reflection:
            snapshot.reflections.insert(TherapySessionReflection(date: min(date, now), summary: text, whatHelped: "", nextFocus: title), at: 0)
        case .completeTask:
            guard let id = action.targetID.flatMap({ UUID(uuidString: $0.hasPrefix("task-") ? String($0.dropFirst(5)) : $0) }), let index = snapshot.weeklyTasks.firstIndex(where: { $0.id == id && !$0.completed }) else { throw AIBuddyAPIError(message: "Die Aufgabe ist nicht mehr offen. Aktualisiere die Übersicht.") }
            snapshot.weeklyTasks[index].toggleCompletion(at: now); snapshot.weeklyTasks[index].reminderShiftedAt = nil
        case .completeRoutine:
            guard let occurrence = RoutinePlanner.due(data: snapshot, now: now).first(where: { $0.id == action.targetID }), let routine = snapshot.routines.first(where: { $0.id == occurrence.routineID }) else { throw AIBuddyAPIError(message: "Die Routine ist nicht mehr fällig. Aktualisiere die Übersicht.") }
            snapshot.routineCompletions.insert(RoutineCompletion(routineID: routine.id, timeID: occurrence.timeID, scheduledAt: occurrence.due, recordedAt: now, note: text, routineTitle: routine.title, timeTitle: routine.times.first { $0.id == occurrence.timeID }?.title), at: 0)
            snapshot.routineSnoozes.removeAll { $0.id == occurrence.id }
        case .openScreen: throw AIBuddyAPIError(message: "Navigation wird direkt in der App ausgeführt.")
        }
        snapshot.hashtagCatalog = AppHashtags.catalog(snapshot)
        snapshot.aiMessages[message].appliedActionIDs.append(originalID)
        data = snapshot
    }
}
