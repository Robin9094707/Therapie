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
        }.navigationTitle("KI-Begleiter")
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
                if let conversationID { AIBuddyChatContent(controller: store.aiController, inSession: store.data.currentSession != nil, conversationID: conversationID, onNoteProposal: onNoteProposal) }
                else { ProgressView("Gespräch vorbereiten …") }
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { store.aiController.cancel(); dismiss() } } }
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
struct AIBuddyChatContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var controller: AIBuddyController
    var inSession: Bool
    var conversationID: UUID
    var onNoteProposal: ((TherapyNote) -> Void)? = nil
    @FocusState private var composerFocused: Bool
    @State private var manual: GuidedCheckIn?
    @State private var guided: GuidedCheckIn?
    @State private var previewContext: AIBuddyContext?
    @State private var text = ""
    @State private var settings = false
    @State private var review: AIBuddyReviewRoute?
    @State private var photo: PhotosPickerItem?
    @State private var image: Data?
    @State private var confirmPhoto = false
    @State private var voice = false
    @State private var clearChat = false
    @State private var confirmSaveChat = false
    @State private var moreMessages = false
    @State private var explicitDays: Int?
    @State private var navigation: String?
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
                        GlassCard { VStack(alignment: .leading, spacing: 8) { Text(controller.pendingQuestion).font(.subheadline); ProgressView("Dein Begleiter denkt nach …"); Button("Anfrage abbrechen") { controller.cancel() } } }
                    }
                    if let error = controller.error { GlassCard { Text(error).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled) } }
            }
        }.onChange(of: messages.count) { _, _ in
            if let id = messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
            updateContext()
        }
        }.navigationTitle(chat?.title ?? "Gespräch").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if store.data.aiSettings.enabled && chat != nil { composer.padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial) } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { if let draft { Button(draft.step == 7 ? "Übersicht" : "Normal", systemImage: "slider.horizontal.3") { controller.cancel(); composerFocused = false; manual = draft }.accessibilityIdentifier("ai.checkin.toolbar.manual") } }
                ToolbarItem(placement: .topBarTrailing) { Menu { Button("KI-Einstellungen", systemImage: "slider.horizontal.3") { settings = true }; Button("Gespräch im Tagebuch speichern", systemImage: "book.closed") { confirmSaveChat = true }; Button("Gespräch löschen", systemImage: "trash", role: .destructive) { clearChat = true } } label: { Image(systemName: "ellipsis.circle") } } }
            .sheet(isPresented: $settings) { AIBuddySettingsView() }
            .sheet(item: $guided) { GuidedCheckInDestination(entry: $0) }
            .sheet(item: $manual) { GuidedCheckInView(entry: $0) }
            .sheet(item: $review) { AIBuddyActionReviewView(action: $0.action, messageID: $0.messageID) }
            .sheet(isPresented: $voice) { AIBuddyVoiceView { transcript in text = transcript } }
            .sheet(isPresented: Binding(get: { navigation != nil }, set: { if !$0 { navigation = nil } })) { NavigationStack { destination(navigation ?? "today").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { navigation = nil } } } } }
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
            .onAppear { controller.error = nil; updateContext() }
            .onDisappear { controller.cancel() }
            .onChange(of: store.data.aiSettings.enabled) { _, enabled in if !enabled { controller.cancel(); image = nil; photo = nil } }
    }
    private var introduction: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: inSession ? "Ein Gedanke während der Stunde" : "Was geht dir heute durch den Kopf?", icon: "sparkles", subtitle: "Gemeinsam reflektieren, sortieren und passende Einträge vorbereiten.")
                if !store.data.aiSettings.enabled { Button("Optionalen KI-Begleiter einrichten", systemImage: "key") { settings = true }.buttonStyle(.borderedProminent) }
                else {
                    ScrollView(.horizontal, showsIndicators: false) { HStack {
                        prompt("Tagesrückblick", question: "Fasse meinen heutigen Tag mit Stimmungen und Einträgen knapp zusammen.", days: 1)
                        prompt("Wochenrückblick", question: "Erstelle einen Wochenrückblick für die letzten 7 Tage: Stimmung, Energie, hilfreiche Momente, offene Themen und einen kleinen nächsten Schritt.", days: 7)
                        prompt("Neuer Eintrag", question: "Ich möchte einen neuen Eintrag machen. Frage mich kurz, was ich festhalten möchte, und biete Stimmung, Notiz und Therapiethema als passende Aktionen an.", days: nil)
                    } }
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
                let selection = Binding<Int>(get: { explicitDays ?? 0 }, set: { setDays($0 == 0 ? nil : $0); persistDays() })
                Picker("Kontext", selection: selection) { Text("Aus Frage / Standard").tag(0); Text("Heute").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90) }
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
                            else { review = .init(messageID: message.id, action: action) }
                        } label: { Label(applied ? "Gespeichert · " + action.kind.label : action.kind.label + (action.title.isEmpty ? "" : ": " + AIBuddyText.plain(action.title)), systemImage: applied ? "checkmark.circle.fill" : action.kind.symbol).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered).disabled(applied).accessibilityIdentifier("ai.action." + action.kind.rawValue)
                    }
                    if let days = reply.suggestedDays { Text("Mehr Kontext? Vorschlag: \(days) Tage").font(.caption) }
                    if message.id == messages.last?.id {
                        VStack(alignment: .leading) {
                            Text("Für die nächste Nachricht: \(explicitDays ?? chat?.contextDays ?? store.data.aiSettings.contextDays) Tage").font(.caption)
                            Slider(value: Binding(get: { Double(explicitDays ?? chat?.contextDays ?? store.data.aiSettings.contextDays) }, set: { setDays(Int($0)) }), in: 1...90, step: 1, onEditingChanged: { editing in if !editing { persistDays(); updateContext() } }).accessibilityLabel("Kontext in Tagen")
                            Button("Zeitraum wieder aus Nachricht erkennen") { setDays(nil); persistDays(); updateContext() }.font(.caption)
                        }
                        if draft == nil { Button("KI-geführten Check-in beginnen", systemImage: "sparkles") { startCheckIn() }.buttonStyle(.bordered) }
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
                if store.data.aiSettings.allowVoiceUploads { Button { composerFocused = false; voice = true } label: { Image(systemName: "mic") }.accessibilityLabel("Einsprechen").frame(minWidth: 44, minHeight: 44) }
                if store.data.aiSettings.allowPhotoUploads { PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }.accessibilityLabel("Foto auswählen").frame(minWidth: 44, minHeight: 44) }
                TextField("Nachricht …", text: $text, axis: .vertical).lineLimit(1...5).focused($composerFocused).padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22)).accessibilityIdentifier("ai.composer")
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)).foregroundStyle(.indigo) }.accessibilityLabel("Senden").disabled(controller.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 5000 || draft?.step == 7).accessibilityIdentifier("ai.send")
            }
            if text.count > 4800 { Text("\(text.count) / 5.000 Zeichen").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func send() {
        guard !controller.busy else { return }
        let question = text, picture = image
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            await Task.yield()
            let succeeded = await controller.send(question, image: picture, inSession: inSession, daysOverride: explicitDays, conversationID: conversationID)
            updateContext()
            if succeeded { if text == question { text = "" }; image = nil; photo = nil }
        }
    }
    private func setDays(_ days: Int?) {
        explicitDays = days
    }
    private func persistDays() {
        guard let index = store.data.aiConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        store.data.aiConversations[index].contextDays = explicitDays
    }
    private func updateContext() { previewContext = AIBuddyContext.make(data: store.data, days: explicitDays ?? chat?.contextDays ?? store.data.aiSettings.contextDays) }
    private func startCheckIn() {
        let entry = GuidedCheckIn(kind: .free)
        // A separate linked conversation keeps the guided questions out of the current discussion.
        guided = DayCheckInPolicy.reopen(entry, in: store.data)
    }
    private func guideHeader(_ entry: GuidedCheckIn) -> some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                Label("KI-geführter Check-in · \(entry.step + 1) / 8", systemImage: "sparkles").font(.headline)
                ProgressView(value: Double(entry.step + 1), total: 8)
                Text(AICheckInGuide.questions[max(0, min(7, entry.step))]).font(.subheadline)
                HStack {
                    Button(entry.step == 7 ? "Übersicht prüfen & abschließen" : "Normal fortsetzen", systemImage: "slider.horizontal.3") { controller.cancel(); composerFocused = false; manual = entry }.accessibilityIdentifier("ai.checkin.manual")
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
        navigation = screen
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
    init(action: AIBuddyAction, messageID: UUID) { original = action; self.messageID = messageID; _action = State(initialValue: action); _date = State(initialValue: action.date ?? Date()); _percent = State(initialValue: action.moodPercent ?? 50) }
    private var completion: Bool { [.completeTask, .completeRoutine].contains(action.kind) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Vorschlag · bitte prüfen") {
                    Label(action.kind.label, systemImage: action.kind.symbol)
                    if completion { Text("Bestätige nur, wenn du diese Aufgabe oder Routine wirklich erledigt hast.").font(.headline) }
                    TherapyInputField(title: "Überschrift", multiline: false, text: $action.title)
                    TherapyInputField(title: "Text", text: $action.text)
                    HashtagEditor(tags: Binding(get: { action.tags ?? [] }, set: { action.tags = $0 }))
                }
                if !completion {
                    Section("Datum & Einordnung") {
                        DatePicker("Zeitpunkt", selection: $date)
                        if [.mood, .checkIn].contains(action.kind) {
                            MoodBarometerControl(percent: $percent)
                            Text(original.moodPercent == nil ? "Die KI hat keine Stimmung festgelegt. Wähle deinen eigenen Wert." : "Die KI hat diesen Wert vorgeschlagen. Du kannst ihn frei ändern.").font(.caption).foregroundStyle(.secondary)
                        }
                        if action.kind == .routine { WeekdaySelection(days: $action.weekdays); Text("Keine Auswahl = täglich. Die Uhrzeit stammt aus dem Zeitpunkt oben.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section { Text("Speichert einen regulären App-Eintrag, inklusive Backup, Export und Rückgängig-Funktion.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle(completion ? "Wirklich erledigt?" : "KI-Vorschlag bearbeiten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(completion ? "Ja, erledigt" : "Speichern") { save() }.bold().disabled(action.title.count > 160 || action.text.count > 6000 || (!completion && action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
                }
        }
    }
    private func save() {
        do {
            var clean = action
            clean.dateISO = ISO8601DateFormatter().string(from: date)
            if [.mood, .checkIn].contains(clean.kind) { clean.moodPercent = percent }
            var snapshot = store.data
            try AIBuddyMutation.apply(clean, originalID: original.id, messageID: messageID, to: &snapshot)
            store.data = snapshot
            if let failure = store.lastSaveError { error = failure } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
