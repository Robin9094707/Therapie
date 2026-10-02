import Foundation

enum ArchiveRecord: Identifiable {
    case note(TherapyNote), media(MediaItem), energy(EnergyEntry), reflection(TherapySessionReflection)
    case mood(MoodCheckIn), point(BatteryPoint), review(WeekReview), session(RunningTherapySession)
    case task(WeeklyTask), topic(TherapyTopic), goal(TherapyGoal)
    case weeklyEnergy(WeeklyEnergyReview)
    case guided(GuidedCheckIn), routineLog(RoutineCompletion)
    var id: String {
        switch self {
        case .note(let value): "note-\(value.id)"
        case .media(let value): "media-\(value.id)"
        case .energy(let value): "energy-\(value.id)"
        case .reflection(let value): "reflection-\(value.id)"
        case .mood(let value): "mood-\(value.id)"
        case .point(let value): "point-\(value.id)"
        case .review(let value): "review-\(value.id)"
        case .session(let value): "session-\(value.id)"
        case .task(let value): "task-\(value.id)"
        case .topic(let value): "topic-\(value.id)"
        case .goal(let value): "goal-\(value.id)"
        case .weeklyEnergy(let value): "weekly-energy-\(value.id)"
        case .routineLog(let value): "routine-log-\(value.id)"
        case .guided(let value): "guided-\(value.id)"
        }
    }
    var date: Date {
        switch self {
        case .note(let value): value.createdAt
        case .media(let value): value.createdAt
        case .energy(let value): value.createdAt
        case .reflection(let value): value.date
        case .mood(let value): value.date
        case .point(let value): value.date
        case .review(let value): value.weekStart
        case .session(let value): value.startedAt
        case .task(let value): value.createdAt
        case .topic(let value): value.createdAt
        case .goal(let value): value.createdAt
        case .weeklyEnergy(let value): value.periodEnd
        case .routineLog(let value): value.scheduledAt
        case .guided(let value): value.date
        }
    }
    var title: String {
        switch self {
        case .note(let value): value.title
        case .media(let value): value.title
        case .energy(let value): value.percent.map { "Akku \($0) %" } ?? "Energie-Check \(value.level)/5"
        case .reflection: "Therapie-Rückblick"
        case .mood(let value): "\(value.face) \(value.moodTitle) · Akku \(value.battery)/5"
        case .point(let value): value.title
        case .review(let value): "Wochenrückblick KW \(value.weekStart.therapyWeek.week)"
        case .session(let value): value.title
        case .task(let value): value.title
        case .topic(let value): value.title
        case .goal(let value): value.title
        case .weeklyEnergy(let value): "Wochenenergie · Akku \(value.energy)/5"
        case .routineLog(let value): value.routineTitle ?? "Routinenprotokoll"
        case .guided(let value): value.displayTitle + (value.isDraft ? " · Entwurf" : "")
        }
    }
    var subtitle: String {
        switch self {
        case .note(let value): ([value.text, value.author ?? ""] + value.tags).joined(separator: " · ")
        case .media(let value): [value.kind.displayName, value.note, value.category ?? "", value.source ?? "", value.tags.joined(separator: " ")].joined(separator: " · ")
        case .energy(let value): [value.givesEnergy, value.takesEnergy, value.note].joined(separator: " · ")
        case .reflection(let value): [value.summary, value.whatHelped, value.nextFocus].joined(separator: " · ")
        case .mood(let value): ([value.note, value.smallWin, value.nextNeed] + value.emotions).joined(separator: " · ")
        case .point(let value): [value.direction.title, value.category.title, value.note].joined(separator: " · ")
        case .review(let value): [value.summary, value.therapyQuestion, value.nextStep].joined(separator: " · ")
        case .session(let value): [value.summary, value.nextStep].joined(separator: " · ")
        case .task(let value): (value.completed ? "Erledigt · " : "Offen · ") + value.details
        case .topic(let value): [value.status.rawValue, value.description, value.category.rawValue].joined(separator: " · ")
        case .goal(let value): [value.status.rawValue, value.smallStep, value.measure].joined(separator: " · ")
        case .weeklyEnergy(let value): (value.gives.map(\.title) + value.takes.map(\.title) + [value.note, value.therapyQuestion]).joined(separator: " · ")
        case .routineLog(let value): (value.outcome == .done ? "Erledigt" : "Ausgelassen") + " · " + (value.timeTitle ?? "") + " · " + value.note
        case .guided(let value): ([value.summary, value.smallWin, value.therapyQuestion] + (value.tags ?? [])).joined(separator: " · ")
        }
    }
    var symbol: String {
        switch self {
        case .note(let value): value.isImportant == true ? "pin.fill" : "note.text"
        case .media(let value): value.kind.symbol
        case .energy: "bolt.heart"
        case .reflection: "clock.arrow.circlepath"
        case .mood: "face.smiling"
        case .point(let value): value.direction.symbol
        case .review: "calendar.badge.checkmark"
        case .session: "timer"
        case .task: "checklist"
        case .topic(let value): value.category.symbol
        case .goal: "scope"
        case .weeklyEnergy: "battery.100percent"
        case .routineLog: "checkmark.circle"
        case .guided(let value): value.kind.symbol
        }
    }
    var isCheckIn: Bool { switch self { case .guided, .mood, .note, .media: true; default: false } }
    var deletionMessage: String {
        switch self {
        case .guided: "Der Check-in wird gelöscht. Angelegte Aufgaben und Fotos bleiben erhalten."
        case .mood: "Der Check-in und seine zugehörigen Akku-Punkte werden gelöscht. In der geöffneten App kannst du das zehn Sekunden lang rückgängig machen."
        case .media: "Der Eintrag und seine lokale Datei werden gelöscht. In der geöffneten App kannst du das zehn Sekunden lang rückgängig machen."
        case .topic: "Das Thema wird gelöscht. Verknüpfte Inhalte bleiben ohne Themenzuordnung erhalten."
        case .session: "Die Sitzung wird gelöscht. Ihre Notizen bleiben ohne Sitzungszuordnung erhalten."
        default: "Dieser Eintrag wird gelöscht. In der geöffneten App kannst du das zehn Sekunden lang rückgängig machen."
        }
    }
}


extension ArchiveRecord {
    var kind: ArchiveKind {
        switch self {
        case .note: .notes
        case .media(let item): item.kind == .photo ? .photos : item.kind == .audio ? .audio : .documents
        case .guided, .mood: .checkIns
        case .routineLog: .routines
        case .energy, .point, .weeklyEnergy: .energy
        case .task: .tasks
        case .topic, .goal: .topics
        case .session, .reflection, .review: .therapy
        }
    }
    var topicID: UUID? {
        switch self { case .note(let v): v.topicID; case .media(let v): v.topicID; case .task(let v): v.topicID; case .goal(let v): v.topicID; case .topic(let v): v.id; default: nil }
    }
    var folderID: UUID? {
        switch self { case .note(let v): v.folderID; case .media(let v): v.folderID; case .topic(let v): v.folderID; default: nil }
    }
    var canDelete: Bool { if case .routineLog = self { return false }; return true }
    static func all(in data: AppData) -> [ArchiveRecord] {
        var values = data.notes.map(ArchiveRecord.note)
        values += data.media.map(ArchiveRecord.media)
        values += data.energyEntries.map(ArchiveRecord.energy)
        values += data.reflections.map(ArchiveRecord.reflection)
        values += data.moodCheckIns.map(ArchiveRecord.mood)
        values += data.batteryPoints.map(ArchiveRecord.point)
        values += data.weekReviews.map(ArchiveRecord.review)
        values += data.sessionHistory.map(ArchiveRecord.session)
        values += data.weeklyTasks.map(ArchiveRecord.task)
        values += data.therapyTopics.map(ArchiveRecord.topic)
        values += data.therapyGoals.map(ArchiveRecord.goal)
        values += data.weeklyEnergyReviews.map(ArchiveRecord.weeklyEnergy)
        values += data.guidedCheckIns.map(ArchiveRecord.guided)
        values += data.routineCompletions.map(ArchiveRecord.routineLog)
        return values
    }
}
enum ArchiveKind: String, CaseIterable, Identifiable {
    case all = "Alles", notes = "Notizen", photos = "Fotos", audio = "Audio", documents = "Dokumente", checkIns = "Check-ins", routines = "Routinen", energy = "Energie", tasks = "Aufgaben", topics = "Themen & Ziele", therapy = "Therapie & Rückblicke"
    var id: String { rawValue }
}
