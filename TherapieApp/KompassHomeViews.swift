import SwiftUI

// MARK: - Heute (Kompass 6): quick capture and everyday tools

enum QuickCaptureKind: String, CaseIterable, Identifiable {
    case note, task, therapyTopic, bewoTopic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .note: "Notiz"
        case .task: "Aufgabe"
        case .therapyTopic: "Therapie-Thema"
        case .bewoTopic: "BeWo-Thema"
        }
    }
    var symbol: String {
        switch self {
        case .note: "square.and.pencil"
        case .task: "checklist"
        case .therapyTopic: "leaf.fill"
        case .bewoTopic: "house.fill"
        }
    }
    var tint: Color {
        switch self {
        case .note: .orange
        case .task: .blue
        case .therapyTopic: .green
        case .bewoTopic: .brown
        }
    }
    var placeholder: String {
        switch self {
        case .note: "Was beschäftigt dich gerade?"
        case .task: "Was möchtest du diese Woche schaffen?"
        case .therapyTopic: "Was möchtest du in der Therapie ansprechen?"
        case .bewoTopic: "Was möchtest du mit deiner Betreuung besprechen?"
        }
    }
}

/// One field for everything: write, pick a kind, save. Editors stay one tap away for details.
struct QuickCaptureCard: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("kompass.quickCapture.kind") private var kindRaw = QuickCaptureKind.note.rawValue
    @State private var text = ""
    @State private var confirmation: String?
    @State private var mood: MoodCheckIn?
    @State private var askAI = false
    @FocusState private var focused: Bool

    private var kind: QuickCaptureKind { QuickCaptureKind(rawValue: kindRaw) ?? .note }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Schnell festhalten", systemImage: "bolt.fill").font(.system(.headline, design: .rounded)).foregroundStyle(.primary)
                    Spacer()
                    if focused { Button("Fertig") { focused = false }.font(.subheadline.weight(.semibold)) }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(QuickCaptureKind.allCases) { option in
                            let selected = option == kind
                            Button {
                                TherapyEffects.shared.light()
                                withAnimation(.snappy(duration: 0.2)) { kindRaw = option.rawValue }
                            } label: {
                                Label(option.title, systemImage: option.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(selected ? AnyShapeStyle(option.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("capture.kind." + option.rawValue)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(kind.placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                        .padding(12)
                        .therapyInsetSurface()
                        .accessibilityIdentifier("capture.text")
                    Button(action: save) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(trimmed.isEmpty ? Color.secondary : kind.tint)
                    }
                    .disabled(trimmed.isEmpty)
                    .accessibilityLabel(kind.title + " sichern")
                    .accessibilityIdentifier("capture.save")
                }
                if let detected = GermanDateDetector.detect(trimmed) {
                    DetectedDateSuggestions(text: trimmed, detected: detected) { message in
                        text = ""
                        TherapyEffects.shared.light()
                        withAnimation { confirmation = message }
                        Task { @MainActor in try? await Task.sleep(for: .seconds(2.5)); withAnimation { confirmation = nil } }
                    }
                    .transition(.opacity)
                }
                if store.data.aiSettings.enabled && !trimmed.isEmpty {
                    Button { focused = false; askAI = true } label: { Label("Mit KI besprechen & einordnen", systemImage: "sparkles") }
                        .font(.caption.weight(.semibold)).tint(.indigo)
                        .accessibilityIdentifier("capture.ai")
                }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(.green)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Divider()
                HStack(spacing: 4) {
                    Text("Wie geht es dir?").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    ForEach(1...5, id: \.self) { level in
                        Button { mood = MoodCheckIn(date: Date(), mood: level, battery: 3) } label: {
                            Text(BeWoMood.faces[level - 1]).font(.title2).frame(width: 40, height: 40).contentShape(Rectangle())
                        }
                        .buttonStyle(TherapyPressStyle())
                        .accessibilityLabel("Stimmung: " + BeWoMood.titles[level - 1])
                    }
                }
            }
        }
        .sheet(item: $mood) { MoodEditorView(entry: $0).presentationDetents([.large]) }
        .sheet(isPresented: $askAI, onDismiss: { text = "" }) {
            AIBuddyEntryView(initialQuestion: trimmed + "\n\n(Ordne das bitte ein und schlage passende Einträge als Aktionen vor – bei einem Termin den passenden Termin.)")
        }
    }

    private func save() {
        let value = trimmed
        guard !value.isEmpty else { return }
        let firstLine = value.components(separatedBy: .newlines).first ?? value
        let title = String(firstLine.prefix(80))
        switch kind {
        case .note:
            store.saveNote(TherapyNote(title: title, text: value, tags: []))
        case .task:
            let week = Date().therapyWeek
            let details = value == firstLine ? "" : String(value.dropFirst(firstLine.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            store.data.weeklyTasks.insert(WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: title, details: details), at: 0)
        case .therapyTopic:
            var topic = TherapyTopic(title: title, isCurrent: true)
            topic.description = value == firstLine ? "" : value
            store.saveTopic(topic)
        case .bewoTopic:
            var topic = AssistedLivingTopic(title: title)
            topic.details = value == firstLine ? "" : value
            store.saveAssistedLivingTopic(topic)
        }
        guard store.lastSaveError == nil else { return }
        text = ""
        TherapyEffects.shared.light()
        withAnimation { confirmation = kind.title + " gesichert" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { confirmation = nil }
        }
    }
}

/// AI shortcuts on Heute (only when the companion is set up).
struct TodayAIStrip: View {
    var body: some View {
        AIShortcutStrip(title: "Frag Kompass", prompts: [
            ("Mein Tag", "sun.max", "Was steht heute an (Therapie, BeWo, Routinen, Aufgaben)? Hilf mir mit einer realistischen Reihenfolge und einem kleinen ersten Schritt."),
            ("Wie geht's mir?", "heart.text.square", "Wie ging es mir in den letzten 7 Tagen laut meinen Einträgen? Kurz, mit Datumsbelegen und einem freundlichen nächsten Schritt."),
            ("Woche planen", "calendar", "Hilf mir, die nächsten 7 Tage zu planen: Termine (Therapie und BeWo), Aufgaben und Pausen. Schlage nur ausdrücklich gewünschte Einträge als Aktionen vor."),
            ("Ruhe planen", "moon.zzz", "Ich brauche weniger Erinnerungen. Was kommt heute noch, und welche Ruhe-Variante passt?")
        ])
    }
}

/// Everyday tools on Heute: one compact grid instead of a separate tab.
struct EverydayToolsSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var sheet: TherapyFeature?

    var body: some View {
        FeatureGridSection(title: "Dein Alltag", icon: "figure.mind.and.body", tint: .orange,
                           features: TherapyFeature.features(["routines", "tasks", "quiet", "alarms", "showers", "timeline", "emergency", "methods", "grounding", "checkins", "bewo", "everyday"], data: store.data),
                           compact: true) { sheet = $0 }
            .sheet(item: $sheet) { feature in TherapyFeatureDestination(id: feature.id) }
    }
}

/// The moon in the Heute toolbar; filled while a general pause is active.
struct QuietToolbarButton: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let active = QuietPolicy.globalPause(store.data.quietMode) != nil
        Button { store.notificationQuietCenter = true } label: {
            Label(active ? "Ruhe ist an" : "Mitteilungen & Wecker", systemImage: active ? "moon.zzz.fill" : "moon")
        }
        .tint(active ? .indigo : nil)
        .accessibilityIdentifier("today.quiet")
    }
}
