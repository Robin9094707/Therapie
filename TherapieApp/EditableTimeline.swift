import SwiftUI

private enum ArchiveRecord: Identifiable {
    case note(TherapyNote), media(MediaItem), energy(EnergyEntry), reflection(TherapySessionReflection)
    case mood(MoodCheckIn), point(BatteryPoint), review(WeekReview), session(RunningTherapySession)
    case task(WeeklyTask), topic(TherapyTopic), goal(TherapyGoal)
    case weeklyEnergy(WeeklyEnergyReview)
    case guided(GuidedCheckIn)
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
        case .guided(let value): value.date
        }
    }
    var title: String {
        switch self {
        case .note(let value): value.title
        case .media(let value): value.title
        case .energy(let value): "Energie-Check \(value.level)/5"
        case .reflection: "Therapie-Rückblick"
        case .mood(let value): "\(value.face) \(value.moodTitle) · Akku \(value.battery)/5"
        case .point(let value): value.title
        case .review(let value): "Wochenrückblick KW \(value.weekStart.therapyWeek.week)"
        case .session(let value): value.title
        case .task(let value): value.title
        case .topic(let value): value.title
        case .goal(let value): value.title
        case .weeklyEnergy(let value): "Wochenenergie · Akku \(value.energy)/5"
        case .guided(let value): value.displayTitle + (value.isDraft ? " · Entwurf" : "")
        }
    }
    var subtitle: String {
        switch self {
        case .note(let value): ([value.text, value.author ?? ""] + value.tags).joined(separator: " · ")
        case .media(let value): [value.kind.displayName, value.note, value.category ?? "", value.source ?? ""].joined(separator: " · ")
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
        case .guided(let value): [value.summary, value.smallWin, value.therapyQuestion].joined(separator: " · ")
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
        case .guided(let value): value.kind.symbol
        }
    }
    var isCheckIn: Bool { switch self { case .guided, .mood: true; default: false } }
    var deletionMessage: String {
        switch self {
        case .guided: "Der Check-in wird gelöscht. Angelegte Aufgaben und Fotos bleiben erhalten."
        case .mood: "Der Check-in und seine zugehörigen Akku-Punkte werden endgültig gelöscht."
        case .media: "Der Eintrag und seine lokale Datei werden endgültig gelöscht."
        case .topic: "Das Thema wird gelöscht. Verknüpfte Inhalte bleiben ohne Themenzuordnung erhalten."
        case .session: "Die Sitzung wird gelöscht. Ihre Notizen bleiben ohne Sitzungszuordnung erhalten."
        default: "Dieser Eintrag wird endgültig gelöscht."
        }
    }
}

struct TherapyEditableTimeline: View {
    @EnvironmentObject private var store: AppStore
    var searchText: String
    @State private var editing: ArchiveRecord?
    @State private var deleting: ArchiveRecord?
    @State private var confirmDelete = false
    private var records: [ArchiveRecord] {
        var values = store.data.notes.map(ArchiveRecord.note)
        values += store.data.media.map(ArchiveRecord.media)
        values += store.data.energyEntries.map(ArchiveRecord.energy)
        values += store.data.reflections.map(ArchiveRecord.reflection)
        values += store.data.moodCheckIns.map(ArchiveRecord.mood)
        values += store.data.batteryPoints.map(ArchiveRecord.point)
        values += store.data.weekReviews.map(ArchiveRecord.review)
        values += store.data.sessionHistory.map(ArchiveRecord.session)
        values += store.data.weeklyTasks.map(ArchiveRecord.task)
        values += store.data.therapyTopics.map(ArchiveRecord.topic)
        values += store.data.therapyGoals.map(ArchiveRecord.goal)
        values += store.data.weeklyEnergyReviews.map(ArchiveRecord.weeklyEnergy)
        values += store.data.guidedCheckIns.map(ArchiveRecord.guided)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.filter { query.isEmpty || ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(query) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        LazyVStack(spacing: 12) {
            if records.isEmpty { GlassCard { ContentUnavailableView("Deine Timeline ist noch leer", systemImage: "clock.arrow.circlepath", description: Text("Alle Einträge erscheinen hier. Öffne einen Eintrag, um ihn anzusehen. Check-ins zeigen zuerst ihre Übersicht.")) } }
            ForEach(records) { record in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: record.symbol).font(.title3).foregroundStyle(.indigo).frame(width: 30).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.title).font(.headline)
                                Text(record.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ResponsiveButtonRow {
                            Button(record.isCheckIn ? "Übersicht öffnen" : "Öffnen & bearbeiten", systemImage: record.isCheckIn ? "doc.text.magnifyingglass" : "pencil") { editing = record }
                            Button(role: .destructive) { deleting = record; confirmDelete = true } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Eintrag löschen")
                        }.font(.caption.bold())
                    }
                }
            }
        }
        .sheet(item: $editing) { editor($0) }
        .alert("Eintrag löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { if let deleting { remove(deleting) }; deleting = nil }
        } message: { Text(deleting?.deletionMessage ?? "") }
    }
    @ViewBuilder private func editor(_ record: ArchiveRecord) -> some View {
        switch record {
        case .note(let value): TherapyNoteEditorView(note: value)
        case .media(let value): TherapyMediaEditorView(item: value)
        case .energy(let value): LegacyEnergyEditorView(entry: value)
        case .reflection(let value): TherapyReflectionEditorView(entry: value)
        case .mood(let value): MoodCheckInDetailView(entryID: value.id)
        case .point(let value): BatteryPointEditorView(point: value) { store.saveBatteryPoint($0); return store.lastSaveError == nil }
        case .review(let value): WeekReviewEditorView(review: value)
        case .session(let value): SessionHistoryEditorView(session: value)
        case .task(let value): WeeklyTaskEditorView(task: value)
        case .topic(let value): TopicEditorView(topic: value)
        case .goal(let value): GoalEditorView(goal: value)
        case .weeklyEnergy(let value): WeeklyEnergyEditorView(review: value)
        case .guided(let value): GuidedCheckInDestination(entry: value)
        }
    }
    private func remove(_ record: ArchiveRecord) {
        var snapshot = store.data
        switch record {
        case .note(let value): snapshot.notes.removeAll { $0.id == value.id }
        case .media(let value): store.deleteMedia(value); return
        case .energy(let value): snapshot.energyEntries.removeAll { $0.id == value.id }
        case .reflection(let value): snapshot.reflections.removeAll { $0.id == value.id }
        case .mood(let value): store.deleteCheckIn(value); return
        case .point(let value): store.deleteBatteryPoint(value.id); return
        case .review(let value): snapshot.weekReviews.removeAll { $0.id == value.id }
        case .weeklyEnergy(let value): snapshot.weeklyEnergyReviews.removeAll { $0.id == value.id }
        case .guided(let value): store.deleteGuided(value.id); return
        case .session(let value):
            snapshot.sessionHistory.removeAll { $0.id == value.id }
            for i in snapshot.notes.indices where snapshot.notes[i].sessionID == value.id { snapshot.notes[i].sessionID = nil }
        case .task(let value): snapshot.weeklyTasks.removeAll { $0.id == value.id }
        case .topic(let value): TherapyHierarchy.removeTopic(value.id, data: &snapshot)
        case .goal(let value):
            snapshot.therapyGoals.removeAll { $0.id == value.id }
            for i in snapshot.weeklyTasks.indices where snapshot.weeklyTasks[i].goalID == value.id { snapshot.weeklyTasks[i].goalID = nil }
            for i in snapshot.routines.indices where snapshot.routines[i].goalID == value.id { snapshot.routines[i].goalID = nil }
        }
        store.data = snapshot
    }
}
