import SwiftUI
import PhotosUI
import UIKit

struct AIBuddyView: View {
    @EnvironmentObject private var store: AppStore
    var inSession = false
    var body: some View { AIBuddyChatContent(controller: store.aiController, inSession: inSession) }
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
    @State private var text = ""
    @State private var settings = false
    @State private var review: AIBuddyReviewRoute?
    @State private var photo: PhotosPickerItem?
    @State private var image: Data?
    @State private var confirmPhoto = false
    @State private var voice = false
    @State private var clearChat = false
    @State private var moreMessages = false
    @State private var explicitDays: Int?
    @State private var navigation: String?
    private var context: AIBuddyContext { AIBuddyContext.make(data: store.data, days: explicitDays ?? AIBuddyContext.resolvedDays(question: text, settings: store.data.aiSettings)) }
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 16) {
                introduction
                if store.data.aiSettings.enabled {
                    contextCard
                    ForEach(Array(moreMessages ? store.data.aiMessages : Array(store.data.aiMessages.suffix(40)))) { message in messageCard(message) }
                    if store.data.aiMessages.count > 40 && !moreMessages { Button("Frühere Nachrichten anzeigen") { moreMessages = true } }
                    if controller.busy {
                        GlassCard { VStack(alignment: .leading, spacing: 8) { Text(controller.pendingQuestion).font(.subheadline); ProgressView("Dein Begleiter denkt nach …"); Button("Anfrage abbrechen") { controller.cancel() } } }
                    }
                    if let error = controller.error { GlassCard { Text(error).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled) } }
                    composer
                }
            }
        }.navigationTitle("KI-Begleiter").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("KI-Einstellungen", systemImage: "slider.horizontal.3") { settings = true }; Button("Chat leeren", systemImage: "trash", role: .destructive) { clearChat = true } } label: { Image(systemName: "ellipsis.circle") } } }
            .sheet(isPresented: $settings) { AIBuddySettingsView() }
            .sheet(item: $review) { AIBuddyActionReviewView(action: $0.action, messageID: $0.messageID) }
            .sheet(isPresented: $voice) { AIBuddyVoiceView { transcript in text = transcript } }
            .sheet(isPresented: Binding(get: { navigation != nil }, set: { if !$0 { navigation = nil } })) { NavigationStack { destination(navigation ?? "today").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { navigation = nil } } } } }
            .onChange(of: photo) { _, value in if value != nil { confirmPhoto = true } }
            .alert("Ausgewähltes Foto an OpenAI senden?", isPresented: $confirmPhoto) {
                Button("Abbrechen", role: .cancel) { photo = nil; image = nil }
                Button("Für nächste Nachricht vorbereiten") { Task { await preparePhoto() } }
            } message: { Text("Das Foto wird auf höchstens 1.024 Pixel verkleinert und beim nächsten Senden hochgeladen. Es kann persönliche Informationen enthalten. Die Bildanalyse verursacht zusätzliche API-Kosten. Andere Archivbilder werden nicht übertragen.") }
            .alert("Chatverlauf leeren?", isPresented: $clearChat) { Button("Abbrechen", role: .cancel) {}; Button("Leeren", role: .destructive) { controller.cancel(); store.data.aiMessages = [] } } message: { Text("Gespeicherte Tagebucheinträge bleiben erhalten. Rückgängig ist zehn Minuten lang in der geöffneten App möglich.") }
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
                let selection = Binding<Int>(get: { explicitDays ?? 0 }, set: { explicitDays = $0 == 0 ? nil : $0 })
                Picker("Kontext", selection: selection) { Text("Aus Frage / Standard").tag(0); Text("Heute").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90) }
                Text(context.start.formatted(date: .abbreviated, time: .omitted) + " – " + context.end.formatted(date: .abbreviated, time: .omitted) + " · \(context.recordCount) Text-Einträge").font(.caption).foregroundStyle(.secondary)
                if context.omittedCount > 0 { Text("\(context.omittedCount) Einträge werden wegen des Textlimits ausgelassen; neuere haben Vorrang.").font(.caption).foregroundStyle(.secondary) }
                Text("Zusätzlich: aktuelle offene Aufgaben, fällige Routinen und offene Gesprächspunkte, auch ältere. Der Chat berücksichtigt die letzten 8 Nachrichten. Bilder nur nach deiner Auswahl.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func messageCard(_ message: AIBuddyMessage) -> some View {
        GlassCard(emphasized: message.role == "assistant") {
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
                    if let days = reply.suggestedDays { Button("Für nächste Frage \(days) Tage berücksichtigen") { explicitDays = days }.font(.subheadline) }
                    Button(message.savedNoteID == nil ? "Rückblick im Tagebuch speichern" : "Im Tagebuch gespeichert", systemImage: "book.closed") { controller.saveReply(message) }.buttonStyle(.bordered).disabled(message.savedNoteID != nil).accessibilityIdentifier("ai.save.summary")
                    if let start = message.contextStart, let end = message.contextEnd { Text("Kontext " + start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary) }
                    if let input = message.inputTokens, let output = message.outputTokens { Text("\(message.model ?? "OpenAI") · letzte Antwort: \(input) Eingabe- / \(output) Ausgabetokens. Eventuelle Wiederholungen kommen hinzu.").font(.caption2).foregroundStyle(.secondary) }
                } else { Text(message.text).font(.subheadline).textSelection(.enabled) }
                Text(message.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func formatted(_ value: String) -> some View {
        let text = (try? AttributedString(markdown: value.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(AIBuddyText.plain(value))
        return Text(text).font(.subheadline).textSelection(.enabled)
    }
    private var composer: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                TherapyInputField(title: "Deine Nachricht", prompt: "Wie geht es dir? Was möchtest du festhalten?", text: $text).accessibilityIdentifier("ai.composer")
                if image != nil { HStack { Label("Ein Foto für diese Nachricht vorbereitet", systemImage: "photo"); Spacer(); Button("Entfernen") { image = nil; photo = nil } }.font(.caption) }
                HStack {
                    if store.data.aiSettings.allowVoiceUploads { Button("Einsprechen", systemImage: "mic") { voice = true }.buttonStyle(.bordered) }
                    if store.data.aiSettings.allowPhotoUploads { PhotosPicker(selection: $photo, matching: .images) { Label("Foto", systemImage: "photo") }.buttonStyle(.bordered) }
                    Spacer()
                    Button("Senden", systemImage: "arrow.up.circle.fill") { Task { let succeeded = await controller.send(text, image: image, inSession: inSession, daysOverride: explicitDays); if succeeded { text = ""; image = nil; photo = nil } } }.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 5000).accessibilityIdentifier("ai.send")
                }
                Text("Änderungen entstehen erst nach deinem Speichern. KI-Vorschläge für Stimmung, Datum und Inhalt kannst du vorher korrigieren.").font(.caption2).foregroundStyle(.secondary)
            }.disabled(controller.busy)
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
