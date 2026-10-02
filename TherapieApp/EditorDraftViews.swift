import SwiftUI

extension AppStore {
    func saveEditorDraft<T: Encodable>(_ value: T, id: UUID, kind: String, title: String) {
        do {
            let draft = try AppEditorDraft.make(value, id: id, kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unbenannter Entwurf" : title)
            var snapshot = data; snapshot.editorDrafts.removeAll { $0.id == id }; snapshot.editorDrafts.insert(draft, at: 0); data = snapshot
        } catch { lastSaveError = error.localizedDescription }
    }
    func removeEditorDraft(_ id: UUID) {
        guard data.editorDrafts.contains(where: { $0.id == id }) else { return }
        data.editorDrafts.removeAll { $0.id == id }
    }
}
struct EditorDraftListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var opening: AppEditorDraft?
    @State private var deleting: AppEditorDraft?
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Nur ausdrücklich gespeicherte Eingaben. Entwürfe bleiben getrennt von fertigen Einträgen und sind in deinen Backups enthalten.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.data.editorDrafts.sorted { $0.updatedAt > $1.updatedAt }) { draft in
                    GlassCard { HStack { Button { opening = draft } label: { VStack(alignment: .leading, spacing: 6) { Text(draft.title).font(.headline); Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain); Button("Entwurf löschen", systemImage: "trash", role: .destructive) { deleting = draft }.labelStyle(.iconOnly).buttonStyle(.borderless) } }
                }
                if store.data.editorDrafts.isEmpty { ContentUnavailableView("Keine offenen Entwürfe", systemImage: "square.and.pencil") }
            }
        }.navigationTitle("Meine Entwürfe")
            .sheet(item: $opening) { EditorDraftDestination(draft: $0) }
            .alert("Entwurf löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Abbrechen", role: .cancel) {}; Button("Löschen", role: .destructive) { if let deleting { store.removeEditorDraft(deleting.id) }; deleting = nil } }
    }
}
private struct EditorDraftDestination: View {
    @EnvironmentObject private var store: AppStore
    let draft: AppEditorDraft
    var body: some View {
        Group {
            switch draft.kind {
            case "note": if let value = draft.decode(TherapyNote.self) { TherapyNoteEditorView(note: value) }
            case "task": if let value = draft.decode(WeeklyTask.self) { WeeklyTaskEditorView(task: value) }
            case "routine": if let value = draft.decode(DailyRoutine.self) { RoutineEditorView(routine: value) }
            case "topic": if let value = draft.decode(TherapyTopic.self) { TopicEditorView(topic: value) }
            case "goal": if let value = draft.decode(TherapyGoal.self) { GoalEditorView(goal: value) }
            case "folder": if let value = draft.decode(TherapyFolder.self) { FolderEditorView(folder: value) }
            case "media": if let value = draft.decode(MediaItem.self) { TherapyMediaEditorView(item: value) }
            case "energy": if let value = draft.decode(EnergyEntry.self) { LegacyEnergyEditorView(entry: value) }
            case "reflection": if let value = draft.decode(TherapySessionReflection.self) { TherapyReflectionEditorView(entry: value) }
            case "mood": if let value = draft.decode(MoodEntryDraft.self) { MoodEditorView(entry: value.entry, points: value.points) }
            case "battery": if let value = draft.decode(BatteryPoint.self) { BatteryPointEditorView(point: value) { store.saveBatteryPoint($0); return store.lastSaveError == nil } }
            case "weekReview": if let value = draft.decode(WeekReview.self) { WeekReviewEditorView(review: value) }
            case "sessionTemplate": if let value = draft.decode(TherapySessionTemplate.self) { SessionTemplateEditorView(template: value) }
            case "appointment": if let value = draft.decode(TherapyExtraAppointment.self) { TherapyExtraAppointmentEditor(appointment: value) }
            case "recurrence": if let value = draft.decode(TherapyRecurrence.self) { TherapyRecurrenceEditor(rule: value) }
            default: ContentUnavailableView("Entwurf nicht verfügbar", systemImage: "doc.badge.ellipsis")
            }
        }
    }
}
