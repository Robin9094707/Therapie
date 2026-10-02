import SwiftUI
import AVFoundation

extension AppAccent {
    var color: Color {
        switch self { case .indigo: .indigo; case .blue: .blue; case .purple: .purple; case .red: .red; case .teal: .teal; case .green: .green; case .rose: .pink; case .amber: .orange }
    }
}
enum BatteryTone {
    static func color(_ percent: Int) -> Color { percent < 25 ? .red : percent < 50 ? .orange : percent < 75 ? .yellow : .green }
    static func burden(_ value: Int) -> Color { color(100 - (max(1, min(5, value)) - 1) * 25) }
}
@MainActor final class BuddySpeech: ObservableObject {
    @Published var readingID: UUID?
    private let synthesizer = AVSpeechSynthesizer()
    func stop() { synthesizer.stopSpeaking(at: .immediate); readingID = nil }
    func read(_ text: String, id: UUID) {
        if readingID == id && synthesizer.isSpeaking { stop(); return }
        stop(); readingID = id
        let utterance = AVSpeechUtterance(string: AIBuddyText.plain(text))
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE"); utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

/// One tap records; the next stops and transcribes. Upload consent is explicit and revocable.
struct BuddyInlineMicrophone: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = AudioRecorderService()
    @State private var file = FileManager.default.temporaryDirectory.appendingPathComponent("buddy-inline-" + UUID().uuidString + ".m4a")
    @State private var starting = false
    @State private var busy = false
    @State private var pending = false
    @State private var consent = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    var disabled = false
    var beforeRecording: () -> Void = {}
    var receive: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    if recorder.isRecording { stop(upload: true) }
                    else if pending { transcribe() }
                    else if !store.data.aiSettings.allowVoiceUploads { consent = true }
                    else { start() }
                } label: { Image(systemName: recorder.isRecording ? "stop.circle.fill" : pending ? "arrow.clockwise.circle" : "mic.fill").font(.title3).foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(recorder.isRecording ? "Aufnahme stoppen und transkribieren" : pending ? "Transkription erneut versuchen" : "Sprachnachricht aufnehmen")
                    .disabled(busy || starting || (disabled && !recorder.isRecording))
                if recorder.isRecording { Text("\(Int(recorder.elapsed)) s").monospacedDigit().foregroundStyle(.red).font(.caption) }
                if busy { ProgressView().controlSize(.small).accessibilityLabel("Sprachnachricht wird transkribiert") }
                if pending && !busy { Button("Verwerfen", systemImage: "trash") { reset() }.labelStyle(.iconOnly) }
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
        .alert("Sprachnachrichten aktivieren?", isPresented: $consent) {
            Button("Abbrechen", role: .cancel) {}
            Button("Erlauben und aufnehmen") { store.data.aiSettings.allowVoiceUploads = true; if store.lastSaveError == nil { start() } }
        } message: { Text("Beim Stoppen wird deine eigene Aufnahme automatisch an OpenAI übertragen. Die Transkription kostet laut deinem API-Tarif. Maximal zwei Minuten. Im Chat kannst du den Text vor dem Senden bearbeiten; während der Therapiestunde wird er als Notiz gespeichert. Die Freigabe ist im KI-Profil widerrufbar.") }
        .onChange(of: recorder.elapsed) { _, elapsed in if elapsed >= 120 && recorder.isRecording { stop(upload: true) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active && recorder.isRecording { stop(upload: false) } }
        .onChange(of: store.data.aiSettings.enabled) { _, enabled in if !enabled { operation?.cancel(); _ = recorder.stop(); reset() } }
        .onChange(of: store.data.aiSettings.allowVoiceUploads) { _, allowed in if !allowed { operation?.cancel(); _ = recorder.stop(); reset() } }
        .onDisappear { operation?.cancel(); _ = recorder.stop(); reset() }
    }
    private func start() {
        guard !busy, !starting, AIBuddyKeychain.read() != nil else { error = "Bitte zuerst den API-Schlüssel hinterlegen."; return }
        beforeRecording(); starting = true; error = nil
        operation = Task { @MainActor in
            defer { starting = false }
            do { try await recorder.start(url: file); if Task.isCancelled { _ = recorder.stop(); reset() } }
            catch { self.error = error.localizedDescription }
        }
    }
    private func stop(upload: Bool) {
        let duration = recorder.stop(); pending = duration > 0
        if upload && pending { transcribe() }
        else if pending { error = "Aufnahme angehalten. Tippe zum Transkribieren oder verwirf sie." }
    }
    private func transcribe() {
        guard !busy, pending, let key = AIBuddyKeychain.read() else { error = "Bitte zuerst den API-Schlüssel hinterlegen."; return }
        busy = true; error = nil
        let settings = store.data.aiSettings
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let value = try await AIBuddyAPI().transcribe(file: file, settings: settings, key: key)
                try Task.checkCancellation()
                guard store.data.aiSettings.enabled && store.data.aiSettings.allowVoiceUploads else { return }
                receive(value); reset()
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func reset() { pending = false; try? FileManager.default.removeItem(at: file) }
}

struct BuddyConversationSummaryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var conversationID: UUID
    @State private var title = ""
    @State private var summary = ""
    @State private var tags: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var initialized = false
    @State private var operation: Task<Void, Never>?
    private var chat: AIBuddyConversation? { store.data.aiConversations.first { $0.id == conversationID } }
    private var messages: [AIBuddyMessage] { store.data.aiMessages.filter { $0.conversationID == conversationID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("So erscheint dein Eintrag") {
                    TherapyInputField(title: "Überschrift", multiline: false, text: $title)
                    TherapyInputField(title: "Zusammenfassung", text: $summary)
                    HashtagEditor(tags: $tags)
                }
                Section {
                    Button(busy ? "Zusammenfassung entsteht …" : "Mit KI zusammenfassen", systemImage: "sparkles") { generate() }.disabled(busy || !store.data.aiSettings.enabled)
                    if busy { ProgressView() }
                    if let error { Text(error).foregroundStyle(.orange).font(.caption) }
                    Text("Die KI sieht einen begrenzten Verlauf und die kurze Gesprächsnotiz. Prüfe und bearbeite den Vorschlag. Der vollständige Chat bleibt lokal unter Details erhalten. Neue Einträge, Aufgaben oder Werte werden dadurch nicht erneut angelegt.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Details") { DisclosureGroup("Vollständiges Gespräch · \(messages.count) Nachrichten") { Text(BuddyInteraction.transcript(messages)).font(.subheadline).textSelection(.enabled) } }
                if chat?.savedNoteID != nil { Section { Text("Beim Bestätigen ersetzt diese Vorschau Überschrift, Zusammenfassung und Tags deines bisherigen Gesprächseintrags. Andere Einträge bleiben erhalten.").font(.caption).foregroundStyle(.secondary) } }
            }.navigationTitle("Eintrag prüfen").navigationBarTitleDisplayMode(.inline).buttonStyle(.borderless)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { operation?.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { save() }.bold().disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    title = chat?.title ?? "Mein Gespräch"; tags = AppHashtags.clean(["Tagebuch"] + (chat?.tags ?? []), known: AppHashtags.catalog(store.data))
                    summary = chat?.memory ?? messages.last(where: { $0.role == "assistant" })?.text ?? messages.last?.text ?? ""
                    if store.data.aiSettings.enabled && AIBuddyKeychain.read() != nil { generate() }
                }.onDisappear { operation?.cancel() }
        }
    }
    private func generate() {
        guard !busy, let key = AIBuddyKeychain.read() else { error = "Kein API-Schlüssel hinterlegt. Du kannst den Eintrag selbst bearbeiten."; return }
        busy = true; error = nil
        let captured = messages, memory = chat?.memory ?? "", settings = store.data.aiSettings
        let context = AIBuddyContext(start: chat?.createdAt ?? Date(), end: Date(), days: 1, recordCount: captured.count, omittedCount: 0, text: "VERLAUF:\n" + BuddyInteraction.boundedTranscript(captured, limit: 10000) + "\nGESPRÄCHSNOTIZ:\n" + String(memory.prefix(1800)) + "\nBEKANNTE TAGS: " + AppHashtags.catalog(store.data).prefix(80).joined(separator: ", "))
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await AIBuddyAPI().answer(question: "Erstelle einen zusammenhängenden kurzen Tagebucheintrag aus diesem gesamten Gespräch mit passender Überschrift und 3–8 konkreten tags. Nutzerangaben und KI-Vorschläge unterscheiden. Keine actions, keine Rückfragen, keine Diagnosen. Zusammenfassung in message/sections.", context: context, history: [], settings: settings, key: key)
                try Task.checkCancellation()
                title = AIBuddyText.plain(result.reply.title); summary = result.reply.journalText
                tags = BuddyInteraction.hashtags(["Tagebuch"] + (result.reply.tags ?? []), text: captured.filter { $0.role == "user" }.map(\.text).joined(separator: "\n"), known: AppHashtags.catalog(store.data))
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        guard store.data.aiConversations.contains(where: { $0.id == conversationID }) else { error = "Dieses Gespräch wurde inzwischen entfernt."; return }
        var snapshot = store.data
        AIConversationMutation.saveSummary(conversationID, title: title, summary: summary, tags: tags, in: &snapshot); store.data = snapshot
        if let failure = store.lastSaveError { error = failure } else { dismiss() }
    }
}

struct BuddyWellbeingProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var range = 0
    var body: some View {
        TherapyScreen {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Zeitraum", selection: $range) { Text("Live").tag(0); Text("Heute").tag(1); Text("7 Tage").tag(7) }.pickerStyle(.segmented)
                    profile(now: timeline.date)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Optionale Akku-Schätzung im Tagesverlauf", isOn: $store.data.wellbeingPreferences.estimateBattery)
                            if store.data.wellbeingPreferences.estimateBattery { Stepper("Zeitlicher Verbrauch: \(store.data.wellbeingPreferences.hourlyDecline) Prozentpunkte/Stunde", value: $store.data.wellbeingPreferences.hourlyDecline, in: 0...10) }
                            Text("Die Schätzung beginnt bei deinem letzten heutigen Akkuwert. Bestätigte Akku-Geber/-Nehmer wirken mit 5 Prozentpunkten je Wirkungsstufe; optional kommt der selbst eingestellte zeitliche Verbrauch hinzu. Das ist ein persönliches Planungsmodell, keine Messung. Ohne heutigen Ausgangswert wird nichts geschätzt.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Mit KI über mein Befinden sprechen", systemImage: "sparkles") { showAI = true }.buttonStyle(.bordered).disabled(!store.data.aiSettings.enabled)
                }
            }
        }.navigationTitle("Mein Befinden").sheet(isPresented: $showAI) { AIBuddyEntryView() }
    }
    @State private var showAI = false
    @ViewBuilder private func profile(now: Date) -> some View {
        let start = range == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -(range == 7 ? 6 : 0), to: Calendar.current.startOfDay(for: now)) ?? now
        let period = WellnessPeriod(start: start, end: now.addingTimeInterval(0.001))
        let daily = WellnessAnalytics.daily(store.data, period: period)
        let guided = store.data.guidedCheckIns.filter { !$0.isDraft && $0.date >= start && $0.date <= now }.sorted { $0.date > $1.date }
        let moods = store.data.moodCheckIns.filter { $0.date >= start && $0.date <= now }.sorted { $0.date > $1.date }
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: range == 7 ? "Deine letzten sieben Tage" : "Dein letzter bekannter Stand", icon: "heart.text.clipboard", subtitle: "Nur deine gespeicherten Angaben. Fehlende Werte bleiben offen.")
                if let reading = WellbeingProfile.battery(store.data, now: now, start: start) {
                    let value = range == 7 ? WellnessAnalytics.average(daily.compactMap(\.battery)).map { Int((($0 - 1) * 25).rounded()) } ?? reading.value : WellbeingProfile.estimatedBattery(store.data, reading: reading, now: now)
                    metric("Akku", value: value, maximum: 100, color: BatteryTone.color(value), suffix: "%")
                    Text(range == 7 ? "Mittelwert der erfassten Tage" : (store.data.wellbeingPreferences.estimateBattery && Calendar.current.isDate(reading.date, inSameDayAs: now) ? "Geschätzter Stand · Ausgangswert " : "Selbstberichteter Stand · ") + reading.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                } else { Label("Akku: noch keine Angabe", systemImage: "battery.0percent").foregroundStyle(.secondary) }
                let recentMood = (guided.compactMap { c in c.moodPercent.map { WellbeingReading(date: c.date, value: $0) } ?? c.mood.map { WellbeingReading(date: c.date, value: ($0 - 1) * 25) } } + moods.map { WellbeingReading(date: $0.date, value: $0.moodPercent ?? (($0.mood - 1) * 25)) }).max { $0.date < $1.date }
                if let value = range == 7 ? WellnessAnalytics.average(daily.compactMap(\.mood)).map({ Int((($0 - 1) * 25).rounded()) }) : recentMood?.value { metric("Stimmung", value: value, maximum: 100, color: BatteryTone.color(value), suffix: "/100") }
                let stress = latest(guided.map { ($0.date, $0.stress) } + moods.map { ($0.date, $0.stress) })
                let sensory = latest(guided.map { ($0.date, $0.sensoryLoad) } + moods.map { ($0.date, $0.sensoryLoad) })
                let satisfaction = latest(guided.map { ($0.date, $0.satisfaction) })
                if let value = range == 7 ? WellnessAnalytics.average(daily.compactMap(\.stress)).map({ Int($0.rounded()) }) : stress { metric("Stress", value: value, maximum: 5, color: BatteryTone.burden(value), suffix: "/5") }
                if let value = range == 7 ? WellnessAnalytics.average(daily.compactMap(\.sensory)).map({ Int($0.rounded()) }) : sensory { metric("Reizbelastung", value: value, maximum: 5, color: BatteryTone.burden(value), suffix: "/5") }
                if let value = range == 7 ? WellnessAnalytics.average(guided.compactMap { $0.satisfaction.map(Double.init) }).map({ Int($0.rounded()) }) : satisfaction { metric("Zufriedenheit", value: value, maximum: 5, color: BatteryTone.color((value - 1) * 25), suffix: "/5") }
                Text(range == 7 ? "Durchschnitt erfasster Tageswerte; Zufriedenheit: Durchschnitt deiner Angaben. Hohe Belastung ist rot, hohe Energie grün. Keine medizinische Bewertung." : "Werte können von unterschiedlichen Zeitpunkten stammen und ändern sich erst mit neuen Angaben. Bei Live können auch ältere letzte Angaben erscheinen. Kein automatisch erfundener Gesundheits-Score.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func latest(_ values: [(Date, Int?)]) -> Int? { values.filter { $0.1 != nil }.max { $0.0 < $1.0 }?.1 }
    private func metric(_ title: String, value: Int, maximum: Int, color: Color, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title).font(.subheadline.bold()); Spacer(); Text("\(value)\(suffix)").font(.headline).monospacedDigit() }
            if maximum == 5 { HStack { ForEach(1...5, id: \.self) { dot in Circle().fill(dot <= value ? color : Color.primary.opacity(0.08)).frame(width: 15, height: 15) } }.accessibilityHidden(true) }
            else { ProgressView(value: Double(value), total: Double(maximum)).tint(color) }
        }.accessibilityElement(children: .combine)
    }
}
