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
    @State private var showWhatsNew = false

    var body: some View {
        VStack(spacing: 18) {
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Liquid Glass", icon: "circle.lefthalf.filled", subtitle: "Wie viel Glas du sehen möchtest – live ausprobieren.")
                    SurfacePreviewTile()
                    HStack(spacing: 10) {
                        ForEach(SurfaceStyle.allCases) { style in styleButton(style) }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(SurfacePreferences.presets.indices, id: \.self) { index in
                                let preset = SurfacePreferences.presets[index]
                                Button(preset.title) { withAnimation(.snappy) { store.data.surface = preset.value } }
                                    .buttonStyle(.glass)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if store.data.surface.style != .solid {
                        slider("Deckkraft der Karten", value: $store.data.surface.coverage, low: "Durchsichtig", high: "Deckend", icon: "square.fill.on.square.fill")
                    }
                    slider("Farbtönung", value: $store.data.surface.tintStrength, low: "Zart", high: "Kräftig", icon: "paintbrush.fill")
                    slider("Farbverlauf im Hintergrund", value: $store.data.surface.backgroundIntensity, low: "Fast weiß", high: "Lebendig", icon: "circle.hexagongrid.fill")
                    Toggle("Glas reagiert auf Berührung", isOn: $store.data.surface.interactiveGlass)
                    Toggle("Runde, weiche Karten", isOn: $store.data.surface.roundedCards)
                    Text("„Sanftes Glas“ behält die Glas-Kanten, deckt den Hintergrund aber ruhig ab. Für vollständig deckende Flächen kannst du auch „Matt“ wählen oder in den iPhone-Bedienungshilfen „Transparenz reduzieren“ einschalten.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Farbe & Helligkeit", icon: "paintpalette.fill", subtitle: "So übersichtlich und ruhig, wie du es brauchst.")
                    Picker("Darstellung", selection: $appearance) {
                        ForEach(TherapyAppearance.allCases) { option in Text(option.title).tag(option.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(AppAccent.allCases) { accent in accentButton(accent) }
                    }
                    Toggle("Ruhige Oberfläche", isOn: $calmInterface)
                    Text("Die ruhige Oberfläche dämpft zusätzlich Farbverlauf und Glastönung. Die Schriftgröße folgt deinen iPhone-Einstellungen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Gefühl", icon: "hand.tap.fill", subtitle: "Haptik und kleine Feiern.")
                    Toggle("Feine Haptik", isOn: $haptics)
                    Toggle("Konfetti bei erledigten Aufgaben", isOn: $confetti)
                    Text("Bei reduzierter Bewegung erscheint eine ruhige Bestätigung statt Konfetti.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Version", value: TherapyDesign.appVersion).font(.footnote).foregroundStyle(.secondary)
                    Button("Neu in dieser Version", systemImage: "sparkles") { showWhatsNew = true }
                        .buttonStyle(.glass)
                }
            }
        }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
        .onChange(of: appearance) { _, _ in store.refreshReadableFiles() }
        .onChange(of: calmInterface) { _, _ in store.refreshReadableFiles() }
        .onChange(of: haptics) { _, _ in store.refreshReadableFiles() }
        .onChange(of: confetti) { _, _ in store.refreshReadableFiles() }
    }

    private func styleButton(_ style: SurfaceStyle) -> some View {
        let selected = store.data.surface.style == style
        return Button {
            TherapyEffects.shared.light()
            withAnimation(.snappy) { store.data.surface.style = style }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: style.symbol).font(.title3.weight(.semibold))
                Text(style.title).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(style.subtitle).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(8)
            .therapyInsetSurface(selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(TherapyPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accentButton(_ accent: AppAccent) -> some View {
        let selected = store.data.accentTheme == accent
        return Button {
            TherapyEffects.shared.light()
            store.data.accentTheme = accent
        } label: {
            VStack(spacing: 6) {
                Circle().fill(accent.color.gradient)
                    .frame(width: 34, height: 34)
                    .overlay { if selected { Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.white) } }
                    .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: selected ? 2 : 0) }
                Text(accent.title).font(.caption2.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TherapyPressStyle())
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func slider(_ title: String, value: Binding<Double>, low: String, high: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// A small live sample of a card, chip and tile with the current surface settings.
private struct SurfacePreviewTile: View {
    var body: some View {
        ZStack {
            AppBackground().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TherapyIconTile(icon: "leaf.fill", size: 30, tint: .teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nächste Therapie").font(.subheadline.weight(.bold))
                        Text("Dienstag · 15:00").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    TherapyChip(text: "2 Routinen", icon: "repeat", tint: .green)
                    TherapyChip(text: "BeWo morgen", icon: "house.fill", tint: .orange)
                }
            }
            .padding(14)
            .therapyGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(14)
        }
        .frame(height: 150)
        .accessibilityHidden(true)
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
                        .tint(Color.accentColor)
                        .accessibilityLabel("Wochenfortschritt")
                        .accessibilityValue("\(completed) von \(tasks.count)")
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
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
