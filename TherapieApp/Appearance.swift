import SwiftUI

enum TherapyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Wie das iPhone"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearanceCard: View {
    @AppStorage("therapy.appearance") private var appearance = TherapyAppearance.system.rawValue
    @AppStorage("therapy.calmInterface") private var calmInterface = true

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Deine Oberfläche", icon: "paintpalette.fill",
                              subtitle: "So übersichtlich und ruhig, wie du es brauchst.")
                Picker("Darstellung", selection: $appearance) {
                    ForEach(TherapyAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Ruhige Oberfläche", isOn: $calmInterface)
                Text("Weniger Transparenz und Farbverläufe. Die Schriftgröße folgt deinen iPhone-Einstellungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Version", value: "1.2.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekOverviewCard: View {
    @EnvironmentObject private var store: AppStore
    private var tasks: [WeeklyTask] {
        let week = Date().therapyWeek
        return store.data.weeklyTasks.filter {
            $0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year
        }
    }
    private var completed: Int { tasks.filter(\.completed).count }
    private var latestEnergy: EnergyEntry? {
        store.data.energyEntries.filter { $0.createdAt.isSameTherapyDay(as: Date()) }
            .max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Deine Woche", icon: "chart.bar.xaxis",
                              subtitle: "Kleine Schritte zählen.")
                if tasks.isEmpty {
                    Text("Noch keine Wochenaufgabe. Du kannst in deinem Tempo starten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("\(completed) von \(tasks.count) Aufgaben erledigt")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    ProgressView(value: Double(completed), total: Double(tasks.count))
                        .tint(.indigo)
                        .accessibilityLabel("Wochenfortschritt")
                        .accessibilityValue("\(completed) von \(tasks.count)")
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Energie heute").font(.subheadline.weight(.semibold))
                        if let entry = latestEnergy {
                            Text("\(entry.level) von 5 · " + entry.createdAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                            if !entry.givesEnergy.isEmpty {
                                Text("Gibt dir Energie: " + entry.givesEnergy)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Über den Energie-Check kannst du kurz festhalten, wie es dir geht.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct TherapyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
