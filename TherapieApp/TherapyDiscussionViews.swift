import SwiftUI

struct TherapyDiscussionCard: View {
    @EnvironmentObject private var store: AppStore
    var alwaysVisible = false
    @State private var showAll = false
    @State private var expanded = false
    var body: some View {
        if alwaysVisible || TherapyDiscussionPlanner.isTherapyDay(store.data) {
            let points = TherapyDiscussionPlanner.points(in: store.data, includeDiscussed: showAll)
            GlassCard(emphasized: !points.isEmpty) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Das wollte ich besprechen", icon: "text.bubble", subtitle: "Gesammelt aus deinen Check-ins und Rückblicken · \(points.count) Punkte")
                    if points.isEmpty { Text("Hier erscheinen deine Therapiefragen. Beim Check-in kannst du jederzeit festhalten, was du besprechen möchtest.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(Array(points.prefix(expanded ? 200 : 5))) { point in
                        let discussed = store.data.therapyDiscussionAcknowledgedIDs.contains(point.id)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(point.text).font(.subheadline).textSelection(.enabled)
                            Text(point.source + " · " + point.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Button(discussed ? "Wieder auf die Gesprächsliste" : "Als besprochen markieren", systemImage: discussed ? "arrow.uturn.backward" : "checkmark.circle") {
                                if discussed { store.data.therapyDiscussionAcknowledgedIDs.removeAll { $0 == point.id } }
                                else { store.data.therapyDiscussionAcknowledgedIDs.append(point.id) }
                            }.font(.caption).buttonStyle(.bordered)
                        }
                        Divider()
                    }
                    if points.count > 5 { Button(expanded ? "Weniger anzeigen" : "Alle Punkte anzeigen") { expanded.toggle() } }
                    Toggle("Auch besprochene Punkte zeigen", isOn: $showAll).font(.caption)
                    Text("Offene Punkte bleiben bis zum Markieren erhalten. Die ursprünglichen Einträge werden dabei nicht verändert.").font(.caption2).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("therapy.discussion")
        }
    }
}
