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
    @EnvironmentObject private var store: AppStore
    @AppStorage("therapy.haptics") private var haptics = true
    @AppStorage("therapy.confetti") private var confetti = true
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
                Toggle("Feine Haptik", isOn: $haptics)
                Toggle("Konfetti bei erledigten Aufgaben", isOn: $confetti)
                Text("Bei reduzierter Bewegung erscheint eine ruhige Bestätigung statt Konfetti.").font(.caption).foregroundStyle(.secondary)
                Text("Weniger Transparenz und Farbverläufe. Die Schriftgröße folgt deinen iPhone-Einstellungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3000.0.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: appearance) { _, _ in store.refreshReadableFiles() }
        .onChange(of: calmInterface) { _, _ in store.refreshReadableFiles() }
        .onChange(of: haptics) { _, _ in store.refreshReadableFiles() }
        .onChange(of: confetti) { _, _ in store.refreshReadableFiles() }
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
    private var latestMood: MoodCheckIn? {
        store.data.moodCheckIns.filter { $0.date.isSameTherapyDay(as: Date()) }.max { $0.date < $1.date }
    }

    private var latestGuided: GuidedCheckIn? {
        store.data.guidedCheckIns.filter { !$0.isDraft && $0.date.isSameTherapyDay(as: Date()) }.max { $0.date < $1.date }
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
                        Text("Stimmung & Akku heute").font(.subheadline.weight(.semibold))
                        if let entry = latestGuided, entry.date >= max(latestMood?.date ?? .distantPast, latestEnergy?.createdAt ?? .distantPast) {
                            Text(entry.mood.map { MoodCheckIn.moodTitles[max(0, min(4, $0 - 1))] } ?? "Stimmung offen")
                            Text(entry.batteryPercent.map { "Akku \($0) %" } ?? "Akku offen").font(.subheadline.weight(.semibold))
                            Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if !entry.nextNeed.isEmpty { Text("Jetzt brauche ich: " + entry.nextNeed).font(.footnote).foregroundStyle(.secondary) }
                        } else if let entry = latestMood {
                            Text("\(entry.face) \(entry.moodTitle) · Akku \(entry.battery)/5")
                            Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if !entry.nextNeed.isEmpty { Text("Jetzt brauche ich: " + entry.nextNeed).font(.footnote).foregroundStyle(.secondary) }
                        } else if let entry = latestEnergy {
                            Text("\(entry.level) von 5 · " + entry.createdAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                            if !entry.givesEnergy.isEmpty {
                                Text("Gibt dir Energie: " + entry.givesEnergy)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Über den Stimmungs-Check-in kannst du kurz festhalten, wie es dir geht.")
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
