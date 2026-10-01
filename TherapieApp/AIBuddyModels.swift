import Foundation

struct AIBuddySettings: Codable, Equatable {
    var enabled = false
    var model = "gpt-5.6-luna"
    var transcriptionModel = "gpt-4o-mini-transcribe"
    var contextDays = 7
    var automaticRange = true
    var includeJournal = true
    var allowPhotoUploads = false
    var allowVoiceUploads = false
    init() {}
    enum CodingKeys: String, CodingKey { case enabled, model, transcriptionModel, contextDays, automaticRange, includeJournal, allowPhotoUploads, allowVoiceUploads }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
    var date: Date? { dateISO.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var valid: Bool {
        guard title.count <= 160, text.count <= 6000, (dateISO == nil || date != nil), (moodPercent == nil || (0...100).contains(moodPercent!)), weekdays.allSatisfy({ (1...7).contains($0) }) else { return false }
        if [.completeTask, .completeRoutine, .openScreen].contains(kind) { return !(targetID ?? "").isEmpty }
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
    var valid: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.count <= 12000 && title.count <= 160 && sections.count <= 8 && actions.count <= 6 && actions.allSatisfy(\.valid) && sections.allSatisfy { $0.heading.count <= 160 && $0.text.count <= 6000 } && (suggestedDays == nil || (1...90).contains(suggestedDays!)) }
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
}
enum AIBuddyText {
    static func plain(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "(?m)^```[^\\n]*\\n?", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
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
        if q.contains("heute") || q.contains("tagesrückblick") { return 1 }
        if q.contains("wochen") || q.contains("diese woche") { return 7 }
        if q.contains("monat") { return 30 }
        if let range = q.range(of: "\\b[0-9]{1,2}\\s+tage", options: .regularExpression), let number = Int(q[range].split(separator: " ")[0]) { return max(1, min(90, number)) }
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
                details = [checkIn.summary, checkIn.givesEnergy, checkIn.takesEnergy, checkIn.smallWin, checkIn.nextNeed, checkIn.therapyQuestion, "Stimmung \(checkIn.moodPercent.map(String.init) ?? checkIn.mood.map { String(($0 - 1) * 25) } ?? "unbekannt")/100", "Akku \(checkIn.batteryPercent.map(String.init) ?? "unbekannt")/100"].joined(separator: " · ")
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
        let due = RoutinePlanner.due(data: data, now: end).prefix(12).map { occurrence in "\(occurrence.id) | \(data.routines.first { $0.id == occurrence.routineID }?.title ?? "Routine")" }.joined(separator: "\n")
        let openTasks = data.weeklyTasks.filter { !$0.completed }.prefix(15).map { "\($0.id) | \($0.title)" }.joined(separator: "\n")
        let topics = TherapyDiscussionPlanner.points(in: data).prefix(15).map { formatter.string(from: $0.date) + " | " + String($0.text.prefix(350)) }.joined(separator: "\n")
        let session = data.currentSession.map { "Laufende Stunde: " + $0.title + ", Phasen: " + $0.phases.map(\.title).joined(separator: ", ") + ", begonnen " + formatter.string(from: $0.startedAt) } ?? "Keine Stunde aktiv"
        let text = session + "\nZeitraum \(formatter.string(from: start)) bis \(formatter.string(from: end)), \(days) Kalendertage. \(lines.count) Einträge, \(records.count - lines.count) aus Platzgründen nicht enthalten. Selbstberichtete Tagesmittel: \(average) bei \(moods.count) Tagen mit Stimmung; Trend \(trend) auf Skala 1–5, keine Diagnose. Nächste Therapie: \(next).\nEINTRÄGE:\n" + lines.joined(separator: "\n") + "\nFÄLLIGE ROUTINEN (IDs):\n" + due + "\nOFFENE AUFGABEN (IDs):\n" + openTasks + "\nGESPRÄCHSLISTE (auch ältere offene Punkte):\n" + topics
        return .init(start: start, end: end, days: days, recordCount: lines.count, omittedCount: records.count - lines.count, text: text)
    }
}
