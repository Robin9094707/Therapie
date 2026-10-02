import SwiftUI

struct RoutineHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    @State private var query = ""
    @State private var outcome = "all"
    private var logs: [RoutineCompletion] {
        let cutoff = days == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return store.data.routineCompletions.filter { log in
            log.scheduledAt >= cutoff && (outcome == "all" || log.outcome.rawValue == outcome) && (query.isEmpty || (RoutineHistoryMutation.title(log, data: store.data) + " " + (log.timeTitle ?? "") + " " + log.note).localizedCaseInsensitiveContains(query))
        }.sorted { $0.scheduledAt > $1.scheduledAt }
    }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                LazyVStack(alignment: .leading, spacing: 16) {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Deine kleinen Schritte", icon: "clock.arrow.circlepath", subtitle: "Auch gelöschte Routinen bleiben hier nachvollziehbar.")
                            Picker("Zeitraum", selection: $days) { Text("14 Tage").tag(14); Text("30 Tage").tag(30); Text("Alles").tag(0) }.pickerStyle(.segmented)
                            Picker("Status", selection: $outcome) { Text("Alle").tag("all"); Text("Erledigt").tag("done"); Text("Ausgelassen").tag("skipped") }.pickerStyle(.segmented)
                            Text("\(logs.filter { $0.outcome == .done }.count) erledigt · \(logs.filter { $0.outcome == .skipped }.count) ausgelassen").font(.headline)
                            Text("Gezählt werden nur deine Bestätigungen. Fehlende Einträge gelten nicht automatisch als ausgelassen. Korrekturen ändern keine Erinnerungen und bleiben sichtbar.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if logs.isEmpty { ContentUnavailableView("Noch kein passender Verlauf", systemImage: "clock", description: Text("Hier erscheinen erledigte und bewusst ausgelassene Termine.")) }
                    ForEach(logs) { RoutineHistoryCard(log: $0, showTitle: true) }
                }
            }.buttonStyle(.borderless).navigationTitle("Routinenverlauf").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Routine oder Notiz suchen")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
struct RoutineHistoryCard: View {
    @EnvironmentObject private var store: AppStore
    let log: RoutineCompletion
    var showTitle = false
    @State private var correcting = false
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if showTitle { Text(RoutineHistoryMutation.title(log, data: store.data)).font(.headline) }
                if let title = log.timeTitle, !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
                Label(log.outcome == .done ? "Erledigt" : "Ausgelassen", systemImage: log.outcome == .done ? "checkmark.circle.fill" : "forward.end").foregroundStyle(log.outcome == .done ? .green : .secondary)
                Text("Fällig: " + log.scheduledAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Text("Erste Bestätigung: " + log.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if !log.note.isEmpty { Text(log.note).font(.subheadline) }
                if let corrections = log.corrections, !corrections.isEmpty {
                    DisclosureGroup("\(corrections.count) Korrektur\(corrections.count == 1 ? "" : "en")") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(corrections) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                                    Text("\(item.previousOutcome == .done ? "Erledigt" : "Ausgelassen") → \(item.outcome == .done ? "Erledigt" : "Ausgelassen")").font(.caption)
                                    Text(item.reason).font(.subheadline)
                                    if item.previousNote != item.note {
                                        Text("Vorherige Notiz: " + (item.previousNote.isEmpty ? "–" : item.previousNote)).font(.caption).foregroundStyle(.secondary)
                                        Text("Neue Notiz: " + (item.note.isEmpty ? "–" : item.note)).font(.caption)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }
                Button("Angabe korrigieren", systemImage: "pencil") { correcting = true }.font(.caption)
            }
        }.sheet(isPresented: $correcting) { RoutineCorrectionView(log: log) }
    }
}
private struct RoutineCorrectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let log: RoutineCompletion
    @State private var outcome: RoutineOutcome
    @State private var note: String
    @State private var reason = ""
    @State private var confirm = false
    @State private var error: String?
    init(log: RoutineCompletion) {
        self.log = log
        _outcome = State(initialValue: log.outcome); _note = State(initialValue: log.note)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(RoutineHistoryMutation.title(log, data: store.data)).font(.headline)
                    Text(log.scheduledAt.formatted(date: .complete, time: .shortened))
                }
                Section("Richtige Angabe") {
                    Picker("Status", selection: $outcome) { Text("Erledigt").tag(RoutineOutcome.done); Text("Ausgelassen").tag(RoutineOutcome.skipped) }
                    TextField("Notiz (optional)", text: $note, axis: .vertical).lineLimit(2...6)
                    TextField("Warum korrigierst du die Angabe?", text: $reason, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Text("Die ursprüngliche Bestätigung bleibt im Korrekturverlauf erhalten. Dieser Termin wird dadurch nicht erneut erinnert.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.buttonStyle(.borderless).navigationTitle("Angabe korrigieren").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { confirm = true }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (outcome == log.outcome && note == log.note)) }
                }
                .alert("Korrektur speichern?", isPresented: $confirm) {
                    Button("Abbrechen", role: .cancel) {}
                    Button("Ja, korrigieren") {
                        store.correctRoutineLog(id: log.id, outcome: outcome, note: note, reason: reason)
                        if let failure = store.lastSaveError { error = failure } else { dismiss() }
                    }
                } message: { Text("Der aktuelle Status wird geändert; die vorherige Angabe und dein Grund bleiben erhalten.") }
        }
    }
}
