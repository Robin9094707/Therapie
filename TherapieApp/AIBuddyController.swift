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
    func send(_ question: String, image: Data? = nil, inSession: Bool = false, daysOverride: Int? = nil) async -> Bool {
        guard !busy, let store, store.data.aiSettings.enabled else { return false }
        guard let key = AIBuddyKeychain.read() else { error = "Bitte hinterlege zuerst deinen OpenAI-API-Schlüssel im Profil."; return false }
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 5000 else { error = "Bitte schreibe eine Nachricht mit höchstens 5.000 Zeichen."; return false }
        let settings = store.data.aiSettings
        let context = AIBuddyContext.make(data: store.data, days: daysOverride ?? AIBuddyContext.resolvedDays(question: clean, settings: settings))
        let history = store.data.aiMessages
        let identifier = UUID(); activeID = identifier
        busy = true; error = nil; pendingQuestion = clean
        let task = Task { try await AIBuddyAPI().answer(question: clean, context: context, history: history, settings: settings, key: key, imageJPEG: image, inSession: inSession) }
        request = task
        defer { if activeID == identifier { busy = false; pendingQuestion = ""; request = nil; activeID = nil } }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard !task.isCancelled, activeID == identifier, store.data.aiSettings.enabled else { return false }
            var snapshot = store.data
            snapshot.aiMessages.append(AIBuddyMessage(role: "user", text: clean + (image == nil ? "" : "\n[Ein ausgewähltes Foto wurde mit ausdrücklicher Freigabe analysiert.]"), contextStart: context.start, contextEnd: context.end))
            snapshot.aiMessages.append(AIBuddyMessage(role: "assistant", text: result.reply.journalText, reply: result.reply, contextStart: context.start, contextEnd: context.end, model: settings.model, inputTokens: result.inputTokens, outputTokens: result.outputTokens))
            store.data = snapshot
            if let failure = store.lastSaveError { error = failure; return false }
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
