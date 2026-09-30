import SwiftUI

struct CompanionTodayCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var checkIn: GuidedCheckIn?
    @State private var showEntries = false
    @State private var showRoutines = false
    @AppStorage("therapy.calmInterface") private var calmInterface = true
    var body: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Ein Moment für dich", icon: "sparkles", subtitle: "Ankommen, Energie spüren, einen kleinen Schritt wählen.")
                    Spacer(minLength: 0)
                    Menu {
                        Button("Liquid Glass", systemImage: "sparkles") { calmInterface = false; store.refreshReadableFiles() }
                        Button("Ruhige Darstellung", systemImage: "leaf") { calmInterface = true; store.refreshReadableFiles() }
                    } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Darstellung wählen")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { checkInButton(.morning); checkInButton(.evening); checkInButton(.therapy) }
                    VStack(alignment: .leading, spacing: 10) { checkInButton(.morning); checkInButton(.evening); checkInButton(.therapy) }
                }
                ForEach(store.data.guidedCheckIns.filter(\.isDraft).prefix(2)) { draft in
                    Button { checkIn = draft } label: { Label("\(draft.kind.title) fortsetzen · Schritt \(draft.step + 1)", systemImage: "arrow.uturn.forward") }.font(.subheadline)
                }
                Divider()
                HStack {
                    Button("Neuer Eintrag", systemImage: "plus.circle.fill") { showEntries = true }
                    Spacer()
                    Button("Routinen & Ziele", systemImage: "alarm") { showRoutines = true }
                }.font(.subheadline.weight(.semibold))
                let due = RoutinePlanner.due(data: store.data)
                if !due.isEmpty {
                    Label("\(due.count) Routine\(due.count == 1 ? "" : "n") noch offen", systemImage: "bell.badge.fill").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .sheet(item: $checkIn) { GuidedCheckInView(entry: $0) }
        .sheet(isPresented: $showEntries) { EntryHubView() }
        .sheet(isPresented: $showRoutines) { NavigationStack { RoutineHubView() } }
    }
    private func checkInButton(_ kind: GuidedCheckInKind) -> some View {
        Button { checkIn = GuidedCheckIn(kind: kind) } label: { Label(kind == .morning ? "Morgen" : kind == .evening ? "Abend" : "Therapie", systemImage: kind.symbol).padding(.vertical, 6) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
    }
}
struct EntryHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn: GuidedCheckIn?
    @State private var showPhoto = false
    @State private var showMood = false
    @State private var showBattery = false
    @State private var showNote = false
    @State private var showAudio = false
    var body: some View {
        NavigationStack {
            TherapyScreen {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Was möchtest du festhalten?").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Ein Foto, eine Stimmung oder ein kompletter Check-in. Alles bleibt in deinem persönlichen Archiv.").foregroundStyle(.secondary)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Button("Geführter Check-in", systemImage: "sparkles") { checkIn = GuidedCheckIn() }
                            Button("Stimmung & Energie", systemImage: "face.smiling") { showMood = true }
                            Button("Akku-Geber oder Akku-Nehmer", systemImage: "battery.75percent") { showBattery = true }
                            Button("Neues Foto", systemImage: "photo.badge.plus") { showPhoto = true }
                            Button("Eine Notiz", systemImage: "square.and.pencil") { showNote = true }
                            Button("Eine Sprachnotiz", systemImage: "waveform") { showAudio = true }
                        }.font(.headline)
                    }
                    ForEach(store.data.guidedCheckIns.sorted { $0.date > $1.date }) { entry in
                        GuidedCheckInCard(entry: entry, edit: { checkIn = entry })
                    }
                }
            }.navigationTitle("Deine Einträge").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
                .sheet(item: $checkIn) { GuidedCheckInView(entry: $0) }
                .sheet(isPresented: $showPhoto) { AddPhotoView() }
                .sheet(isPresented: $showMood) { MoodEditorView() }
                .sheet(isPresented: $showBattery) { BatteryPointEditorView { store.saveBatteryPoint($0); return store.lastSaveError == nil } }
                .sheet(isPresented: $showNote) { AddNoteView() }
                .sheet(isPresented: $showAudio) { AudioRecordingView() }
        }
    }
}
struct GuidedCheckInCard: View {
    @EnvironmentObject private var store: AppStore
    let entry: GuidedCheckIn
    let edit: () -> Void
    @State private var deleting = false
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label(entry.kind.title, systemImage: entry.kind.symbol).font(.headline); Spacer(); if entry.isDraft { Text("Entwurf").font(.caption).foregroundStyle(.secondary) } }
                GuidedCheckInSummary(entry: entry)
                ResponsiveButtonRow {
                    Button(entry.isDraft ? "Fortsetzen" : "Bearbeiten", systemImage: "pencil", action: edit).buttonStyle(.bordered)
                    ShareLink(item: GuidedCheckInExport.text(entry), subject: Text(entry.kind.title)) { Label("Teilen", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    Button("Löschen", systemImage: "trash", role: .destructive) { deleting = true }.buttonStyle(.bordered)
                }
                if !entry.mediaIDs.isEmpty {
                    ForEach(entry.mediaIDs, id: \.self) { id in
                        if let media = store.data.media.first(where: { $0.id == id }) {
                            if media.attachmentOmitted == true { Label(media.title + " · Datei nicht im Backup enthalten", systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.secondary) }
                            else { ShareLink(item: store.fileURL(for: media)) { Label(media.title, systemImage: "photo") }.font(.caption) }
                        }
                    }
                }
            }
        }.alert("Check-in löschen?", isPresented: $deleting) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { store.data.guidedCheckIns.removeAll { $0.id == entry.id } }
        } message: { Text("Die bereits angelegten Aufgaben und Fotos bleiben im Archiv erhalten.") }
    }
}
enum GuidedCheckInExport {
    static func text(_ entry: GuidedCheckIn) -> String {
        var lines = [entry.kind.title, entry.date.formatted(date: .complete, time: .shortened)]
        if let mood = entry.mood { lines.append("Stimmung: " + MoodCheckIn.moodTitles[max(0, min(4, mood - 1))]) }
        if let battery = entry.batteryPercent { lines.append("Akku: \(battery) %") }
        if let stress = entry.stress { lines.append("Stress: \(stress)/5") }
        if let sensory = entry.sensoryLoad { lines.append("Reize: \(sensory)/5") }
        if let sleep = entry.sleepHours { lines.append("Schlaf: \(sleep.formatted()) Stunden") }
        for (label, text) in [("Rückblick", entry.summary), ("Gibt Energie", entry.givesEnergy), ("Kostet Energie", entry.takesEnergy), ("Kleiner Erfolg", entry.smallWin), ("Jetzt brauche ich", entry.nextNeed), ("Therapiefrage", entry.therapyQuestion)] where !text.isEmpty { lines.append(label + ": " + text) }
        for task in entry.tasks where !task.title.isEmpty { lines.append("Aufgabe (\(task.source)): \(task.title)\nKleiner Schritt: \(task.smallStep)\n\(task.details)") }
        if !entry.mediaIDs.isEmpty { lines.append("Fotos: \(entry.mediaIDs.count) · separat im Archiv teilen") }
        return lines.joined(separator: "\n\n")
    }
}
