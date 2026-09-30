import SwiftUI

struct TherapyTodayCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GlassCard(emphasized: store.data.currentSession != nil) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Deine Therapie", icon: "leaf", subtitle: "Für die nächste Stunde bereitlegen.")
                Button("Wochenenergie für die Therapie eintragen", systemImage: "battery.100percent") { store.openEnergyReview = true }
                NavigationLink { SessionConductorView() } label: {
                    Label(store.data.currentSession == nil ? "Therapiestunde starten" : "Laufende Therapiestunde öffnen", systemImage: "timer").font(.headline)
                }
                let current = store.data.therapyTopics.filter(\.isCurrent)
                ForEach(Array(current.prefix(3))) { topic in Label(topic.title, systemImage: topic.category.symbol).font(.subheadline) }
                let important = store.data.notes.filter { $0.isImportant == true }.sorted { $0.createdAt > $1.createdAt }
                ForEach(Array(important.prefix(2))) { note in Label(note.title, systemImage: "pin.fill").font(.subheadline).foregroundStyle(.secondary) }
                if current.isEmpty && important.isEmpty { Text("Wähle aktuelle Themen und hefte wichtige Notizen im Bereich Therapie an.").font(.subheadline).foregroundStyle(.secondary) }
                Text("\(store.data.therapyGoals.filter { $0.status != .completed }.count) offene Ziele · \(store.data.media.count) Materialien").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
