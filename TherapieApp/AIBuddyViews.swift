import SwiftUI
import PhotosUI
import UIKit

struct AIBuddyView: View {
    @EnvironmentObject private var store: AppStore
    var inSession = false
    @State private var settings = false
    @State private var active: UUID?
    @State private var deleting: AIBuddyConversation?
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 16) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Deine Gespräche", icon: "bubble.left.and.bubble.right", subtitle: "Ein eigener Raum für jeden Gedanken. Deine Chats werden hier und in deinen Backups gespeichert. Beim Senden wird der angezeigte Kontext an OpenAI übertragen.")
                        if store.data.aiSettings.enabled {
                            Button("Neues Gespräch", systemImage: "square.and.pencil") { newChat() }.buttonStyle(.borderedProminent).accessibilityIdentifier("ai.new.chat")
                            NavigationLink { TherapyJournalView() } label: { Label("Therapietagebuch", systemImage: "book.closed") }
                        } else { Button("KI einrichten", systemImage: "key") { settings = true } }
                    }
                }
                ForEach(store.data.aiConversations.sorted { $0.updatedAt > $1.updatedAt }) { chat in
                    NavigationLink { AIBuddyChatContent(controller: store.aiController, inSession: inSession, conversationID: chat.id) } label: {
                        GlassCard { HStack { Image(systemName: chat.checkInID == nil ? "bubble.left.and.bubble.right.fill" : "sparkles").foregroundStyle(.indigo); VStack(alignment: .leading, spacing: 6) { Text(chat.title).font(.headline).lineLimit(2); Text(chat.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) } }
                    }.buttonStyle(.plain).contextMenu { Button("Gespräch löschen", systemImage: "trash", role: .destructive) { deleting = chat } }.accessibilityIdentifier("ai.chat." + chat.id.uuidString)
                }
            }
        }.buttonStyle(.borderless).navigationTitle("KI-Begleiter")
            .navigationDestination(isPresented: Binding(get: { active != nil }, set: { if !$0 { active = nil } })) { if let active { AIBuddyChatContent(controller: store.aiController, inSession: inSession, conversationID: active) } }
            .sheet(isPresented: $settings) { AIBuddySettingsView() }
            .alert("Gespräch löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Abbrechen", role: .cancel) { deleting = nil }
                Button("Löschen", role: .destructive) { if let deleting { store.aiController.cancel(); var snapshot = store.data; AIConversationMutation.delete(deleting.id, in: &snapshot); store.data = snapshot }; deleting = nil }
            } message: { Text("Gespeicherte Tagebucheinträge und Check-ins bleiben erhalten. Rückgängig ist zehn Minuten lang in der geöffneten App möglich.") }
            .onAppear { if ProcessInfo.processInfo.arguments.contains("--buddy-fixture"), active == nil { active = store.data.aiConversations.first?.id } }
    }
    private func newChat() { var snapshot = store.data; let id = AIConversationMutation.create(in: &snapshot); store.data = snapshot; if store.lastSaveError == nil { active = id } }
}
/// A contextual entry point used from notes, the home screen and check-ins.
struct AIBuddyEntryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var checkIn: GuidedCheckIn? = nil
    var note: TherapyNote? = nil
    var onNoteProposal: ((TherapyNote) -> Void)? = nil
    @State private var conversationID: UUID?
    var body: some View {
        NavigationStack {
            Group {
                if let conversationID { AIBuddyChatContent(controller: store.aiController, inSession: store.data.currentSession != nil, conversationID: conversationID, onNoteProposal: onNoteProposal, close: { dismiss() }) }
                else { ProgressView("Gespräch vorbereiten …") }
            }
        }.onAppear {
            guard conversationID == nil else { return }
            var snapshot = store.data; let id = AIConversationMutation.create(in: &snapshot, checkIn: checkIn, note: note); store.data = snapshot
            if store.lastSaveError == nil { conversationID = id }
        }
    }
}
private struct AIBuddyReviewRoute: Identifiable {
    var id: String { messageID.uuidString + action.id }
    var messageID: UUID
    var action: AIBuddyAction
}
private enum BuddySheet: Identifiable {
    case settings, guided(GuidedCheckIn), manual(GuidedCheckIn), review(AIBuddyReviewRoute), voice, screen(String)
    var id: String {
        switch self { case .settings: "settings"; case .guided(let c): "guided-" + c.id.uuidString; case .manual(let c): "manual-" + c.id.uuidString; case .review(let r): "review-" + r.id; case .voice: "voice"; case .screen(let name): "screen-" + name }
    }
}
struct AIBuddyChatContent: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @ObservedObject var controller: AIBuddyController
    var inSession: Bool
    var conversationID: UUID
    var onNoteProposal: ((TherapyNote) -> Void)? = nil
    var close: (() -> Void)? = nil
    @State private var route: BuddySheet?
    @State private var confirmExit = false
    @State private var sending = false
    @State private var retryImage: Data?
    @State private var initialized = false
    @StateObject private var inputHandle = ChatComposerHandle()
    @State private var visibilityID = UUID()
    @State private var previewContext: AIBuddyContext?
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: Data?
    @State private var confirmPhoto = false
    @State private var clearChat = false
    @State private var confirmSaveChat = false
    @State private var moreMessages = false
    @State private var explicitDays: Int?
    private var chat: AIBuddyConversation? { store.data.aiConversations.first { $0.id == conversationID } }
    private var messages: [AIBuddyMessage] { store.data.aiMessages.filter { $0.conversationID == conversationID } }
    private var draft: GuidedCheckIn? { chat?.checkInID.flatMap { id in store.data.guidedCheckIns.first { $0.id == id && $0.isDraft } } }
    private var context: AIBuddyContext { previewContext ?? AIBuddyContext(start: Date(), end: Date(), days: 7, recordCount: 0, omittedCount: 0, text: "") }
    var body: some View {
        ScrollViewReader { proxy in
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 16) {
                if chat == nil { ContentUnavailableView("Gespräch gelöscht", systemImage: "bubble.left.and.bubble.right") }
                else if messages.isEmpty { introduction }
                if let draft { guideHeader(draft) }
                if store.data.aiSettings.enabled { DisclosureGroup("Kontext für deine nächste Nachricht") { contextCard } }
                    ForEach(Array(moreMessages ? messages : Array(messages.suffix(40)))) { message in messageCard(message).id(message.id) }
                    if messages.count > 40 && !moreMessages { Button("Frühere Nachrichten anzeigen") { moreMessages = true } }
                    if controller.busy {
                        HStack { BuddyTypingBubble(); Button("Anfrage abbrechen", systemImage: "xmark.circle") { controller.cancel() }.labelStyle(.iconOnly).foregroundStyle(.secondary); Spacer() }.id("buddy.typing")
                    }
                    if let error = controller.error { GlassCard { VStack(alignment: .leading, spacing: 8) { Text(error).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled); if let last = messages.last, last.role == "user" { Button("Antwort erneut versuchen", systemImage: "arrow.clockwise") { send(questionOverride: last.text, pictureOverride: retryImage) }.disabled(controller.busy || sending) } } } }
            }
        }.onAppear {
            if let id = messages.last?.id { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) } }
        }.onChange(of: messages.count) { _, _ in
            if let id = messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
            updateContext()
        }.onChange(of: controller.busy) { _, busy in if busy { withAnimation { proxy.scrollTo("buddy.typing", anchor: .bottom) } } }
        }.buttonStyle(.borderless).navigationTitle(chat?.title ?? "Gespräch").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .safeAreaInset(edge: .bottom) { if store.data.aiSettings.enabled && chat != nil { composer.padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(close == nil ? "Zurück" : "Schließen", systemImage: "chevron.left") { requestClose() }.accessibilityIdentifier("ai.chat.close") }
                ToolbarItem(placement: .topBarTrailing) { if store.undoAvailable { Button("Letzte Eingabe rückgängig", systemImage: "arrow.uturn.backward") { inputHandle.finishEditing(); store.undoLastChange() }.accessibilityIdentifier("ai.undo") } }
                ToolbarItem(placement: .topBarTrailing) { if let draft { Button(draft.step == 7 ? "Übersicht" : "Normal", systemImage: "slider.horizontal.3") { controller.cancel(); inputHandle.finishEditing(); route = .manual(draft) }.accessibilityIdentifier("ai.checkin.toolbar.manual") } }
                ToolbarItem(placement: .topBarTrailing) { Menu { Button("KI-Einstellungen", systemImage: "slider.horizontal.3") { inputHandle.finishEditing(); route = .settings }; Button("Gespräch im Tagebuch speichern", systemImage: "book.closed") { confirmSaveChat = true }; Button("Gespräch löschen", systemImage: "trash", role: .destructive) { clearChat = true } } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("ai.chat.menu") } }
            .sheet(item: $route) { destination in
                switch destination {
                case .settings: AIBuddySettingsView()
                case .guided(let entry): GuidedCheckInDestination(entry: entry)
                case .manual(let entry): GuidedCheckInView(entry: entry)
                case .review(let review): AIBuddyActionReviewView(action: review.action, messageID: review.messageID)
                case .voice: AIBuddyVoiceView { transcript in text = transcript }
                case .screen(let name): NavigationStack { self.destination(name).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { route = nil } } } }
                }
            }
            .alert("Eingabe behalten?", isPresented: $confirmExit) {
                Button("Weiter schreiben", role: .cancel) {}
                Button("Als Entwurf speichern") { finishClose(saveDraft: true) }
                Button("Verwerfen", role: .destructive) { finishClose(saveDraft: false) }
            } message: { Text("Deine bereits gesendeten Nachrichten bleiben erhalten. Du entscheidest über den noch nicht gesendeten Text.") }
            .onChange(of: photo) { _, value in if value != nil { confirmPhoto = true } }
            .alert("Ausgewähltes Foto an OpenAI senden?", isPresented: $confirmPhoto) {
                Button("Abbrechen", role: .cancel) { photo = nil; image = nil }
                Button("Für nächste Nachricht vorbereiten") { Task { await preparePhoto() } }
            } message: { Text("Das Foto wird auf höchstens 1.024 Pixel verkleinert und beim nächsten Senden hochgeladen. Es kann persönliche Informationen enthalten. Die Bildanalyse verursacht zusätzliche API-Kosten. Andere Archivbilder werden nicht übertragen.") }
            .alert("Gespräch im Tagebuch speichern?", isPresented: $confirmSaveChat) {
                Button("Abbrechen", role: .cancel) {}
                Button("Speichern") { var snapshot = store.data; AIConversationMutation.save(conversationID, in: &snapshot); store.data = snapshot }
            } message: { Text(chat?.savedNoteID == nil ? "Dein vollständiger Verlauf wird als bearbeitbarer Tagebucheintrag gespeichert." : "Der zuvor gespeicherte Tagebucheintrag wird mit dem vollständigen aktuellen Gespräch aktualisiert. Auch eigene Änderungen an diesem Eintrag werden dabei ersetzt.") }
            .alert("Chatverlauf leeren?", isPresented: $clearChat) { Button("Abbrechen", role: .cancel) {}; Button("Leeren", role: .destructive) { controller.cancel(); var snapshot = store.data; AIConversationMutation.delete(conversationID, in: &snapshot); store.data = snapshot } } message: { Text("Gespeicherte Tagebucheinträge bleiben erhalten. Rückgängig ist zehn Minuten lang in der geöffneten App möglich.") }
            .onAppear { store.visibleAIComposerIDs.insert(visibilityID); if !initialized { text = chat?.draftText ?? ""; initialized = true; controller.error = nil }; updateContext() }
            .onChange(of: text) { _, _ in updateContext(onlyIfRangeChanged: true) }
            .onDisappear { store.visibleAIComposerIDs.remove(visibilityID); if route == nil { inputHandle.finishEditing(); controller.cancel(); cleanupEmptyChat() } }
            .onChange(of: store.data.aiSettings.enabled) { _, enabled in if !enabled { controller.cancel(); image = nil; photo = nil } }
    }
    private var introduction: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: inSession ? "Ein Gedanke während der Stunde" : "Was geht dir heute durch den Kopf?", icon: "sparkles", subtitle: "Gemeinsam reflektieren, sortieren und passende Einträge vorbereiten.")
                if !store.data.aiSettings.enabled { Button("Optionalen KI-Begleiter einrichten", systemImage: "key") { route = .settings }.buttonStyle(.borderedProminent) }
                else {
                    ScrollView(.horizontal, showsIndicators: false) { HStack {
                        prompt("Tagesrückblick", question: "Fasse meinen heutigen Tag mit Stimmungen und Einträgen knapp zusammen.", days: 1)
                        prompt("Wochenrückblick", question: "Erstelle einen Wochenrückblick für die letzten 7 Tage: Stimmung, Energie, hilfreiche Momente, offene Themen und einen kleinen nächsten Schritt.", days: 7)
                        prompt("Neuer Eintrag", question: "Ich möchte einen neuen Eintrag machen. Frage mich kurz, was ich festhalten möchte, und biete Stimmung, Notiz und Therapiethema als passende Aktionen an.", days: nil)
                    } }
                    if draft == nil { checkInSuggestions }
                    NavigationLink { TherapyJournalView() } label: { Label("Mein Therapietagebuch", systemImage: "book.closed") }.font(.subheadline)
                }
            }
        }
    }
    private func prompt(_ title: String, question: String, days: Int?) -> some View { Button(title) { text = question; explicitDays = days }.buttonStyle(.bordered).disabled(controller.busy) }
    private var contextCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Dein sichtbarer Datenzeitraum", systemImage: "calendar").font(.subheadline.bold())
                let selection = Binding<Int>(get: { explicitDays ?? chat?.contextDays ?? 0 }, set: { setDays($0 == 0 ? nil : $0); persistDays(); updateContext() })
                Picker("Kontext", selection: selection) { Text("Aus Frage / Standard").tag(0); Text("Heute").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90); if let days = explicitDays ?? chat?.contextDays, ![1, 7, 30, 90].contains(days) { Text("\(days) Tage").tag(days) } }
                Text(context.start.formatted(date: .abbreviated, time: .omitted) + " – " + context.end.formatted(date: .abbreviated, time: .omitted) + " · \(context.recordCount) Text-Einträge").font(.caption).foregroundStyle(.secondary)
                if context.omittedCount > 0 { Text("\(context.omittedCount) Einträge werden wegen des Textlimits ausgelassen; neuere haben Vorrang.").font(.caption).foregroundStyle(.secondary) }
                Text("Zusätzlich: aktuelle offene Aufgaben, fällige Routinen und offene Gesprächspunkte, auch ältere. Der Chat berücksichtigt die letzten 8 Nachrichten. Bilder nur nach deiner Auswahl.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func messageCard(_ message: AIBuddyMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 12) {
                Label(message.role == "user" ? "Du" : "Dein Begleiter", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles").font(.caption.bold()).foregroundStyle(.secondary)
                if let reply = message.reply {
                    if !reply.title.isEmpty { Text(AIBuddyText.plain(reply.title)).font(.headline) }
                    formatted(reply.message)
                    ForEach(Array(reply.sections.enumerated()), id: \.offset) { _, section in VStack(alignment: .leading, spacing: 5) { Text(AIBuddyText.plain(section.heading)).font(.subheadline.bold()); formatted(section.text) } }
                    ForEach(reply.actions) { action in
                        let applied = message.appliedActionIDs.contains(action.id)
                        Button {
                            if action.kind == .openScreen { open(action.targetID ?? "") }
                            else if action.kind == .guidedCheckIn { startCheckIn(target: action.targetID) }
                            else { inputHandle.finishEditing(); route = .review(.init(messageID: message.id, action: action)) }
                        } label: { Label(applied ? "Gespeichert · " + action.kind.label : action.kind.label + (action.title.isEmpty ? "" : ": " + AIBuddyText.plain(action.title)), systemImage: applied ? "checkmark.circle.fill" : action.kind.symbol).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered).disabled(applied).accessibilityIdentifier("ai.action." + action.kind.rawValue)
                    }
                    if let days = reply.suggestedDays { Button("Mehr Kontext? \(days) Tage für die nächste Nachricht") { setDays(days); persistDays(); updateContext() }.font(.caption) }
                    if message.id == messages.last?.id {
                        VStack(alignment: .leading) {
                            Text("Für die nächste Nachricht: \(explicitDays ?? chat?.contextDays ?? store.data.aiSettings.contextDays) Tage").font(.caption)
                            Slider(value: Binding(get: { Double(explicitDays ?? chat?.contextDays ?? store.data.aiSettings.contextDays) }, set: { setDays(Int($0)) }), in: 1...90, step: 1, onEditingChanged: { editing in if !editing { persistDays(); updateContext() } }).accessibilityLabel("Kontext in Tagen")
                            Button("Zeitraum wieder aus Nachricht erkennen") { setDays(nil); persistDays(); updateContext() }.font(.caption)
                        }
                        if draft == nil { checkInSuggestions }
                        quickPrompts
                        if let note = chat?.noteContext, let onNoteProposal {
                            Button("Textvorschlag in meine Notiz übernehmen", systemImage: "pencil") { var proposal = note; proposal.title = AIBuddyText.plain(reply.title); proposal.text = reply.journalText; proposal.tags = AppHashtags.clean(reply.actions.flatMap { $0.tags ?? [] } + note.tags, known: AppHashtags.catalog(store.data)); onNoteProposal(proposal) }.buttonStyle(.bordered)
                        }
                    }
                    Button(message.savedNoteID == nil ? "Rückblick im Tagebuch speichern" : "Im Tagebuch gespeichert", systemImage: "book.closed") { controller.saveReply(message) }.buttonStyle(.bordered).disabled(message.savedNoteID != nil).accessibilityIdentifier("ai.save.summary")
                    if let start = message.contextStart, let end = message.contextEnd { Text("Kontext " + start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary) }
                    if let input = message.inputTokens, let output = message.outputTokens { Text("\(message.model ?? "OpenAI") · letzte Antwort: \(input) Eingabe- / \(output) Ausgabetokens. Eventuelle Wiederholungen kommen hinzu.").font(.caption2).foregroundStyle(.secondary) }
                } else { Text(message.text).font(.subheadline).textSelection(.enabled) }
                Text(message.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }.padding(16).background(message.role == "user" ? Color.indigo.opacity(0.14) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
            if message.role != "user" { Spacer(minLength: 16) }
        }
    }
    private func formatted(_ value: String) -> some View {
        let text = (try? AttributedString(markdown: value.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(AIBuddyText.plain(value))
        return Text(text).font(.subheadline).textSelection(.enabled)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if image != nil { HStack { Label("Foto vorbereitet", systemImage: "photo"); Spacer(); Button("Entfernen") { image = nil; photo = nil } }.font(.caption) }
            HStack(alignment: .bottom, spacing: 10) {
                if store.data.aiSettings.allowVoiceUploads { Button { inputHandle.finishEditing(); route = .voice } label: { Image(systemName: "mic") }.accessibilityLabel("Einsprechen").frame(minWidth: 44, minHeight: 44) }
                if store.data.aiSettings.allowPhotoUploads { PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }.accessibilityLabel("Foto auswählen").frame(minWidth: 44, minHeight: 44) }
                ChatComposerInput(text: $text, handle: inputHandle)
                    .overlay(alignment: .topLeading) { if text.isEmpty { Text("Nachricht …").foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 11).allowsHitTesting(false).accessibilityHidden(true) } }
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)).foregroundStyle(.indigo) }.accessibilityLabel("Senden").disabled(sending || controller.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 5000 || draft?.step == 7).accessibilityIdentifier("ai.send")
            }
            if text.count > 4800 { Text("\(text.count) / 5.000 Zeichen").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func send(questionOverride: String? = nil, pictureOverride: Data? = nil) {
        guard !controller.busy, !sending else { return }
        inputHandle.finishEditing()
        let question = questionOverride ?? inputHandle.currentText ?? text
        let picture = pictureOverride ?? image
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            _ = await controller.send(question, image: picture, inSession: inSession, daysOverride: explicitDays, conversationID: conversationID, onAccepted: {
                if questionOverride == nil { _ = inputHandle.clearIfUnchanged(question); text = "" }
                retryImage = picture
                if image == picture { image = nil; photo = nil }
            })
            updateContext()
        }
    }
    private func requestClose() {
        inputHandle.finishEditing()
        text = inputHandle.currentText ?? text
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { confirmExit = true }
        else { finishClose(saveDraft: false) }
    }
    private func finishClose(saveDraft: Bool) {
        controller.cancel()
        var snapshot = store.data
        if let index = snapshot.aiConversations.firstIndex(where: { $0.id == conversationID }) {
            snapshot.aiConversations[index].draftText = saveDraft ? text : nil
        }
        if !saveDraft { AIConversationMutation.removeIfEmpty(conversationID, in: &snapshot) }
        store.data = snapshot
        guard store.lastSaveError == nil else { return }
        text = ""; close?(); if close == nil { dismiss() }
    }
    private func cleanupEmptyChat() {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var snapshot = store.data; AIConversationMutation.removeIfEmpty(conversationID, in: &snapshot)
        if snapshot != store.data { store.data = snapshot }
    }
    private func setDays(_ days: Int?) {
        explicitDays = days
    }
    private func persistDays() {
        guard let index = store.data.aiConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        store.data.aiConversations[index].contextDays = explicitDays
    }
    private func updateContext(onlyIfRangeChanged: Bool = false) {
        let days = AIBuddyContext.requestDays(question: text, settings: store.data.aiSettings, chosenDays: explicitDays ?? chat?.contextDays)
        if onlyIfRangeChanged, previewContext?.days == days { return }
        previewContext = AIBuddyContext.make(data: store.data, days: days)
    }
    private func startCheckIn(target: String? = nil) {
        let slots = DayCheckInPolicy.slots(store.data.companionSettings).filter { $0.enabled }
        if let target, UUID(uuidString: target) != nil, !slots.contains(where: { $0.id.uuidString == target }) { controller.error = "Dieses Check-in-Fenster ist nicht mehr eingerichtet."; return }
        let selected = slots.first { $0.id.uuidString == target } ?? slots.first { $0.contains(Date()) }
        let proposed = target == "free" ? GuidedCheckIn(kind: .free) : selected.map { DayCheckInPolicy.entry($0) } ?? GuidedCheckIn(kind: .free)
        let entry = DayCheckInPolicy.reopen(proposed, in: store.data)
        if entry.id == proposed.id, let selected, target != "free", !selected.contains(Date()) { controller.error = "Dieser Check-in liegt außerhalb seines Zeitfensters."; return }
        inputHandle.finishEditing(); route = .guided(entry)
    }
    private var checkInSuggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deine Check-ins heute").font(.caption.bold())
            ForEach(DayCheckInPolicy.slots(store.data.companionSettings).filter { $0.enabled }) { slot in
                let existing = DayCheckInPolicy.existing(for: DayCheckInPolicy.entry(slot), in: store.data)
                Button {
                    startCheckIn(target: slot.id.uuidString)
                } label: { Label(slot.title + (existing.map { $0.isDraft ? " · fortsetzen" : " · ansehen" } ?? ""), systemImage: existing?.isDraft == false ? "checkmark.circle.fill" : slot.kind.symbol) }
                    .buttonStyle(.bordered).disabled(existing == nil && !slot.contains(Date()))
            }
        }
    }
    private var quickPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack {
            prompt("Tag zusammenfassen", question: "Fasse meinen heutigen Tag zusammen. Was gab mir Akku, was nahm mir Akku? Biete passende prüfbare Einträge an.", days: 1)
            prompt("Woche zusammenfassen", question: "Fasse meine letzten 7 Tage zusammen und hilf mir mit einem kleinen nächsten Schritt.", days: 7)
            prompt("Tagesstruktur", question: "Hilf mir Schritt für Schritt mit einer realistischen Tagesstruktur. Berücksichtige meine Energie und Termine. Frage zuerst, was ich heute brauche.", days: nil)
        } }
    }
    private func guideHeader(_ entry: GuidedCheckIn) -> some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                Label("KI-geführter Check-in · \(entry.step + 1) / 8", systemImage: "sparkles").font(.headline)
                ProgressView(value: Double(entry.step + 1), total: 8)
                Text(AICheckInGuide.questions[max(0, min(7, entry.step))]).font(.subheadline)
                HStack {
                    Button(entry.step == 7 ? "Übersicht prüfen & abschließen" : "Normal fortsetzen", systemImage: "slider.horizontal.3") { controller.cancel(); inputHandle.finishEditing(); route = .manual(entry) }.accessibilityIdentifier("ai.checkin.manual")
                    if entry.step < 7 { Button("Überspringen") { controller.cancel(); var snapshot = store.data; var next = entry; next.step += 1; _ = GuidedCheckInMutation.apply(next, complete: false, to: &snapshot); snapshot.aiMessages.append(AIBuddyMessage(role: "assistant", text: AICheckInGuide.questions[next.step], conversationID: conversationID)); store.data = snapshot } }
                }.buttonStyle(.bordered)
                HashtagChips(tags: entry.tags ?? [])
            }
        }
    }
    private func preparePhoto() async {
        do {
            guard let raw = try await photo?.loadTransferable(type: Data.self), let original = UIImage(data: raw) else { throw AIBuddyAPIError(message: "Das Bild konnte nicht geöffnet werden.") }
            let scale = min(1, 1024 / max(original.size.width, original.size.height))
            let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
            guard let bytes = resized.jpegData(compressionQuality: 0.7), bytes.count <= 2_000_000 else { throw AIBuddyAPIError(message: "Das Bild ist zu groß.") }
            image = bytes
        } catch { controller.error = error.localizedDescription; photo = nil }
    }
    private func open(_ screen: String) {
        guard ["today", "insights", "therapy", "archive", "session", "routines", "appointments", "reminders"].contains(screen) else { controller.error = "Dieser Bereich ist nicht bekannt. Wähle ihn über die App-Navigation."; return }
        inputHandle.finishEditing(); route = .screen(screen)
    }
    @ViewBuilder private func destination(_ name: String) -> some View {
        switch name {
        case "insights": InsightsHubView()
        case "therapy": TherapyHubView()
        case "archive": LibraryView()
        case "session": SessionConductorView()
        case "routines": RoutineHubView()
        case "appointments": TherapyAppointmentsView()
        case "reminders": ReminderCenterView()
        default: DashboardView()
        }
    }
}

struct AIBuddyActionReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let original: AIBuddyAction
    let messageID: UUID
    @State private var action: AIBuddyAction
    @State private var date: Date
    @State private var percent: Int
    @State private var error: String?
    @State private var baseline: Data?
    @State private var hasBaseline = false
    @State private var hasDate: Bool
    init(action: AIBuddyAction, messageID: UUID) { original = action; self.messageID = messageID; _action = State(initialValue: action); _date = State(initialValue: action.date ?? Date()); _percent = State(initialValue: action.moodPercent ?? 50); _hasDate = State(initialValue: action.date != nil) }
    private var completion: Bool { [.completeTask, .completeRoutine].contains(action.kind) }
    private var removing: Bool { [.deleteTask, .deleteRoutine].contains(action.kind) }
    private var modifying: Bool { [.updateTask, .updateRoutine, .setting].contains(action.kind) }
    private var settingsAction: Bool { action.kind == .setting }
    private var recurring: Bool { [.task, .routine, .updateRoutine, .updateTask].contains(action.kind) }
    private var options: Binding<AIBuddyActionOptions> { Binding(get: { action.options ?? AIBuddyActionOptions() }, set: { action.options = $0 }) }
    private var canSave: Bool { action.valid && (completion || removing || settingsAction || !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Vorschlag · bitte prüfen") {
                    Label(action.kind.label, systemImage: action.kind.symbol)
                    if completion { Text("Bestätige nur, wenn du diese Aufgabe oder Routine wirklich erledigt hast.").font(.headline) }
                    if !removing && !settingsAction {
                        TherapyInputField(title: "Überschrift", multiline: false, text: $action.title)
                        TherapyInputField(title: "Text", text: $action.text)
                    }
                    if removing { Label("Dieser Eintrag wird entfernt. Verlauf und andere Einträge bleiben erhalten.", systemImage: "trash").foregroundStyle(.orange); Text(action.title).font(.headline) }
                    if modifying || removing { Text("Bisher: " + previousDescription).font(.caption).foregroundStyle(.secondary) }
                    if [.note, .checkIn].contains(action.kind) { HashtagEditor(tags: Binding(get: { action.tags ?? [] }, set: { action.tags = $0 })) }
                }
                if settingsAction {
                    Section("Änderung prüfen") {
                        Text(action.targetID ?? "")
                        if action.targetID == "ai.contextDays" { Stepper("Neu: \(action.options?.valueInt ?? 7) Tage", value: Binding(get: { action.options?.valueInt ?? 7 }, set: { options.wrappedValue.valueInt = $0 }), in: 1...90) }
                        else { Toggle("Neuer Wert", isOn: Binding(get: { action.options?.valueBool ?? false }, set: { options.wrappedValue.valueBool = $0 })) }
                    }
                }
                if !completion && !removing && !settingsAction {
                    Section("Datum & Einordnung") {
                        if [.task, .updateTask, .updateRoutine, .goal].contains(action.kind) { Toggle("Zeitpunkt ändern / festlegen", isOn: $hasDate) }
                        if hasDate || [.routine, .appointment].contains(action.kind) { DatePicker("Zeitpunkt", selection: $date) }
                        if [.mood, .checkIn].contains(action.kind) {
                            MoodBarometerControl(percent: $percent)
                            Text(original.moodPercent == nil ? "Die KI hat keine Stimmung festgelegt. Wähle deinen eigenen Wert." : "Die KI hat diesen Wert vorgeschlagen. Du kannst ihn frei ändern.").font(.caption).foregroundStyle(.secondary)
                        }
                        if recurring { WeekdaySelection(days: $action.weekdays); Text("Routine: keine Auswahl = täglich. Aufgabe: keine Auswahl = Wochentag des Termins. Die Uhrzeit stammt aus dem Zeitpunkt oben.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if recurring && !removing {
                    Section("Erinnerung & Wiederholung") {
                        Toggle("Erinnerungen anpassen", isOn: Binding(get: { action.options?.remindersEnabled != nil }, set: { options.wrappedValue.remindersEnabled = $0 ? true : nil }))
                        if action.options?.remindersEnabled != nil {
                            Toggle("Erinnern", isOn: Binding(get: { action.options?.remindersEnabled ?? true }, set: { options.wrappedValue.remindersEnabled = $0 }))
                            Toggle("AlarmKit anpassen", isOn: Binding(get: { action.options?.alarmEnabled != nil }, set: { options.wrappedValue.alarmEnabled = $0 ? false : nil }))
                            if action.options?.alarmEnabled != nil { Toggle("AlarmKit-Wecker", isOn: Binding(get: { action.options?.alarmEnabled ?? false }, set: { options.wrappedValue.alarmEnabled = $0 })) }
                        }
                        if [.routine, .updateRoutine].contains(action.kind) {
                            if let retry = action.options?.retryMinutes { Stepper("Erneut nach \(retry) Minuten", value: Binding(get: { action.options?.retryMinutes ?? 20 }, set: { options.wrappedValue.retryMinutes = $0 }), in: 5...180, step: 5) }
                            if action.options?.enabled != nil { Toggle("Routine aktiv", isOn: Binding(get: { action.options?.enabled ?? true }, set: { options.wrappedValue.enabled = $0 })) }
                        }
                        if action.kind == .task || action.kind == .routine {
                            Toggle("Wöchentlich wiederholen", isOn: Binding(get: { action.options?.repeatEveryWeeks != nil }, set: { options.wrappedValue.repeatEveryWeeks = $0 ? 1 : nil; if $0 && action.kind == .task { options.wrappedValue.repeatCount = action.options?.repeatCount ?? 1; hasDate = true } }))
                        }
                        if action.options?.repeatEveryWeeks != nil {
                            Stepper("Alle \(action.options?.repeatEveryWeeks ?? 1) Wochen", value: Binding(get: { action.options?.repeatEveryWeeks ?? 1 }, set: { options.wrappedValue.repeatEveryWeeks = $0 }), in: 1...52)
                            if action.kind == .task || action.options?.repeatCount != nil { Stepper("\(action.options?.repeatCount ?? 1) \(action.kind == .task ? "Aufgaben" : "aktive Wochen")", value: Binding(get: { action.options?.repeatCount ?? 1 }, set: { options.wrappedValue.repeatCount = $0 }), in: 1...52) }
                            Text(action.kind == .task ? "Legt die angezeigte Anzahl separater Aufgaben an. Jede wird in ihrer Woche aktiv und kann einzeln erledigt werden." : "Ausgewählte Tage gelten in jeder aktiven Woche. Ohne Anzahl läuft die Routine unbegrenzt.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section { Text("Speichert einen regulären App-Eintrag, inklusive Backup, Export und Rückgängig-Funktion.").font(.caption).foregroundStyle(.secondary) }
            }.buttonStyle(.borderless).navigationTitle(removing ? "Entfernen prüfen" : completion ? "Wirklich erledigt?" : "KI-Vorschlag bearbeiten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(removing ? "Ja, entfernen" : completion ? "Ja, erledigt" : modifying ? "Änderung übernehmen" : "Speichern") { save() }.bold().disabled(!canSave) }
                }
        }.onAppear { if !hasBaseline { baseline = AIBuddyMutation.targetSnapshot(original, in: store.data); hasBaseline = true } }
    }
    private var previousDescription: String {
        if action.kind == .setting { return AIBuddySettingsChange.value(action.targetID ?? "", data: store.data) }
        let id = action.targetID.flatMap(UUID.init(uuidString:))
        if let task = store.data.weeklyTasks.first(where: { $0.id == id }) { return task.title + " · " + task.details + " · " + (task.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "Kein Termin") }
        if let routine = store.data.routines.first(where: { $0.id == id }) { return routine.title + " · " + routine.details + " · " + routine.times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ", ") }
        return "Eintrag nicht mehr vorhanden"
    }
    private func save() {
        do {
            var clean = action
            if modifying || removing {
                guard baseline == AIBuddyMutation.targetSnapshot(original, in: store.data) else { error = "Dieser Eintrag hat sich seit dem Öffnen geändert. Bitte schließe die Vorschau und prüfe sie erneut."; return }
            }
            clean.dateISO = hasDate || [.routine, .appointment, .mood, .checkIn, .note, .energy, .reflection].contains(clean.kind) ? ISO8601DateFormatter().string(from: date) : nil
            if [.mood, .checkIn].contains(clean.kind) { clean.moodPercent = percent }
            var snapshot = store.data
            try AIBuddyMutation.apply(clean, originalID: original.id, messageID: messageID, to: &snapshot)
            store.data = snapshot
            if let failure = store.lastSaveError { error = failure } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}


private struct BuddyTypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.25, paused: reduceMotion)) { timeline in
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    let active = Int(timeline.date.timeIntervalSinceReferenceDate * 3) % 3 == index
                    Circle().fill(Color.secondary.opacity(reduceMotion || active ? 0.8 : 0.3)).frame(width: 8, height: 8).offset(y: !reduceMotion && active ? -3 : 0)
                }
            }.padding(.horizontal, 20).padding(.vertical, 18).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
        }.accessibilityLabel("Dein Begleiter schreibt").accessibilityIdentifier("ai.typing")
    }
}
