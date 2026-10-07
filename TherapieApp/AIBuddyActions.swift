import Foundation

enum AIBuddyMutation {
    static func apply(_ action: AIBuddyAction, originalID: String, messageID: UUID, to data: inout AppData, now: Date = Date()) throws {
        guard action.valid, let message = data.aiMessages.firstIndex(where: { $0.id == messageID }), !data.aiMessages[message].appliedActionIDs.contains(originalID) else { throw AIBuddyAPIError(message: "Diese Aktion ist ungültig oder bereits gespeichert.") }
        var snapshot = data
        let title = AIBuddyText.plain(action.title), text = AIBuddyText.plain(action.text)
        let date = action.date ?? now
        switch action.kind {
        case .shower, .skipRoutine, .postponeRoutine, .reopenTask, .postponeTask, .method, .thoughtStop, .updateMethod, .deleteMethod, .emergencyPlan, .updateNote, .deleteNote, .updateTopic, .deleteTopic, .updateGoal, .deleteGoal, .goalProgress, .discussTopic, .editEntry:
            try applyExtended(action, to: &snapshot, now: now)
        case .battery:
            guard let percent = action.moodPercent else { throw AIBuddyAPIError(message: "Bitte wähle deinen Akkuwert.") }
            snapshot.energyEntries.insert(EnergyEntry(createdAt: min(date, now), level: MoodBarometer.score(percent), percent: percent, givesEnergy: "", takesEnergy: "", note: text), at: 0)
        case .startSession:
            guard snapshot.currentSession == nil, let template = snapshot.sessionTemplates.first(where: { $0.id == action.targetID.flatMap(UUID.init(uuidString:)) && $0.isValid }) else { throw AIBuddyAPIError(message: "Eine Runde läuft bereits oder diese Vorlage ist nicht mehr verfügbar.") }
            snapshot.currentSession = RunningTherapySession.start(template, at: now)
        case .note:
            snapshot.notes.insert(TherapyNote(createdAt: min(date, now), title: title.isEmpty ? "Mein Therapietagebuch" : title, text: text, tags: BuddyInteraction.hashtags((action.tags ?? []) + ["Tagebuch"], text: title + " " + text, known: AppHashtags.catalog(snapshot)), sessionID: snapshot.currentSession?.id, category: "Therapietagebuch", conversationID: snapshot.aiMessages[message].conversationID, conversationTranscript: snapshot.aiMessages[message].conversationID.map { id in BuddyInteraction.transcript(snapshot.aiMessages.filter { $0.conversationID == id }) }), at: 0)
        case .mood:
            guard let percent = action.moodPercent else { throw AIBuddyAPIError(message: "Bitte wähle deine Stimmung selbst, bevor du speicherst.") }
            var entry = MoodCheckIn(date: min(date, now), mood: MoodBarometer.score(percent), note: text, moodPercent: percent)
            entry.daySlotID = MoodDailyPolicy.slot(for: entry, data: snapshot)?.id
            guard MoodDailyPolicy.existing(for: entry, in: snapshot) == nil else { throw AIBuddyAPIError(message: "In diesem Zeitfenster gibt es bereits einen Stimmungs-Check-in. Bearbeite ihn im Insights-Bereich oder erlaube zusätzliche Einträge im Check-in-Rhythmus.") }
            snapshot.moodCheckIns.insert(entry, at: 0)
        case .topic:
            snapshot.therapyTopics.insert(TherapyTopic(title: title, isCurrent: true, description: text), at: 0)
        case .task:
            let count = action.options?.repeatCount ?? 1
            if action.options?.repeatEveryWeeks != nil && action.date == nil { throw AIBuddyAPIError(message: "Für eine wiederkehrende Aufgabe fehlt der Startzeitpunkt.") }
            for index in 0..<count {
                let occurrence = Calendar.therapyCalendar.date(byAdding: .weekOfYear, value: index * (action.options?.repeatEveryWeeks ?? 1), to: date) ?? date
                let period = occurrence.therapyWeek
                let clock = Calendar.current.dateComponents([.hour, .minute], from: occurrence)
                let reminder = action.options?.remindersEnabled == false ? TaskReminder(enabled: false) : (action.date == nil ? nil : TaskReminder(enabled: true, weekdays: action.weekdays.isEmpty ? [Calendar.current.component(.weekday, from: occurrence)] : Array(Set(action.weekdays)).sorted(), hour: clock.hour ?? 18, minute: clock.minute ?? 0, alarmEnabled: action.options?.alarmEnabled ?? true))
                snapshot.weeklyTasks.insert(WeeklyTask(weekOfYear: period.week, yearForWeekOfYear: period.year, title: title, details: text, reminder: reminder, dueDate: action.date == nil ? nil : occurrence, smallStep: text), at: 0)
            }
        case .appointment:
            guard date > now else { throw AIBuddyAPIError(message: "Der Termin liegt in der Vergangenheit. Bitte prüfe Datum und Uhrzeit.") }
            var appointments = snapshot.schedule.extraAppointments ?? []
            guard !appointments.contains(where: { abs($0.date.timeIntervalSince(date)) < 1 }) else { throw AIBuddyAPIError(message: "Dieser Zusatztermin ist bereits vorhanden.") }
            appointments.append(TherapyExtraAppointment(date: date, title: title)); snapshot.schedule.extraAppointments = appointments
        case .routine:
            let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
            var routine = DailyRoutine(title: title, details: text, times: [RoutineTime(weekdays: action.weekdays.isEmpty ? Array(1...7) : Array(Set(action.weekdays)).sorted(), hour: clock.hour ?? 9, minute: clock.minute ?? 0)])
            if let times = action.options?.times { routine.times = times.sorted().map { RoutineTime(weekdays: action.weekdays.isEmpty ? Array(1...7) : Array(Set(action.weekdays)).sorted(), hour: $0 / 60, minute: $0 % 60) } }
            routine.urgentAlarm = action.options?.alarmEnabled ?? true
            routine.repeatUntilDone = action.options?.repeatUntilDone ?? false
            routine.escalationHour = nil
            configure(&routine, action: action, start: date)
            snapshot.routines.insert(routine, at: 0)
        case .goal:
            snapshot.therapyGoals.insert(TherapyGoal(title: title, why: text, smallStep: text, dueDate: action.date, priority: action.options?.priority), at: 0)
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
            guard let occurrence = RoutinePlanner.occurrences(data: snapshot, now: Calendar.current.startOfDay(for: now), days: 1).first(where: { $0.id == action.targetID }), RoutineDayMutation.resolve(occurrence, outcome: .done, note: text, in: &snapshot, at: now) else { throw AIBuddyAPIError(message: "Die Routine ist nicht mehr offen. Aktualisiere die Übersicht.") }
        case .guidedCheckIn: throw AIBuddyAPIError(message: "Der Check-in wird direkt geöffnet.")
        case .energy:
            snapshot.batteryPoints.insert(BatteryPoint(date: min(date, now), title: AIEnergyKeywords.title(title), direction: action.targetID == "takes" ? .takes : .gives, impact: action.options?.valueInt ?? 3, note: text, impactConfirmed: action.options?.valueInt != nil), at: 0)
        case .updateTask, .deleteTask:
            guard let id = action.targetID.flatMap(UUID.init(uuidString:)), let index = snapshot.weeklyTasks.firstIndex(where: { $0.id == id }) else { throw AIBuddyAPIError(message: "Diese Aufgabe ist nicht mehr vorhanden.") }
            if action.kind == .deleteTask { snapshot.weeklyTasks.remove(at: index) }
            else {
                snapshot.weeklyTasks[index].title = title; snapshot.weeklyTasks[index].details = text
                if let date = action.date { snapshot.weeklyTasks[index].dueDate = date }
                if action.date != nil || !action.weekdays.isEmpty || action.options?.remindersEnabled != nil || action.options?.alarmEnabled != nil {
                    var reminder = TaskReminderPlanner.settings(for: snapshot.weeklyTasks[index], schedule: snapshot.schedule)
                    if let date = action.date { let c = Calendar.current.dateComponents([.hour, .minute], from: date); reminder.hour = c.hour ?? reminder.hour; reminder.minute = c.minute ?? reminder.minute }
                    if !action.weekdays.isEmpty { reminder.weekdays = Array(Set(action.weekdays)).sorted() }
                    if let enabled = action.options?.remindersEnabled { reminder.enabled = enabled }
                    if let alarm = action.options?.alarmEnabled { reminder.alarmEnabled = alarm }
                    snapshot.weeklyTasks[index].reminder = reminder
                }
            }
        case .updateRoutine, .deleteRoutine:
            guard let id = action.targetID.flatMap(UUID.init(uuidString:)), let index = snapshot.routines.firstIndex(where: { $0.id == id }) else { throw AIBuddyAPIError(message: "Diese Routine ist nicht mehr vorhanden.") }
            let previous = snapshot.routines[index]
            if action.kind == .updateRoutine && previous.times.count > 1 && action.options?.times == nil && (action.date != nil || !action.weekdays.isEmpty) { throw AIBuddyAPIError(message: "Diese Routine hat mehrere Uhrzeiten. Bitte wähle den einzelnen Termin im Routine-Editor, damit die anderen unverändert bleiben.") }
            RoutineHistoryMutation.preserveTitles(in: &snapshot, routine: previous)
            if action.kind == .deleteRoutine {
                snapshot.routines.remove(at: index); snapshot.routineSnoozes.removeAll { $0.id.hasPrefix(id.uuidString + ".") }
            } else {
                snapshot.routines[index].title = title; snapshot.routines[index].details = text
                if let date = action.date {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    for t in snapshot.routines[index].times.indices { snapshot.routines[index].times[t].hour = c.hour ?? 9; snapshot.routines[index].times[t].minute = c.minute ?? 0 }
                }
                if !action.weekdays.isEmpty { for t in snapshot.routines[index].times.indices { snapshot.routines[index].times[t].weekdays = Array(Set(action.weekdays)).sorted() } }
                if let times = action.options?.times { snapshot.routines[index].times = times.sorted().map { minute in let existing = previous.times.first { $0.hour * 60 + $0.minute == minute }; return RoutineTime(id: existing?.id ?? UUID(), weekdays: action.weekdays.isEmpty ? existing?.weekdays ?? previous.times.first?.weekdays ?? Array(1...7) : Array(Set(action.weekdays)).sorted(), hour: minute / 60, minute: minute % 60) } }
                configure(&snapshot.routines[index], action: action, start: action.date ?? previous.recurrenceAnchor ?? now)
            }
        case .setting:
            let value = action.options?.valueBool ?? false
            switch action.targetID {
            case "showers.weeklyGoal": snapshot.showerPreferences.weeklyGoal = action.options?.valueInt ?? snapshot.showerPreferences.weeklyGoal
            case "dashboard.welcomeFirst": snapshot.dashboard.welcomeFirst = value
            case "dashboard.showFeatureLinks": snapshot.dashboard.showFeatureLinks = value
            case "dashboard.showAIImpulse": snapshot.dashboard.showAIImpulse = value
            case "appearance.accent": snapshot.accentTheme = action.options?.valueString.flatMap(AppAccent.init(rawValue:)) ?? snapshot.accentTheme
            case "ai.speakReplies": snapshot.aiSettings.speakReplies = value
            case "ai.contextDays": snapshot.aiSettings.contextDays = action.options?.valueInt ?? snapshot.aiSettings.contextDays
            case "ai.preferGuidedCheckIns": snapshot.aiSettings.preferGuidedCheckIns = value
            case "ai.automaticRange": snapshot.aiSettings.automaticRange = value
            case "ai.weeklyReview": snapshot.aiSettings.weeklyReviewEnabled = value
            case "dashboard.compactCards": snapshot.dashboard.compactCards = value
            case "dashboard.showWidgetTitles": snapshot.dashboard.showWidgetTitles = value
            case "reminders.privateTaskTitles": snapshot.reminderPreferences.privateTaskTitles = value
            case "companion.privateRoutineTitles": snapshot.companionSettings.privateRoutineTitles = value
            default: throw AIBuddyAPIError(message: "Diese Einstellung darf die KI nicht ändern.")
            }
        case .openScreen: throw AIBuddyAPIError(message: "Navigation wird direkt in der App ausgeführt.")
        }
        snapshot.hashtagCatalog = AppHashtags.catalog(snapshot)
        snapshot.aiMessages[message].appliedActionIDs.append(originalID)
        data = snapshot
    }
    static func configure(_ routine: inout DailyRoutine, action: AIBuddyAction, start: Date) {
        if let every = action.options?.repeatEveryDays { routine.repeatEveryDays = every; routine.repeatEveryWeeks = nil; routine.recurrenceAnchor = start; for index in routine.times.indices { routine.times[index].weekdays = Array(1...7) } }
        if action.options?.repeatEveryWeeks != nil { routine.repeatEveryDays = nil }
        if let enabled = action.options?.enabled { routine.enabled = enabled }
        if let enabled = action.options?.remindersEnabled { routine.remindersEnabled = enabled }
        if let alarm = action.options?.alarmEnabled { routine.urgentAlarm = alarm }
        if let untilDone = action.options?.repeatUntilDone { routine.repeatUntilDone = untilDone }
        if let retry = action.options?.retryMinutes { routine.retryMinutes = retry }
        if action.kind == .routine || action.options?.repeatEveryWeeks != nil || action.options?.repeatCount != nil {
            routine.recurrenceAnchor = start
            routine.repeatEveryWeeks = routine.repeatEveryDays == nil ? action.options?.repeatEveryWeeks ?? 1 : nil
            if let count = action.options?.repeatCount {
                let calendar = Calendar.current
                let week = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? calendar.startOfDay(for: start)
                routine.endsAt = calendar.date(byAdding: .weekOfYear, value: (count - 1) * (routine.repeatEveryWeeks ?? 1) + 1, to: week)?.addingTimeInterval(-1)
            }
        }
        if action.options?.once == false && action.kind == .updateRoutine { routine.endsAt = nil }
        if action.options?.once == true { routine.endsAt = start.addingTimeInterval(1); routine.recurrenceAnchor = start; routine.repeatEveryWeeks = 1; let clock = Calendar.current.dateComponents([.hour, .minute, .weekday], from: start); routine.times = [RoutineTime(weekdays: [clock.weekday ?? 1], hour: clock.hour ?? 9, minute: clock.minute ?? 0)] }
    }
    static func targetSnapshot(_ action: AIBuddyAction, in data: AppData) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let id = action.targetID.flatMap(UUID.init(uuidString:))
        switch action.kind {
        case .updateTask, .deleteTask, .completeTask, .reopenTask, .postponeTask: return data.weeklyTasks.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .updateRoutine, .deleteRoutine: return data.routines.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .updateMethod, .deleteMethod: return data.copingMethods.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .updateNote, .deleteNote: return data.notes.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .updateTopic, .deleteTopic: return data.therapyTopics.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .updateGoal, .deleteGoal, .goalProgress: return data.therapyGoals.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .emergencyPlan: return try? encoder.encode(data.emergencyPlan)
        case .shower, .skipRoutine, .postponeRoutine, .completeRoutine: return try? encoder.encode(data.routines) + encoder.encode(data.routineCompletions) + encoder.encode(data.routineDeferrals)
        case .discussTopic: return try? encoder.encode(data.therapyDiscussionAcknowledgedIDs)
        case .setting: return Data(AIBuddySettingsChange.value(action.targetID ?? "", data: data).utf8)
        default: return nil
        }
    }
}


extension AIBuddyMutation {
    static func applyExtended(_ action: AIBuddyAction, to data: inout AppData, now: Date) throws {
        let id = action.targetID.flatMap(UUID.init(uuidString:)), title = AIBuddyText.plain(action.title), text = AIBuddyText.plain(action.text)
        func missing() -> AIBuddyAPIError { AIBuddyAPIError(message: "Der Eintrag ist nicht mehr verfügbar oder bereits erledigt. Bitte den Vorschlag aktualisieren.") }
        switch action.kind {
        case .editEntry: throw AIBuddyAPIError(message: "Der native Editor wird direkt geöffnet.")
        case .shower:
            if let target = action.targetID {
                guard let occurrence = ShowerPlanner.today(data, at: now).first(where: { $0.id == target }), RoutineDayMutation.resolve(occurrence, outcome: .done, note: text, in: &data, at: now) else { throw missing() }
            } else {
                guard let date = action.date, date <= now else { throw AIBuddyAPIError(message: "Ein Duschtag kann erst nach dem Duschen bestätigt werden. Bitte Datum prüfen.") }
                data.showerEntries.insert(ShowerEntry(date: date, note: text), at: 0)
            }
        case .skipRoutine, .postponeRoutine:
            guard let occurrence = RoutinePlanner.occurrences(data: data, now: Calendar.current.startOfDay(for: now), days: 1).first(where: { $0.id == action.targetID }) else { throw missing() }
            if action.kind == .skipRoutine {
                guard RoutineDayMutation.resolve(occurrence, outcome: .skipped, note: text, in: &data, at: now) else { throw missing() }
            } else {
                guard let date = action.date, RoutineDayMutation.postpone(occurrence, until: date, in: &data, at: now) else { throw AIBuddyAPIError(message: "Der neue Zeitpunkt muss später liegen und der Termin noch offen sein.") }
            }
        case .reopenTask, .postponeTask:
            guard let index = data.weeklyTasks.firstIndex(where: { $0.id == id }) else { throw missing() }
            if action.kind == .reopenTask {
                guard data.weeklyTasks[index].completed else { throw missing() }
                data.weeklyTasks[index].toggleCompletion(at: now)
                data.weeklyTasks[index].reminderShiftedAt = nil
            } else {
                guard let date = action.date, date > now, !data.weeklyTasks[index].completed else { throw missing() }
                TaskReminderPlanner.postpone(&data.weeklyTasks[index], schedule: data.schedule, minutes: max(1, Int(ceil(date.timeIntervalSince(now) / 60))), now: now)
                data.weeklyTasks[index].dueDate = date; data.weeklyTasks[index].reminderShiftedAt = date
            }
        case .method, .thoughtStop:
            var method = CopingMethod(createdAt: now, updatedAt: now, title: title, kind: action.kind == .thoughtStop ? .thoughtStop : .method, details: text)
            configureMethod(&method, action: action); data.copingMethods.insert(method, at: 0)
        case .updateMethod, .deleteMethod:
            guard let index = data.copingMethods.firstIndex(where: { $0.id == id }) else { throw missing() }
            if action.kind == .deleteMethod { data.copingMethods.remove(at: index); data.emergencyPlan.methodIDs.removeAll { $0 == id } }
            else { data.copingMethods[index].title = title; data.copingMethods[index].details = text; data.copingMethods[index].updatedAt = now; configureMethod(&data.copingMethods[index], action: action) }
        case .emergencyPlan:
            switch action.targetID ?? "firstStep" {
            case "firstStep": data.emergencyPlan.firstStep = text
            case "warningSigns": data.emergencyPlan.warningSigns = text
            case "support": data.emergencyPlan.support = text
            case "steps": data.emergencyPlan.steps = action.options?.steps ?? text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            case "title": data.emergencyPlan.title = text
            default: throw missing()
            }
            data.emergencyPlan.updatedAt = now
        case .updateNote, .deleteNote:
            guard let index = data.notes.firstIndex(where: { $0.id == id }) else { throw missing() }
            if action.kind == .deleteNote { data.notes.remove(at: index) }
            else { data.notes[index].title = title; data.notes[index].text = text; data.notes[index].updatedAt = now }
        case .updateTopic, .deleteTopic:
            guard let index = data.therapyTopics.firstIndex(where: { $0.id == id }) else { throw missing() }
            if action.kind == .deleteTopic { data.therapyTopics.remove(at: index) }
            else { data.therapyTopics[index].title = title; data.therapyTopics[index].description = text }
        case .updateGoal, .deleteGoal, .goalProgress:
            guard let index = data.therapyGoals.firstIndex(where: { $0.id == id }) else { throw missing() }
            if action.kind == .deleteGoal { data.therapyGoals.remove(at: index) }
            else if action.kind == .goalProgress {
                guard let percent = action.options?.valueInt else { throw missing() }
                data.therapyGoals[index].progress = percent; data.therapyGoals[index].status = percent == 100 ? .completed : .active
            } else { data.therapyGoals[index].title = title; data.therapyGoals[index].why = text; if let date = action.date { data.therapyGoals[index].dueDate = date }; if let priority = action.options?.priority { data.therapyGoals[index].priority = priority } }
        case .discussTopic:
            guard let target = action.targetID, TherapyDiscussionPlanner.points(in: data).contains(where: { $0.id == target }) else { throw missing() }
            data.therapyDiscussionAcknowledgedIDs.append(target)
        default: throw AIBuddyAPIError(message: "Diese Aktion ist nicht bekannt.")
        }
    }
    static func configureMethod(_ method: inout CopingMethod, action: AIBuddyAction) {
        if let situation = action.options?.situation { method.situation = situation }
        if let steps = action.options?.steps { method.steps = steps }
        if let stages = action.options?.stages { method.stages = Array(Set(stages.compactMap(MethodStage.init(rawValue:)))).sorted { $0.rawValue < $1.rawValue } }
        if let categories = action.options?.categories { method.categories = Array(Set(categories.compactMap(BatteryCategory.init(rawValue:)))).sorted { $0.rawValue < $1.rawValue } }
    }
}
