import SwiftUI
import UIKit

@MainActor final class AIBuddyController: ObservableObject {
    weak var store: AppStore?
    @Published var busy = false
    @Published var error: String?
    @Published var pendingQuestion = ""
    private var activeID: UUID?
    private var request: Task<AIBuddyResponse, Error>?
    init(store: AppStore) { self.store = store }
    func cancel() { activeID = nil; request?.cancel(); request = nil; busy = false; pendingQuestion = "" }
    func send(_ question: String, image: Data? = nil, inSession: Bool = false, daysOverride: Int? = nil, conversationID: UUID? = nil) async -> Bool {
        guard !busy, let store, store.data.aiSettings.enabled else { return false }
        let fixture = ProcessInfo.processInfo.arguments.contains("--buddy-network-fixture")
        guard let key = fixture ? "fixture-no-network" : AIBuddyKeychain.read() else { error = "Bitte hinterlege zuerst deinen OpenAI-API-Schlüssel im Profil."; return false }
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 5000 else { error = "Bitte schreibe eine Nachricht mit höchstens 5.000 Zeichen."; return false }
        let chatID: UUID
        if let conversationID { chatID = conversationID }
        else { var snapshot = store.data; chatID = snapshot.aiConversations.first?.id ?? AIConversationMutation.create(in: &snapshot); store.data = snapshot }
        guard let chat = store.data.aiConversations.first(where: { $0.id == chatID }) else { return false }
        let settings = store.data.aiSettings
        let scopeInMessage = clean.range(of: "(?i)heute|tagesrückblick|woche|monat|\\b[0-9]{1,2}\\s+tage", options: .regularExpression) != nil
        let days = scopeInMessage && settings.automaticRange ? AIBuddyContext.resolvedDays(question: clean, settings: settings) : daysOverride ?? chat.contextDays ?? settings.contextDays
        var context = AIBuddyContext.make(data: store.data, days: days)
        let history = store.data.aiMessages.filter { $0.conversationID == chatID }
        let draft = chat.checkInID.flatMap { id in store.data.guidedCheckIns.first { $0.id == id && $0.isDraft } }
        let guide = draft.map(AICheckInGuide.instructions) ?? ""
        if let note = chat.noteContext, settings.includeJournal { context.text += "\nDIE NOTIZ ZUM GESPRÄCH: " + note.title + "\n" + String(note.text.prefix(6000)) }
        if let draft, draft.step >= 7 { error = "Deine Übersicht ist bereit. Bitte prüfe sie vor dem Abschließen."; return false }
        // Keep sent user messages even when a request fails or is canceled. Retry the same
        // unanswered message without duplicating it; successful turns remain distinct.
        let userText = clean + (image == nil ? "" : "\n[Ein ausgewähltes Foto wurde mit ausdrücklicher Freigabe analysiert.]")
        let userID: UUID
        if let last = history.last, last.role == "user", last.text == userText { userID = last.id }
        else {
            let message = AIBuddyMessage(role: "user", text: userText, contextStart: context.start, contextEnd: context.end, conversationID: chatID)
            var snapshot = store.data; snapshot.aiMessages.append(message)
            if let index = snapshot.aiConversations.firstIndex(where: { $0.id == chatID }) { snapshot.aiConversations[index].updatedAt = Date(); if snapshot.aiConversations[index].title == "Neues Gespräch" { snapshot.aiConversations[index].title = String(clean.prefix(60)) } }
            store.data = snapshot
            if let failure = store.lastSaveError { error = failure; return false }
            userID = message.id
        }
        let requestHistory = history.last?.id == userID ? Array(history.dropLast()) : history
        let identifier = UUID(); activeID = identifier
        busy = true; error = nil; pendingQuestion = clean
        let task = Task<AIBuddyResponse, Error> {
            if fixture {
                try await Task.sleep(for: .milliseconds(150))
                let proposal = draft == nil ? nil : AIBuddyCheckInProposal(summary: clean, tags: ["Familie"])
                let message = draft.map { AICheckInGuide.questions[min(7, $0.step + 1)] } ?? "Deine Nachricht ist angekommen. Möchtest du sie im Tagebuch festhalten?"
                let reply = AIBuddyReply(title: "Dein Gedanke", message: message, sections: [], actions: [], checkIn: proposal)
                return AIBuddyResponse(reply: reply)
            }
            return try await AIBuddyAPI().answer(question: clean, context: context, history: requestHistory, settings: settings, key: key, imageJPEG: image, inSession: inSession, guide: guide)
        }
        request = task
        defer { if activeID == identifier { busy = false; pendingQuestion = ""; request = nil; activeID = nil } }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard !task.isCancelled, activeID == identifier, store.data.aiSettings.enabled, store.data.aiConversations.contains(where: { $0.id == chatID }), store.data.aiMessages.contains(where: { $0.id == userID }) else { return false }
            var snapshot = store.data
            snapshot.aiMessages.append(AIBuddyMessage(role: "assistant", text: result.reply.journalText, reply: result.reply, contextStart: context.start, contextEnd: context.end, model: settings.model, inputTokens: result.inputTokens, outputTokens: result.outputTokens, conversationID: chatID))
            if let index = snapshot.aiConversations.firstIndex(where: { $0.id == chatID }) {
                snapshot.aiConversations[index].updatedAt = Date()
                if snapshot.aiConversations[index].title == "Neues Gespräch" { snapshot.aiConversations[index].title = String(clean.prefix(60)) }
            }
            if let id = chat.checkInID, let index = snapshot.guidedCheckIns.firstIndex(where: { $0.id == id && $0.isDraft }), let proposal = result.reply.checkIn {
                var entry = snapshot.guidedCheckIns[index]
                if AICheckInGuide.apply(proposal, to: &entry, known: AppHashtags.catalog(snapshot)) { _ = GuidedCheckInMutation.apply(entry, complete: false, to: &snapshot) }
            }
            store.data = snapshot
            if let failure = store.lastSaveError { error = failure; return false }
            if draft != nil && result.reply.checkIn == nil { error = "Die Antwort enthielt keine auswertbaren Check-in-Angaben. Deine Frage bleibt offen. Versuche es erneut oder setze normal fort."; return false }
            return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    func saveReply(_ message: AIBuddyMessage) {
        guard let store, let index = store.data.aiMessages.firstIndex(where: { $0.id == message.id }), store.data.aiMessages[index].savedNoteID == nil, let reply = message.reply else { return }
        var snapshot = store.data
        let period = [message.contextStart, message.contextEnd].compactMap { $0?.formatted(date: .abbreviated, time: .omitted) }.joined(separator: " – ")
        let note = TherapyNote(title: AIBuddyText.plain(reply.title.isEmpty ? "Mein KI-Rückblick" : reply.title), text: reply.journalText + "\n\nBerücksichtigter Zeitraum: " + period + "\nKI-gestützter Rückblick, bitte persönlich prüfen.", tags: ["Tagebuch", "KI-Rückblick"], sessionID: snapshot.currentSession?.id, category: "Therapietagebuch")
        snapshot.notes.insert(note, at: 0); snapshot.aiMessages[index].savedNoteID = note.id
        store.data = snapshot
    }
}
