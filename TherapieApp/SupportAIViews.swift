import SwiftUI

enum SupportAIPurpose: String, CaseIterable, Identifiable {
    case method, thoughtStop, emergency
    var id: String { rawValue }
    var title: String { switch self { case .method: "Methode entwerfen"; case .thoughtStop: "Gedankenstopp entwerfen"; case .emergency: "Notfallplan entwerfen" } }
}
struct SupportAIProposalView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var purpose: SupportAIPurpose
    @State var category: BatteryCategory = .sensory
    @State var stage: MethodStage = .calm
    var originalMethod: CopingMethod?
    @State private var situation = ""
    @State private var includeContext = false
    @State private var proposal: AIBuddyReply?
    @State private var busy = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var methodDraft: CopingMethod?
    @State private var planDraft: PersonalEmergencyPlan?
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Wunsch") {
                    Picker("Entwurf", selection: $purpose) { ForEach(SupportAIPurpose.allCases) { Text($0.title).tag($0) } }.disabled(busy)
                    TextField("Situation und was dir hilft", text: $situation, axis: .vertical).lineLimit(3...8).disabled(busy)
                    if purpose != .emergency {
                        Picker("Akkuthema", selection: $category) { ForEach(BatteryCategory.allCases) { Text($0.title).tag($0) } }.disabled(busy)
                        Picker("Phase", selection: $stage) { ForEach(MethodStage.allCases) { Text($0.title).tag($0) } }.disabled(busy)
                    }
                    Toggle("Freigegebenen App-Kontext einbeziehen", isOn: $includeContext).disabled(busy)
                    Text(includeContext ? "Dein ausgewählter Zeitraum und die Freigaben des KI-Begleiters gelten. Bilder und Kontaktdaten aus dem Notfallplan werden nicht automatisch gesendet." : "Gesendet werden nur deine Angaben auf dieser Seite, Akkuthema und Phase. Bei einer vorhandenen Methode wird zusätzlich ihr Text übermittelt.").font(.caption).foregroundStyle(.secondary)
                    Button("KI-Vorschlag erstellen", systemImage: "sparkles") { generate() }.disabled(busy || situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || situation.count > 3000)
                    if busy { ProgressView("Dein Entwurf entsteht …"); Button("Anfrage abbrechen") { request?.cancel() } }
                    if !store.data.aiSettings.enabled { Text("Aktiviere den KI-Begleiter im Profil und hinterlege deinen API-Schlüssel. Alle Bereiche kannst du auch selbst ausfüllen.").font(.caption).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if let proposal {
                    Section("Vorschau · noch nicht übernommen") {
                        Text(proposal.title).font(.title2.bold())
                        Text(proposal.message).textSelection(.enabled)
                        ForEach(Array(proposal.sections.enumerated()), id: \.offset) { _, section in VStack(alignment: .leading, spacing: 6) { Text(section.heading).font(.headline); Text(section.text).textSelection(.enabled) } }
                        Text("Prüfe, was für dich passt. Im nächsten Schritt kannst du den Entwurf verändern und speichern.").font(.caption).foregroundStyle(.secondary)
                        Button("Entwurf bearbeiten und übernehmen", systemImage: "pencil") { openDraft(proposal) }.disabled(busy)
                    }
                }
            }.navigationTitle("Mit KI gestalten").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { request?.cancel(); dismiss() } } }
        }.onAppear { if situation.isEmpty, let originalMethod { situation = originalMethod.situation; category = originalMethod.categories.first ?? .sensory; stage = originalMethod.stages.first ?? .calm } }
            .onDisappear { request?.cancel() }
            .sheet(item: $methodDraft) { MethodEditorView(method: $0) }
            .sheet(isPresented: Binding(get: { planDraft != nil }, set: { if !$0 { planDraft = nil } })) { if let planDraft { EmergencyPlanEditorView(plan: planDraft) } }
            .onChange(of: purpose) { _, _ in proposal = nil }
            .onChange(of: situation) { _, _ in proposal = nil }
            .onChange(of: category) { _, _ in proposal = nil }
            .onChange(of: stage) { _, _ in proposal = nil }
    }
    private func generate() {
        guard store.data.aiSettings.enabled, let key = AIBuddyKeychain.read() else { error = "Bitte aktiviere den KI-Begleiter und hinterlege deinen OpenAI-API-Schlüssel im Profil."; return }
        request?.cancel(); busy = true; error = nil; proposal = nil
        let now = Date(), chosenPurpose = purpose
        let question = "Erstelle einen persönlichen, vorsichtigen Entwurf: " + purpose.title + ". Situation: " + situation + ". Akkuthema: " + category.title + ". Phase: " + stage.title
        let settings = store.data.aiSettings
        var context = includeContext ? AIBuddyContext.make(data: store.data, days: settings.contextDays, question: question) : AIBuddyContext(start: now, end: now, days: 1, recordCount: 0, omittedCount: 0, text: "Keine privaten Verlaufsdaten freigegeben.")
        if let originalMethod { context.text = "VORHANDENE METHODE (Nutzerangaben): " + originalMethod.title + "\n" + originalMethod.details + "\n" + originalMethod.steps.joined(separator: "\n") + "\n" + context.text }
        request = Task { @MainActor in
            defer { busy = false }
            do {
                let guide = "\nMETHODEN-ENTWURF: Gib ausschließlich einen kurzen bearbeitbaren Entwurf, keine actions, keine checkIn-Steuerung. Bei Notfallplan: message genau ein kleiner erster Schritt, sections zwei bis vier konkrete kurze weitere Schritte mit Überschrift. Keine Kontakte, Telefonnummern oder Symptome erfinden. Bei Methode: title Methodenname, message kurze Erklärung oder persönlicher Stoppsatz, sections einzelne kleine Schritte. Nichts als garantiert wirksam behaupten. Keine unangenehmen Reize verlangen, Alternativen und Stoppen erlauben. ASMR nur leise und wenn angenehm. Keine Empfehlung, Gedanken mit Zwang zu unterdrücken. Keine Diagnose."
                let result = try await AIBuddyAPI().answer(question: question, context: context, history: [], settings: settings, key: key, guide: guide)
                try Task.checkCancellation()
                guard purpose == chosenPurpose else { return }; proposal = result.reply
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func openDraft(_ reply: AIBuddyReply) {
        let steps = reply.sections.map { $0.heading + ": " + $0.text }
        if purpose == .emergency {
            var draft = store.data.emergencyPlan; draft.firstStep = AIBuddyText.plain(reply.message); draft.steps = steps.map(AIBuddyText.plain); planDraft = draft
        } else {
            var draft = originalMethod ?? CopingMethod()
            draft.title = AIBuddyText.plain(reply.title); draft.kind = purpose == .thoughtStop ? .thoughtStop : .method; draft.situation = situation
            draft.details = AIBuddyText.plain(reply.message); draft.steps = steps.map(AIBuddyText.plain)
            if originalMethod == nil { draft.categories = [category]; draft.stages = [stage] }
            methodDraft = draft
        }
    }
}

struct GroundingHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var deleting: UUID?
    var body: some View {
        List {
            if store.data.groundingPractices.isEmpty { ContentUnavailableView("Noch keine gespeicherte Übung", systemImage: "leaf") }
            ForEach(store.data.groundingPractices.sorted { $0.date > $1.date }) { practice in
                Section(practice.date.formatted(date: .abbreviated, time: .shortened)) {
                    ForEach(Array(practice.answers.prefix(5).enumerated()), id: \.offset) { index, answers in
                        if !answers.isEmpty { VStack(alignment: .leading, spacing: 5) { Text(GroundingGuide.titles[index]).font(.headline); Text(answers.joined(separator: " · ")) } }
                    }
                    if !practice.note.isEmpty { Text(practice.note) }
                    Button("Übung löschen", role: .destructive) { deleting = practice.id }
                }
            }
        }.navigationTitle("Meine Übungen").navigationBarTitleDisplayMode(.inline)
            .alert("Gespeicherte Übung löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Abbrechen", role: .cancel) { deleting = nil }; Button("Löschen", role: .destructive) { if let deleting { store.data.groundingPractices.removeAll { $0.id == deleting } }; deleting = nil } }
    }
}
