import Foundation

struct AIBuddySettings: Codable, Equatable {
    var enabled = false
    var preferGuidedCheckIns = true
    var model = "gpt-5.6-luna"
    var transcriptionModel = "gpt-4o-mini-transcribe"
    var contextDays = 7
    var automaticRange = true
    var includeJournal = true
    var allowPhotoUploads = false
    var allowVoiceUploads = false
    init() {}
    enum CodingKeys: String, CodingKey { case preferGuidedCheckIns, enabled, model, transcriptionModel, contextDays, automaticRange, includeJournal, allowPhotoUploads, allowVoiceUploads }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferGuidedCheckIns = try c.decodeIfPresent(Bool.self, forKey: .preferGuidedCheckIns) ?? true
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "gpt-5.6-luna"
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? "gpt-4o-mini-transcribe"
        contextDays = max(1, min(90, try c.decodeIfPresent(Int.self, forKey: .contextDays) ?? 7))
        automaticRange = try c.decodeIfPresent(Bool.self, forKey: .automaticRange) ?? true
        includeJournal = try c.decodeIfPresent(Bool.self, forKey: .includeJournal) ?? true
        allowPhotoUploads = try c.decodeIfPresent(Bool.self, forKey: .allowPhotoUploads) ?? false
        allowVoiceUploads = try c.decodeIfPresent(Bool.self, forKey: .allowVoiceUploads) ?? false
    }
}
enum AIBuddyActionKind: String, Codable, CaseIterable {
    case note, mood, topic, task, appointment, routine, goal, checkIn, reflection, completeTask, completeRoutine, openScreen
    var label: String {
        switch self {
        case .note: "Notiz / Tagebuch"; case .mood: "Stimmung eintragen"; case .topic: "Therapiethema"; case .task: "Aufgabe"; case .appointment: "Zusatztermin"; case .routine: "Routine"; case .goal: "Ziel"; case .checkIn: "Check-in"; case .reflection: "Therapie-Rückblick"; case .completeTask: "Aufgabe erledigen"; case .completeRoutine: "Routine bestätigen"; case .openScreen: "Bereich öffnen"
        }
    }
    var symbol: String {
        switch self {
        case .note: "note.text"; case .mood: "face.smiling"; case .topic: "text.bubble"; case .task, .completeTask: "checklist"; case .appointment: "calendar.badge.plus"; case .routine, .completeRoutine: "checkmark.circle"; case .goal: "scope"; case .checkIn: "sparkles"; case .reflection: "clock.arrow.circlepath"; case .openScreen: "arrow.up.right.square"
        }
    }
}
struct AIBuddyAction: Codable, Equatable, Identifiable {
    // Stable content identity prevents double execution after a repeated tap/re-render.
    var id: String { kind.rawValue + "|" + title + "|" + text + "|" + (targetID ?? "") + "|" + (dateISO ?? "") }
    var kind: AIBuddyActionKind
    var title: String
    var text: String
    var dateISO: String?
    var moodPercent: Int?
    var targetID: String?
    var minutes: Int?
    var weekdays: [Int]
    var tags: [String]?
    var date: Date? { dateISO.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var valid: Bool {
        guard (tags ?? []).count <= 15, (tags ?? []).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 60 }), title.count <= 160, text.count <= 6000, (dateISO == nil || date != nil), (moodPercent == nil || (0...100).contains(moodPercent!)), weekdays.allSatisfy({ (1...7).contains($0) }) else { return false }
        if ![AIBuddyActionKind.note, .checkIn].contains(kind), !(tags ?? []).isEmpty { return false }
        if kind == .openScreen { return ["today", "insights", "therapy", "archive", "session", "routines", "appointments", "reminders"].contains(targetID ?? "") }
        if [.completeTask, .completeRoutine].contains(kind) { return !(targetID ?? "").isEmpty }
        if kind == .appointment || kind == .routine { return date != nil && !title.isEmpty }
        return !title.isEmpty || !text.isEmpty
    }
}
struct AIBuddySection: Codable, Equatable { var heading: String; var text: String }
struct AIBuddyReply: Codable, Equatable {
    var title: String
    var message: String
    var sections: [AIBuddySection]
    var actions: [AIBuddyAction]
    var suggestedDays: Int?
    var checkIn: AIBuddyCheckInProposal?
    var valid: Bool { (checkIn?.valid ?? true) && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.count <= 12000 && title.count <= 160 && sections.count <= 8 && actions.count <= 6 && actions.allSatisfy(\.valid) && sections.allSatisfy { $0.heading.count <= 160 && $0.text.count <= 6000 } && (suggestedDays == nil || (1...90).contains(suggestedDays!)) }
    var journalText: String {
        ([AIBuddyText.plain(message)] + sections.map { AIBuddyText.plain($0.heading) + "\n" + AIBuddyText.plain($0.text) }).joined(separator: "\n\n")
    }
    static var fallback: AIBuddyReply { .init(title: "Wie möchtest du das festhalten?", message: "Die Antwort konnte nicht als sichere App-Aktion gelesen werden. Du kannst deine Eingabe mit einem dieser Wege selbst festhalten oder es erneut versuchen.", sections: [], actions: [.init(kind: .mood, title: "Meine Stimmung", text: "", weekdays: []), .init(kind: .note, title: "Mein Gedanke", text: "", weekdays: []), .init(kind: .topic, title: "Für die nächste Therapie", text: "", weekdays: [])], suggestedDays: nil) }
}
struct AIBuddyMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var role: String
    var text: String
    var reply: AIBuddyReply?
    var contextStart: Date?
    var contextEnd: Date?
    var model: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var appliedActionIDs: [String] = []
    var savedNoteID: UUID?
    var conversationID: UUID?
}
enum AIBuddyText {
    static func plain(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "(?m)^```[^\\n]*\\n?", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?<!_)_([^_\\n]+)_(?!_)", with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`"] { value = value.replacingOccurrences(of: marker, with: "") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
struct AIBuddyContext {
    var start: Date
    var end: Date
    var days: Int
    var recordCount: Int
    var omittedCount: Int
    var text: String
    static func resolvedDays(question: String, settings: AIBuddySettings) -> Int {
        guard settings.automaticRange else { return max(1, min(90, settings.contextDays)) }
        let q = question.lowercased()
        if let range = q.range(of: "\\b[0-9]{1,2}\\s+(tage|wochen|monate)", options: .regularExpression) {
            let matched = String(q[range])
            if let number = Int(matched.prefix { $0.isNumber }) {
                let multiplier = matched.contains("wochen") ? 7 : matched.contains("monate") ? 30 : 1
                return max(1, min(90, number * multiplier))
            }
        }
        if q.contains("heute") || q.contains("tagesrückblick") { return 1 }
        if q.contains("woche") { return 7 }
        if q.contains("monat") { return 30 }
        return max(1, min(90, settings.contextDays))
    }
    static func make(data: AppData, days: Int, end: Date = Date(), calendar: Calendar = .current) -> AIBuddyContext {
        let days = max(1, min(90, days)), lastDay = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: lastDay)!
        let formatter = ISO8601DateFormatter()
        let records = ArchiveRecord.all(in: data).filter { $0.date >= start && $0.date <= end }.filter { record in
            if case .media = record { return false } // Binary media is strictly opt-in, outside automatic context.
            if !data.aiSettings.includeJournal, case .note = record { return false }
            return true
        }.sorted { $0.date > $1.date }
        var lines: [String] = [], characters = 0
        for record in records.prefix(100) {
            var details = record.subtitle
            if case .guided(let checkIn) = record {
                let moodText: String
                if let percent = checkIn.moodPercent { moodText = String(percent) }
                else if let mood = checkIn.mood { moodText = String((mood - 1) * 25) }
                else { moodText = "unbekannt" }
                let batteryText = checkIn.batteryPercent.map { String($0) } ?? "unbekannt"
                var parts: [String] = [checkIn.summary, checkIn.givesEnergy, checkIn.takesEnergy, checkIn.smallWin, checkIn.nextNeed, checkIn.therapyQuestion]
                parts.append("Stimmung " + moodText + "/100")
                parts.append("Akku " + batteryText + "/100")
                details = parts.joined(separator: " · ")
            }
            let line = formatter.string(from: record.date) + " | " + record.id + " | " + record.title + " | " + String(details.prefix(900))
            guard characters + line.count <= 18000 else { break }
            lines.append(line); characters += line.count
        }
        let period = WellnessPeriod.rolling(days: days, now: end)
        let daily = WellnessAnalytics.daily(data, period: period)
        let moods = daily.compactMap(\.mood)
        let average = WellnessAnalytics.average(moods).map { String(format: "%.1f/5", $0) } ?? "keine Werte"
        let trend = InsightsAnalytics.trend(data: data, period: period).map { String(format: "%+.2f", $0) } ?? "zu wenige Werte"
        let next = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: end).map(formatter.string) ?? "keiner"
        let occurrences: [RoutineOccurrence] = RoutinePlanner.due(data: data, now: end)
        var dueLines: [String] = []
        for occurrence in occurrences.prefix(12) {
            let routine: DailyRoutine? = data.routines.first(where: { $0.id == occurrence.routineID })
            let title: String = routine?.title ?? "Routine"
            dueLines.append(occurrence.id + " | " + title)
        }
        let due: String = dueLines.joined(separator: "\n")
        var taskLines: [String] = []
        for task in data.weeklyTasks.filter({ !$0.completed }).prefix(15) { taskLines.append(task.id.uuidString + " | " + task.title) }
        let openTasks: String = taskLines.joined(separator: "\n")
        var topicLines: [String] = []
        for point in TherapyDiscussionPlanner.points(in: data).prefix(15) {
            let line: String = formatter.string(from: point.date) + " | " + String(point.text.prefix(350))
            topicLines.append(line)
        }
        let topics: String = topicLines.joined(separator: "\n")
        var session: String = "Keine Stunde aktiv"
        if let current = data.currentSession {
            let phases: String = current.phases.map { $0.title }.joined(separator: ", ")
            session = "Laufende Stunde: " + current.title
            session += ", Phasen: " + phases
            session += ", begonnen " + formatter.string(from: current.startedAt)
        }
        var text = session + "\nZeitraum " + formatter.string(from: start) + " bis " + formatter.string(from: end)
        text += ", \(days) Kalendertage. \(lines.count) Einträge, \(records.count - lines.count) aus Platzgründen nicht enthalten."
        text += " Selbstberichtete Tagesmittel: \(average) bei \(moods.count) Tagen mit Stimmung; Trend \(trend) auf Skala 1–5, keine Diagnose."
        text += " Nächste Therapie: " + next
        text += "\nBEKANNTE HASHTAGS (Namen wiederverwenden): " + AppHashtags.catalog(data).prefix(80).joined(separator: ", ")
        text += "\nEINTRÄGE:\n" + lines.joined(separator: "\n")
        text += "\nFÄLLIGE ROUTINEN (IDs):\n" + due
        text += "\nOFFENE AUFGABEN (IDs):\n" + openTasks
        text += "\nGESPRÄCHSLISTE (auch ältere offene Punkte):\n" + topics
        return .init(start: start, end: end, days: days, recordCount: lines.count, omittedCount: records.count - lines.count, text: text)
    }
}


struct AIBuddyConversation: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "Neues Gespräch"
    var createdAt = Date()
    var updatedAt = Date()
    var checkInID: UUID?
    var noteContext: TherapyNote?
    var contextDays: Int?
    var savedNoteID: UUID?
    var savedMessageCount: Int?
}

/// Shared vocabulary. Existing stored spellings remain intact; comparisons use canonical keys.
enum AppHashtags {
    static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
    static func clean(_ values: [String], known: [String] = []) -> [String] {
        var result: [String] = [], seen = Set<String>()
        for raw in values.prefix(30) {
            let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(60))
            let k = key(name)
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            result.append(known.first { key($0) == k } ?? name)
        }
        return result
    }
    static func catalog(_ data: AppData) -> [String] {
        clean(data.hashtagCatalog + data.notes.flatMap(\.tags) + data.media.flatMap(\.tags) + data.guidedCheckIns.flatMap { $0.tags ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func tags(_ record: ArchiveRecord) -> [String] {
        switch record { case .note(let n): n.tags; case .media(let m): m.tags; case .guided(let c): c.tags ?? []; default: [] }
    }
}
struct AIBuddyCheckInProposal: Codable, Equatable {
    var moodPercent: Int?
    var batteryPercent: Int?
    var stress: Int?
    var sensoryLoad: Int?
    var sleepHours: Double?
    var summary: String?
    var givesEnergy: String?
    var takesEnergy: String?
    var smallWin: String?
    var nextNeed: String?
    var therapyQuestion: String?
    var tasks: [String]?
    var tags: [String]?
    var valid: Bool {
        let percentages = [moodPercent, batteryPercent].compactMap { $0 }
        let scales = [stress, sensoryLoad].compactMap { $0 }
        let texts = [summary, givesEnergy, takesEnergy, smallWin, nextNeed, therapyQuestion].compactMap { $0 }
        return percentages.allSatisfy { (0...100).contains($0) } && scales.allSatisfy { (1...5).contains($0) } && (sleepHours == nil || (0...24).contains(sleepHours!)) && texts.allSatisfy { $0.count <= 6000 } && (tasks ?? []).count <= 15 && (tasks ?? []).allSatisfy { $0.count <= 160 } && (tags ?? []).count <= 15 && (tags ?? []).allSatisfy { $0.count <= 60 }
    }
}
enum AICheckInGuide {
    static let questions = [
        "Ankommen: Was geht dir gerade durch den Kopf?",
        "Wie geht es dir gerade? Du kannst deine Stimmung auch von 0 bis 100 beschreiben.",
        "Wie voll ist dein Energie-Akku (0–100 %)? Was gibt dir Energie und was kostet dich Energie?",
        "Wie stark sind Stress und Reizbelastung (1–5)? Wie viele Stunden hast du geschlafen?",
        "Was ist heute wichtig? Gab es einen kleinen Erfolg und was brauchst du jetzt?",
        "Welche kleinen nächsten Schritte möchtest du festhalten? Noch wird keine Aufgabe angelegt.",
        "Was möchtest du in deiner nächsten Therapie besprechen?",
        "Schau dir deine Übersicht an. Du kannst alles bearbeiten und erst danach abschließen."
    ]
    static func instructions(_ entry: GuidedCheckIn) -> String {
        let step = max(0, min(7, entry.step))
        var result = "\nKI-GEFÜHRTER CHECK-IN. Aktuelle Standardfrage: " + questions[step]
        result += "\nDeute ausschließlich die aktuelle Nutzerantwort als Daten für diese Frage. checkIn enthält nur belegte Angaben, sonst null. Kein Ergänzen aus älteren Einträgen. Stimmung vorsichtig vorschlagen, immer überprüfbar. tasks nur explizite gewünschte Schritte, tags bekannte Hashtags bevorzugen. Alle Fragen sind freiwillig; 'überspringen' ergibt null. Keine actions für separate Kopien dieses Check-ins."
        result += "\nAntworte freundlich auf die Antwort und stelle dann genau die nächste Standardfrage, persönlich umformuliert: " + questions[min(7, step + 1)]
        if let encoded = try? JSONEncoder().encode(entry), let text = String(data: encoded, encoding: .utf8) { result += "\nAKTUELLER ENTWURF: " + String(text.prefix(6000)) }
        return result
    }
    static func apply(_ proposal: AIBuddyCheckInProposal, to entry: inout GuidedCheckIn, known: [String]) -> Bool {
        guard entry.isDraft, proposal.valid else { return false }
        switch entry.step {
        case 0: if let v = proposal.summary { entry.summary = v }
        case 1: if let v = proposal.moodPercent { entry.moodPercent = v; entry.mood = MoodBarometer.score(v) }
        case 2:
            if let v = proposal.batteryPercent { entry.batteryPercent = v }
            if let v = proposal.givesEnergy { entry.givesEnergy = v }
            if let v = proposal.takesEnergy { entry.takesEnergy = v }
        case 3:
            if let v = proposal.stress { entry.stress = v }
            if let v = proposal.sensoryLoad { entry.sensoryLoad = v }
            if let v = proposal.sleepHours { entry.sleepHours = v }
        case 4:
            if let v = proposal.summary { entry.summary = v }
            if let v = proposal.smallWin { entry.smallWin = v }
            if let v = proposal.nextNeed { entry.nextNeed = v }
        case 5:
            for title in proposal.tasks ?? [] where !title.isEmpty && !entry.tasks.contains(where: { $0.title == title }) { entry.tasks.append(CheckInTaskDraft(title: title)) }
        case 6: if let v = proposal.therapyQuestion { entry.therapyQuestion = v }
        default: return false
        }
        entry.tags = AppHashtags.clean((entry.tags ?? []) + (proposal.tags ?? []), known: known)
        entry.step = min(7, entry.step + 1)
        return true
    }
}
enum AIConversationMutation {
    static func create(in data: inout AppData, checkIn: GuidedCheckIn? = nil, note: TherapyNote? = nil) -> UUID {
        let checkIn = checkIn.map { DayCheckInPolicy.reopen($0, in: data) }
        if let checkIn, let existing = data.aiConversations.first(where: { $0.checkInID == checkIn.id }) { return existing.id }
        let conversation = AIBuddyConversation(title: checkIn?.displayTitle ?? note?.title ?? "Neues Gespräch", checkInID: checkIn?.id, noteContext: note)
        if let checkIn, checkIn.isDraft { _ = GuidedCheckInMutation.apply(checkIn, complete: false, to: &data) }
        data.aiConversations.insert(conversation, at: 0)
        if let checkIn, checkIn.isDraft { data.aiMessages.append(AIBuddyMessage(role: "assistant", text: AICheckInGuide.questions[max(0, min(7, checkIn.step))], conversationID: conversation.id)) }
        return conversation.id
    }
    static func migrate(_ data: inout AppData) {
        let orphaned = data.aiMessages.filter { $0.conversationID == nil }
        guard let first = orphaned.first else { return }
        let c = AIBuddyConversation(id: first.id, title: "Bisheriges Gespräch", createdAt: first.date, updatedAt: orphaned.last?.date ?? first.date)
        if !data.aiConversations.contains(where: { $0.id == c.id }) { data.aiConversations.append(c) }
        for i in data.aiMessages.indices where data.aiMessages[i].conversationID == nil { data.aiMessages[i].conversationID = c.id }
    }
    static func delete(_ id: UUID, in data: inout AppData) {
        data.aiConversations.removeAll { $0.id == id }; data.aiMessages.removeAll { $0.conversationID == id }
    }
    static func save(_ id: UUID, in data: inout AppData) {
        guard let index = data.aiConversations.firstIndex(where: { $0.id == id }) else { return }
        let messages = data.aiMessages.filter { $0.conversationID == id }
        guard !messages.isEmpty else { return }
        let text = messages.map { ($0.role == "user" ? "Du" : "Begleiter") + " · " + $0.date.formatted(date: .abbreviated, time: .shortened) + "\n" + AIBuddyText.plain($0.text) }.joined(separator: "\n\n")
        if let saved = data.aiConversations[index].savedNoteID, let note = data.notes.firstIndex(where: { $0.id == saved }) { data.notes[note].text = text; data.notes[note].updatedAt = Date() }
        else {
            let note = TherapyNote(title: data.aiConversations[index].title, text: text, tags: ["Tagebuch", "KI-Gespräch"], category: "Therapietagebuch")
            data.notes.insert(note, at: 0); data.aiConversations[index].savedNoteID = note.id
        }
        data.aiConversations[index].savedMessageCount = messages.count
    }
}
