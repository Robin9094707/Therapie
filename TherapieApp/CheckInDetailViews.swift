import SwiftUI
import QuickLook

/// Only new entries and unfinished drafts start in the editor.
struct GuidedCheckInDestination: View {
    @EnvironmentObject private var store: AppStore
    let entry: GuidedCheckIn
    var body: some View {
        if entry.isDraft && store.data.aiSettings.enabled && store.data.aiSettings.preferGuidedCheckIns { AIBuddyEntryView(checkIn: DayCheckInPolicy.reopen(entry, in: store.data)) }
        else if entry.isDraft { GuidedCheckInView(entry: entry) }
        else { GuidedCheckInDetailView(entryID: entry.id) }
    }
}

struct GuidedCheckInDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var editing: GuidedCheckIn?
    @State private var preview: URL?
    private var entry: GuidedCheckIn? { store.data.guidedCheckIns.first { $0.id == entryID } }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                if let entry {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(entry.displayTitle, systemImage: entry.kind.symbol).font(.system(.title2, design: .rounded, weight: .bold))
                                Text(entry.date.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                CheckInMetricGrid(mood: entry.moodPercent.map { "\($0)/100" } ?? entry.mood.map { "\($0)/5" }, battery: entry.batteryPercent.map { "\($0) %" }, stress: entry.stress, sensory: entry.sensoryLoad, sleep: entry.sleepHours)
                            }
                        }
                        HashtagChips(tags: entry.tags ?? [])
                        CheckInTextCard(title: "Dein Rückblick", symbol: "text.bubble", items: [("Rückblick", entry.summary), ("Kleiner Erfolg", entry.smallWin), ("Jetzt brauche ich", entry.nextNeed), ("Frage für die Therapie", entry.therapyQuestion)])
                        CheckInBatteryDetail(points: entry.energyPoints ?? [], legacyGives: entry.givesEnergy, legacyTakes: entry.takesEnergy)
                        if !entry.tasks.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    SectionHeader(title: "Deine nächsten Schritte", icon: "checklist")
                                    ForEach(entry.tasks.filter { !$0.title.isEmpty }) { task in
                                        let saved = store.data.weeklyTasks.first { $0.id == task.id }
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label(task.title, systemImage: saved?.completed == true ? "checkmark.circle.fill" : "circle").font(.headline)
                                            Text(task.source).font(.caption).foregroundStyle(.secondary)
                                            if !task.smallStep.isEmpty { Text("Kleinster Schritt: " + task.smallStep) }
                                            if !task.details.isEmpty { Text(task.details) }
                                            if let due = task.dueDate { Text("Wunschtermin: " + due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                                            if entry.taskIDs.contains(task.id), saved == nil { Text("Die angelegte Aufgabe wurde inzwischen entfernt.").font(.caption).foregroundStyle(.secondary) }
                                        }.textSelection(.enabled)
                                    }
                                    Text("Häkchen zeigen den heutigen Stand der zugehörigen Aufgaben.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !entry.mediaIDs.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Deine Anhänge", icon: "photo.on.rectangle")
                                    ForEach(entry.mediaIDs, id: \.self) { id in
                                        if let item = store.data.media.first(where: { $0.id == id }) {
                                            if item.attachmentOmitted != true, let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL) {
                                                Button { preview = url } label: { Label(item.title, systemImage: item.kind.symbol) }.frame(minHeight: 44)
                                            } else { Label(item.title + " · Datei nicht verfügbar", systemImage: "doc.badge.ellipsis").font(.subheadline).foregroundStyle(.secondary) }
                                        } else { Label("Anhang nicht mehr im Archiv", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        ShareLink(item: GuidedCheckInExport.text(entry), subject: Text(entry.displayTitle)) { Label("Übersicht teilen", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    }.accessibilityIdentifier("checkin.detail")
                } else { ContentUnavailableView("Check-in nicht mehr vorhanden", systemImage: "doc.badge.ellipsis") }
            }.navigationTitle("Dein Check-in").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { if let entry { Button("Bearbeiten", systemImage: "pencil") { var draft = entry; draft.step = 0; editing = draft }.accessibilityIdentifier("checkin.detail.edit") } }
                }
                .sheet(item: $editing) { GuidedCheckInView(entry: $0) }
                .quickLookPreview($preview)
        }
    }
}

struct MoodCheckInDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var editing: MoodCheckIn?
    private var entry: MoodCheckIn? { store.data.moodCheckIns.first { $0.id == entryID } }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                if let entry {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(entry.moodTitle).font(.system(.title2, design: .rounded, weight: .bold))
                                Text(entry.date.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                CheckInMetricGrid(mood: entry.moodPercent.map { "\($0)/100" } ?? "\(entry.mood)/5", battery: "\(entry.battery)/5", stress: entry.stress, sensory: entry.sensoryLoad, sleep: entry.sleepHours)
                                if !entry.emotions.isEmpty { Label(entry.emotions.joined(separator: " · "), systemImage: "heart").font(.subheadline).textSelection(.enabled) }
                            }
                        }
                        CheckInTextCard(title: "Was du festgehalten hast", symbol: "text.bubble", items: [("Deine Notiz", entry.note), ("Kleiner Erfolg", entry.smallWin), ("Jetzt brauche ich", entry.nextNeed)])
                        CheckInBatteryDetail(points: store.data.batteryPoints.filter { $0.checkInID == entry.id })
                    }.accessibilityIdentifier("mood.detail")
                } else { ContentUnavailableView("Check-in nicht mehr vorhanden", systemImage: "doc.badge.ellipsis") }
            }.navigationTitle("Stimmungsübersicht").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { if let entry { Button("Bearbeiten", systemImage: "pencil") { editing = entry }.accessibilityIdentifier("mood.detail.edit") } }
                }
                .sheet(item: $editing) { value in MoodEditorView(entry: value, points: store.data.batteryPoints.filter { $0.checkInID == value.id }) }
        }
    }
}
private struct CheckInMetricGrid: View {
    var mood: String?
    var battery: String?
    var stress: Int?
    var sensory: Int?
    var sleep: Double?
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], alignment: .leading, spacing: 12) {
            metric("Stimmung", mood ?? "Offen", "face.smiling")
            metric("Akku", battery ?? "Offen", "battery.100percent")
            if let stress { metric("Stress", "\(stress)/5", "waveform.path") }
            if let sensory { metric("Reize", "\(sensory)/5", "ear") }
            if let sleep { metric("Schlaf", "\(sleep.formatted()) h", "moon") }
        }
    }
    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
private struct CheckInTextCard: View {
    let title: String
    let symbol: String
    let items: [(String, String)]
    var body: some View {
        if items.contains(where: { !$0.1.isEmpty }) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: title, icon: symbol)
                    ForEach(items.indices, id: \.self) { index in
                        let value = items[index]
                        if !value.1.isEmpty { VStack(alignment: .leading, spacing: 5) { Text(value.0).font(.subheadline.bold()); Text(value.1).textSelection(.enabled) } }
                    }
                }
            }
        }
    }
}
private struct CheckInBatteryDetail: View {
    let points: [BatteryPoint]
    var legacyGives = ""
    var legacyTakes = ""
    var body: some View {
        ForEach(BatteryDirection.allCases) { direction in
            let selected = points.filter { $0.direction == direction }
            let legacy = direction == .gives ? legacyGives : legacyTakes
            if !selected.isEmpty || !legacy.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: direction == .gives ? "Das gibt dir Akku" : "Das nimmt dir Akku", icon: direction.symbol)
                        ForEach(selected) { point in
                            VStack(alignment: .leading, spacing: 5) { Text(point.title).font(.headline); if !point.note.isEmpty { Text(point.note) }; Text("Wirkung \(point.impact)/5 · " + point.category.title).font(.caption).foregroundStyle(.secondary) }.textSelection(.enabled)
                        }
                        if !legacy.isEmpty { Text(legacy).textSelection(.enabled) }
                    }
                }
            }
        }
    }
}
