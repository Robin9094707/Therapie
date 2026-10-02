import Foundation

struct AIBuddySettings: Codable, Equatable {
    var enabled = false
    var preferGuidedCheckIns = true
    var speakReplies = false
    var weeklyReviewEnabled = false
    var lastWeeklyReview: Date?
    var lastWeeklyReviewAttempt: Date?
    var model = "gpt-5.6-luna"
    var transcriptionModel = "gpt-4o-mini-transcribe"
    var contextDays = 7
    var automaticRange = true
    var includeJournal = true
    var allowPhotoUploads = false
    var allowVoiceUploads = false
    init() {}
    enum CodingKeys: String, CodingKey { case speakReplies, lastWeeklyReviewAttempt, weeklyReviewEnabled, lastWeeklyReview, preferGuidedCheckIns, enabled, model, transcriptionModel, contextDays, automaticRange, includeJournal, allowPhotoUploads, allowVoiceUploads }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speakReplies = try c.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? false
        weeklyReviewEnabled = try c.decodeIfPresent(Bool.self, forKey: .weeklyReviewEnabled) ?? false
        lastWeeklyReviewAttempt = try c.decodeIfPresent(Date.self, forKey: .lastWeeklyReviewAttempt)
        lastWeeklyReview = try c.decodeIfPresent(Date.self, forKey: .lastWeeklyReview)
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
    case note, mood, topic, task, appointment, routine, goal, checkIn, reflection, completeTask, completeRoutine, openScreen, guidedCheckIn, energy, updateTask, updateRoutine, deleteTask, deleteRoutine, setting, battery, startSession
    var label: String {
        switch self {
        case .battery: "Akku eintragen"; case .startSession: "Therapierunde starten"
        case .guidedCheckIn: "Check-in starten / öffnen"; case .energy: "Akku-Punkt"; case .updateTask: "Aufgabe ändern"; case .updateRoutine: "Routine ändern"; case .deleteTask: "Aufgabe entfernen"; case .deleteRoutine: "Routine entfernen"; case .setting: "Einstellung ändern"
        case .note: "Notiz / Tagebuch"; case .mood: "Stimmung eintragen"; case .topic: "Therapiethema"; case .task: "Aufgabe"; case .appointment: "Zusatztermin"; case .routine: "Routine"; case .goal: "Ziel"; case .checkIn: "Check-in"; case .reflection: "Therapie-Rückblick"; case .completeTask: "Aufgabe erledigen"; case .completeRoutine: "Routine bestätigen"; case .openScreen: "Bereich öffnen"
        }
    }
    var symbol: String {
        switch self {
        case .battery: "battery.100percent"; case .startSession: "timer"
        case .guidedCheckIn: "sparkles"; case .energy: "battery.100percent"; case .updateTask, .updateRoutine: "pencil"; case .deleteTask, .deleteRoutine: "trash"; case .setting: "slider.horizontal.3"
        case .note: "note.text"; case .mood: "face.smiling"; case .topic: "text.bubble"; case .task, .completeTask: "checklist"; case .appointment: "calendar.badge.plus"; case .routine, .completeRoutine: "checkmark.circle"; case .goal: "scope"; case .checkIn: "sparkles"; case .reflection: "clock.arrow.circlepath"; case .openScreen: "arrow.up.right.square"
        }
    }
}
struct AIBuddyAction: Codable, Equatable, Identifiable {
    // Stable content identity prevents double execution after a repeated tap/re-render.
    var id: String { kind.rawValue + "|" + title + "|" + text + "|" + (targetID ?? "") + "|" + (dateISO ?? "") + (options.map { "|" +  $0.stableIdentity } ?? "") }
    var kind: AIBuddyActionKind
    var title: String
    var text: String
    var dateISO: String?
    var moodPercent: Int?
    var targetID: String?
    var minutes: Int?
    var weekdays: [Int]
    var tags: [String]?
    var options: AIBuddyActionOptions?
    var date: Date? { dateISO.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var valid: Bool {
        guard (options?.valid ?? true), (tags ?? []).count <= 15, (tags ?? []).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 60 }), title.count <= 160, text.count <= 6000, (dateISO == nil || date != nil), (moodPercent == nil || (0...100).contains(moodPercent!)), weekdays.allSatisfy({ (1...7).contains($0) }) else { return false }
        if ![AIBuddyActionKind.note, .checkIn].contains(kind), !(tags ?? []).isEmpty { return false }
        if options?.times != nil && ![AIBuddyActionKind.routine, .updateRoutine].contains(kind) { return false }
        if options?.priority != nil && kind != .goal { return false }
        if kind == .startSession { return targetID.flatMap(UUID.init(uuidString:)) != nil }
        if kind == .battery { return moodPercent != nil }
        if kind == .setting { return AIBuddySettingsChange.valid(action: self) }
        if kind == .guidedCheckIn { return targetID == "current" || targetID == "free" || targetID.flatMap(UUID.init(uuidString:)) != nil }
        if kind == .energy { return !title.isEmpty && ["gives", "takes"].contains(targetID ?? "") }
        if [.updateTask, .updateRoutine, .deleteTask, .deleteRoutine].contains(kind) { return targetID.flatMap(UUID.init(uuidString:)) != nil && (kind == .deleteTask || kind == .deleteRoutine || !title.isEmpty) }
        if kind == .task, options?.repeatEveryWeeks != nil, options?.repeatCount == nil { return false }
        if (options?.repeatCount ?? 1) > 1 && options?.repeatEveryWeeks == nil { return false }
        if kind == .openScreen { return BuddyDestinations.ids.contains(targetID ?? "") }
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
    var tags: [String]?
    var quickReplies: [BuddyQuickReply]?
    var memory: String?
    var valid: Bool { (quickReplies ?? []).count <= 3 && (quickReplies ?? []).allSatisfy(\.valid) && (memory?.count ?? 0) <= 1800 && (tags ?? []).count <= 12 && (tags ?? []).allSatisfy { !$0.isEmpty && $0.count <= 60 } && (checkIn?.valid ?? true) && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.count <= 12000 && title.count <= 160 && sections.count <= 8 && actions.count <= 6 && Set(actions.map(\.id)).count == actions.count && actions.allSatisfy(\.valid) && sections.allSatisfy { $0.heading.count <= 160 && $0.text.count <= 6000 } && (suggestedDays == nil || (1...90).contains(suggestedDays!)) }
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
        if q.contains("gestern") || q.contains("heute") || q.contains("tagesrückblick") { return 1 }
        if q.contains("woche") { return 7 }
        if q.contains("monat") { return 30 }
        return max(1, min(90, settings.contextDays))
    }
    static func requestDays(question: String, settings: AIBuddySettings, chosenDays: Int?) -> Int {
        let explicit = question.range(of: "(?i)gestern|heute|tagesrückblick|woche|monat|\\b[0-9]{1,2}\\s+tage", options: .regularExpression) != nil
        if explicit && settings.automaticRange { return resolvedDays(question: question, settings: settings) }
        return max(1, min(90, chosenDays ?? settings.contextDays))
    }
    static func make(data: AppData, days: Int, end: Date = Date(), calendar: Calendar = .current, question: String = "", clock: Date? = nil) -> AIBuddyContext {
        let days = max(1, min(90, days)), lastDay = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: lastDay)!
        let formatter = ISO8601DateFormatter()
        let requestTime = clock ?? end
        let intent = question.lowercased()
        let settingsIntent = ["einstellung", "design", "hauptfarbe", "app-farbe", "oberfläche"].contains(where: intent.contains)
        let broad = question.isEmpty || ["übersicht", "zusammen", "rückblick", "heute", "gestern", "woche", "monat", "struktur"].contains(where: intent.contains)
        let words = intent.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 3 }
        let records = ArchiveRecord.all(in: data).filter { $0.date >= start && $0.date <= end }.filter { record in
            if case .media = record { return false } // Binary media is strictly opt-in, outside automatic context.
            if !data.aiSettings.includeJournal, case .note = record { return false }
            return true
        }.sorted { lhs, rhs in
            if !broad {
                let a = words.filter { (lhs.title + " " + lhs.subtitle).lowercased().contains($0) }.count
                let b = words.filter { (rhs.title + " " + rhs.subtitle).lowercased().contains($0) }.count
                if a != b { return a > b }
            }
            return lhs.date > rhs.date
        }
        var lines: [String] = [], characters = 0
        for record in records.prefix(settingsIntent ? 0 : broad ? 60 : 12) {
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
            guard characters + line.count <= (question.isEmpty ? 18000 : 8000) else { break }
            lines.append(line); characters += line.count
        }
        let period = WellnessPeriod.rolling(days: days, now: end)
        let daily = WellnessAnalytics.daily(data, period: period)
        let moods = daily.compactMap(\.mood)
        let average = WellnessAnalytics.average(moods).map { String(format: "%.1f/5", $0) } ?? "keine Werte"
        let trend = InsightsAnalytics.trend(data: data, period: period).map { String(format: "%+.2f", $0) } ?? "zu wenige Werte"
        let next = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: requestTime).map(formatter.string) ?? "keiner"
        let occurrences: [RoutineOccurrence] = RoutinePlanner.due(data: data, now: requestTime)
        var dueLines: [String] = []
        for occurrence in occurrences.prefix(12) {
            let routine: DailyRoutine? = data.routines.first(where: { $0.id == occurrence.routineID })
            let title: String = routine?.title ?? "Routine"
            dueLines.append(occurrence.id + " | " + title)
        }
        let due: String = dueLines.joined(separator: "\n")
        var taskLines: [String] = []
        for task in data.weeklyTasks.filter({ !$0.completed }).prefix(15) {
            let clock = TaskReminderPlanner.settings(for: task, schedule: data.schedule)
            taskLines.append(task.id.uuidString + " | " + task.title + " | " + String(task.details.prefix(500)) + " | " + (task.dueDate.map(formatter.string) ?? "Kein Termin") + " | Erinnerung " + String(format: "%02d:%02d", clock.hour, clock.minute) + " Tage " + clock.weekdays.map(String.init).joined(separator: ","))
        }
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
        text += ", \(days) Kalendertage. __SENT__ Einträge, __OMITTED__ aus Platzgründen oder nach Relevanz nicht enthalten."
        text += " Selbstberichtete Tagesmittel: \(average) bei \(moods.count) Tagen mit Stimmung; Trend \(trend) auf Skala 1–5, keine Diagnose."
        text += " Nächste Therapie: " + next
        text += "\nBEKANNTE HASHTAGS (Namen wiederverwenden): " + String(AppHashtags.catalog(data).prefix(80).joined(separator: ", ").prefix(1500))
        text += "\nLOKALE ZEIT: " + requestTime.formatted(date: .complete, time: .shortened) + " · Zeitzone " + TimeZone.current.identifier
        text += "\nCHECK-IN-FENSTER (aktueller Stand, IDs für guidedCheckIn):\n"
        for slot in DayCheckInPolicy.slots(data.companionSettings).filter({ $0.enabled }).prefix(12) {
            let existing = DayCheckInPolicy.existing(for: DayCheckInPolicy.entry(slot, at: requestTime), in: data)
            let state = existing.map { $0.isDraft ? "Entwurf fortsetzen" : "Bereits abgeschlossen; nur öffnen" } ?? (slot.contains(requestTime) ? "Jetzt verfügbar" : "Außerhalb des Zeitfensters")
            text += slot.id.uuidString + " | " + slot.title + " | " + slot.windowText + " | " + state + "\n"
        }
        let planning = broad || ["routine", "aufgabe", "erinner", "alarm", "tablett", "termin", "therapie", "ziel"].contains(where: intent.contains)
        if planning {
            text += "\nROUTINEN (IDs):\n" + data.routines.prefix(12).map { $0.id.uuidString + " | " + $0.title + " | " + String($0.details.prefix(160)) + " | " + ($0.enabled ? "aktiv" : "pausiert") + " | " + $0.times.map { String(format: "%02d:%02d", $0.hour, $0.minute) + " Tage " + $0.weekdays.map(String.init).joined(separator: ",") }.joined(separator: "; ") }.joined(separator: "\n")
            text += "\nFÄLLIGE ROUTINEN:\n" + due + "\nOFFENE AUFGABEN:\n" + String(openTasks.prefix(3000))
        }
        if broad || intent.contains("therapie") || intent.contains("runde") || intent.contains("stunde") {
            text += "\nTHERAPIEVORLAGEN (startSession-IDs):\n" + data.sessionTemplates.filter(\.isValid).prefix(8).map { $0.id.uuidString + " | " + $0.title }.joined(separator: "\n")
            text += "\nGESPRÄCHSPUNKTE:\n" + String(topics.prefix(2500))
        }
        if question.isEmpty || ["einstellung", "design", "farbe", "kontext", "vorlesen", "oberfläche"].contains(where: intent.contains) {
            text += "\nEINSTELLUNGEN:\n" + (AIBuddySettingsChange.booleanKeys + ["ai.contextDays", "appearance.accent"]).map { $0 + " | " + AIBuddySettingsChange.value($0, data: data) }.joined(separator: "\n")
        }
        text = BuddyInteraction.completeLines(text, limit: question.isEmpty ? 7000 : 5000)
        text += "\nNative Bereiche: " + BuddyDestinations.catalogue + "\nEINTRÄGE:\n"
        var sent = 0
        for line in lines {
            guard text.count + line.count + 1 <= (question.isEmpty ? 25000 : 13500) else { break }
            text += line + "\n"; sent += 1
        }
        text = text.replacingOccurrences(of: "__SENT__", with: String(sent)).replacingOccurrences(of: "__OMITTED__", with: String(records.count - sent))
        return .init(start: start, end: end, days: days, recordCount: sent, omittedCount: records.count - sent, text: text)
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
    var draftText: String?
    var memory: String?
    var tags: [String]?
    var sessionID: UUID?
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
        clean(data.hashtagCatalog + data.notes.flatMap(\.tags) + data.media.flatMap(\.tags) + data.guidedCheckIns.flatMap { $0.tags ?? [] } + data.aiConversations.flatMap { $0.tags ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func tags(_ record: ArchiveRecord) -> [String] {
        switch record { case .note(let n): n.tags; case .media(let m): m.tags; case .guided(let c): c.tags ?? []; default: [] }
    }
}
struct AIBuddyCheckInProposal: Codable, Equatable {
    var advance: Bool?
    var finish: Bool?
    var moodPercent: Int?
    var batteryPercent: Int?
    var satisfaction: Int?
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
        let scales = [stress, sensoryLoad, satisfaction].compactMap { $0 }
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
        "Was ist heute wichtig? Gab es einen kleinen Erfolg, wie zufrieden bist du (1–5) und was brauchst du jetzt?",
        "Welche kleinen nächsten Schritte möchtest du festhalten? Noch wird keine Aufgabe angelegt.",
        "Was möchtest du in deiner nächsten Therapie besprechen?",
        "Schau dir deine Übersicht an. Du kannst alles bearbeiten und erst danach abschließen."
    ]
    static func instructions(_ entry: GuidedCheckIn) -> String {
        let step = max(0, min(7, entry.step))
        var result = "\nKI-GEFÜHRTER CHECK-IN. Aktuelle Standardfrage: " + questions[step]
        result += "\nDeute ausschließlich Angaben aus der aktuellen Nutzerantwort als Daten. Auch ausdrücklich genannte Angaben zu späteren Fragen dürfen übernommen werden. checkIn enthält nur belegte Angaben, sonst null. Kein Ergänzen aus älteren Einträgen. Stimmung vorsichtig vorschlagen, immer überprüfbar. tasks nur explizite gewünschte Schritte, tags bekannte Hashtags bevorzugen. Alle Fragen sind freiwillig; 'überspringen' ergibt null. Keine actions für separate Kopien dieses Check-ins."
        result += "\nBei einer Rückfrage, Unklarheit oder Wunsch weiter darüber zu sprechen: advance=false, bleibe freundlich bei derselben Frage. Nur bei beantworteter Frage oder ausdrücklichem Überspringen advance=true. Antworte persönlich und knapp mit einem Bezug auf reale letzte Einträge, ohne neue Angaben in den Entwurf zu erfinden. Die Standardfrage steht bereits in der festen Leiste: nicht wörtlich wiederholen, sondern genau eine persönliche passende Frage stellen. Bei Speichern-/Abschlusswunsch finish=true und eine kurze Einladung zur Übersicht, nicht behaupten gespeichert zu haben. Beim letzten Schritt nur zur Übersicht einladen; Korrekturen bleiben möglich. Dann die passende nächste Standardfrage: " + questions[min(7, step + 1)]
        if let encoded = try? JSONEncoder().encode(entry), let text = String(data: encoded, encoding: .utf8) { result += "\nAKTUELLER ENTWURF: " + String(text.prefix(6000)) }
        return result
    }
    static func apply(_ proposal: AIBuddyCheckInProposal, to entry: inout GuidedCheckIn, known: [String]) -> Bool {
        guard entry.isDraft, proposal.valid else { return false }
        if let v = proposal.summary { entry.summary = v }
        if let v = proposal.moodPercent { entry.moodPercent = v; entry.mood = MoodBarometer.score(v) }
        if let v = proposal.batteryPercent { entry.batteryPercent = v }
        if let v = proposal.givesEnergy { entry.givesEnergy = v }
        if let v = proposal.takesEnergy { entry.takesEnergy = v }
        if let v = proposal.satisfaction { entry.satisfaction = v }
        if let v = proposal.stress { entry.stress = v }
        if let v = proposal.sensoryLoad { entry.sensoryLoad = v }
        if let v = proposal.sleepHours { entry.sleepHours = v }
        if let v = proposal.smallWin { entry.smallWin = v }
        if let v = proposal.nextNeed { entry.nextNeed = v }
        if let v = proposal.therapyQuestion { entry.therapyQuestion = v }
        for title in proposal.tasks ?? [] where !title.isEmpty && !entry.tasks.contains(where: { $0.title == title }) { entry.tasks.append(CheckInTaskDraft(title: title)) }
        entry.tags = AppHashtags.clean((entry.tags ?? []) + (proposal.tags ?? []), known: known)
        if proposal.finish == true { entry.step = 7 }
        else if proposal.advance != false { entry.step = min(7, entry.step + 1) }
        return true
    }
}
enum AIConversationMutation {
    static func create(in data: inout AppData, checkIn: GuidedCheckIn? = nil, note: TherapyNote? = nil) -> UUID {
        let checkIn = checkIn.map { DayCheckInPolicy.reopen($0, in: data) }
        if let checkIn, let existing = data.aiConversations.first(where: { $0.checkInID == checkIn.id }) { return existing.id }
        let candidateTitle = checkIn?.displayTitle ?? note?.title ?? "Neues Gespräch"
        let conversation = AIBuddyConversation(title: candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Neues Gespräch" : candidateTitle, checkInID: checkIn?.id, noteContext: note, sessionID: checkIn?.sessionID ?? note?.sessionID ?? data.currentSession?.id)
        if let checkIn, checkIn.isDraft { _ = GuidedCheckInMutation.apply(checkIn, complete: false, to: &data) }
        data.aiConversations.insert(conversation, at: 0)
        if let checkIn, checkIn.isDraft { data.aiMessages.append(AIBuddyMessage(role: "assistant", text: "Ich begleite dich Schritt für Schritt. Die aktuelle Frage und deinen Fortschritt siehst du in der festen Leiste. Du kannst jederzeit zur Übersicht wechseln, Fragen auslassen oder normal fortsetzen.", conversationID: conversation.id)) }
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


struct AppEditorDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: String
    var title: String
    var updatedAt = Date()
    var payload: Data
    static func make<T: Encodable>(_ value: T, id: UUID, kind: String, title: String) throws -> Self {
        .init(id: id, kind: kind, title: title, payload: try JSONEncoder().encode(value))
    }
    func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: payload) }
}
extension GuidedCheckIn {
    var hasUserContent: Bool {
        mood != nil || moodPercent != nil || batteryPercent != nil || satisfaction != nil || stress != nil || sensoryLoad != nil || sleepHours != nil ||
        [summary, givesEnergy, takesEnergy, smallWin, nextNeed, therapyQuestion].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
        tasks.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || !mediaIDs.isEmpty || !(energyPoints ?? []).isEmpty
    }
}
extension AIConversationMutation {
    static func removeIfEmpty(_ id: UUID, in data: inout AppData) {
        guard let chat = data.aiConversations.first(where: { $0.id == id }),
              (chat.draftText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !data.aiMessages.contains(where: { $0.conversationID == id && $0.role == "user" }) else { return }
        if let checkID = chat.checkInID {
            guard !data.guidedCheckIns.contains(where: { $0.id == checkID && (!$0.isDraft || $0.hasUserContent) }) else { return }
            data.guidedCheckIns.removeAll { $0.id == checkID && $0.isDraft }
        }
        delete(id, in: &data)
    }
}


struct AIBuddyActionOptions: Codable, Equatable {
    var remindersEnabled: Bool?
    var alarmEnabled: Bool?
    var retryMinutes: Int?
    var repeatEveryWeeks: Int?
    var repeatCount: Int?
    var enabled: Bool?
    var valueBool: Bool?
    var valueInt: Int?
    var valueString: String?
    var priority: String?
    var times: [Int]?
    // Keep identities of pre-3011 proposals intact after Codable adds optional fields.
    var stableIdentity: String {
        let legacy = "AIBuddyActionOptions(remindersEnabled: \(String(describing: remindersEnabled)), alarmEnabled: \(String(describing: alarmEnabled)), retryMinutes: \(String(describing: retryMinutes)), repeatEveryWeeks: \(String(describing: repeatEveryWeeks)), repeatCount: \(String(describing: repeatCount)), enabled: \(String(describing: enabled)), valueBool: \(String(describing: valueBool)), valueInt: \(String(describing: valueInt)))"
        guard valueString != nil || priority != nil || times != nil else { return legacy }
        return legacy + "|string=" + (valueString ?? "") + "|priority=" + (priority ?? "") + "|times=" + (times ?? []).map(String.init).joined(separator: ",")
    }
    var valid: Bool {
        (priority == nil || ["low", "normal", "high"].contains(priority!)) &&
        (valueString == nil || valueString!.count <= 60) && (times == nil || (!times!.isEmpty && times!.count <= 8 && Set(times!).count == times!.count && times!.allSatisfy { (0...1439).contains($0) })) &&
        (retryMinutes == nil || (5...180).contains(retryMinutes!)) &&
        (repeatEveryWeeks == nil || (1...52).contains(repeatEveryWeeks!)) &&
        (repeatCount == nil || (1...52).contains(repeatCount!)) &&
        (valueInt == nil || (1...90).contains(valueInt!))
    }
}
enum AIBuddySettingsChange {
    static let booleanKeys = ["ai.preferGuidedCheckIns", "ai.automaticRange", "ai.weeklyReview", "dashboard.compactCards", "dashboard.showWidgetTitles", "reminders.privateTaskTitles", "companion.privateRoutineTitles", "ai.speakReplies"]
    static func valid(action: AIBuddyAction) -> Bool {
        guard let key = action.targetID else { return false }
        if key == "appearance.accent" { return action.options?.valueString.flatMap(AppAccent.init(rawValue:)) != nil }
        if key == "ai.contextDays" { return action.options?.valueInt.map { (1...90).contains($0) } ?? false }
        return booleanKeys.contains(key) && action.options?.valueBool != nil
    }
    static func value(_ key: String, data: AppData) -> String {
        switch key {
        case "appearance.accent": return data.accentTheme.title
        case "ai.speakReplies": return data.aiSettings.speakReplies ? "An" : "Aus"
        case "ai.contextDays": return "\(data.aiSettings.contextDays) Tage"
        case "ai.preferGuidedCheckIns": return data.aiSettings.preferGuidedCheckIns ? "An" : "Aus"
        case "ai.automaticRange": return data.aiSettings.automaticRange ? "An" : "Aus"
        case "ai.weeklyReview": return data.aiSettings.weeklyReviewEnabled ? "An" : "Aus"
        case "dashboard.compactCards": return data.dashboard.compactCards ? "An" : "Aus"
        case "dashboard.showWidgetTitles": return data.dashboard.showWidgetTitles ? "An" : "Aus"
        case "reminders.privateTaskTitles": return data.reminderPreferences.privateTaskTitles ? "An" : "Aus"
        case "companion.privateRoutineTitles": return data.companionSettings.privateRoutineTitles ? "An" : "Aus"
        default: return "Unbekannt"
        }
    }
}

struct MoodEntryDraft: Codable, Equatable { var entry: MoodCheckIn; var points: [BatteryPoint] }

// Small, explicit capability catalogue: settings without a safe mutation open their native editor.
enum BuddyDestinations {
    static let names: [String: String] = ["today": "Heute", "insights": "Stimmung und Auswertung", "therapy": "Therapiethemen und Ziele", "archive": "Archiv", "session": "Therapierunde und Timer", "routines": "Routinen", "appointments": "Therapieintervalle und Termine", "reminders": "Erinnerungen", "settings": "Alle App-Einstellungen, Profil und Datenschutz", "appearance": "Design, Hell/Dunkel, Haptik und Konfetti", "dashboard": "Startseite und Widgets", "wellness": "Stimmungsziele und Freigaben", "backup": "Export und Import", "ai": "KI-Schlüssel, Modelle und Upload-Freigaben", "checkins": "Check-in-Rhythmus und Zeitfenster", "sessionSettings": "Timer, Phasen und Begleitung", "profile": "Aktueller Akku und Befinden"]
    static var ids: [String] { names.keys.sorted() }
    static var catalogue: String { ids.map { $0 + ": " + (names[$0] ?? $0) }.joined(separator: "; ") }
}
enum AppAccent: String, Codable, CaseIterable, Identifiable {
    case indigo, blue, purple, red, teal, green, rose, amber
    var id: String { rawValue }
    var title: String { switch self { case .indigo: "Indigo"; case .blue: "Blau"; case .purple: "Lila"; case .red: "Rot"; case .teal: "Petrol"; case .green: "Grün"; case .rose: "Rosa"; case .amber: "Bernstein" } }
}
struct BuddyQuickReply: Codable, Equatable, Identifiable {
    var title: String
    var text: String
    var id: String { title + "|" + text }
    var valid: Bool { !title.isEmpty && title.count <= 40 && !text.isEmpty && text.count <= 600 }
}
enum BuddyInteraction {
    static func completeLines(_ text: String, limit: Int) -> String {
        var lines: [String] = [], count = 0
        for line in text.components(separatedBy: "\n") { guard count + line.count + 1 <= limit else { break }; lines.append(line); count += line.count + 1 }
        return lines.joined(separator: "\n") + (text.count > limit ? "\n[Weitere Kontextdaten aus Platzgründen ausgelassen.]" : "")
    }
    static func withoutPinnedQuestion(_ text: String, step: Int) -> String {
        let result = text.replacingOccurrences(of: AICheckInGuide.questions[max(0, min(7, step))], with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Deine Angaben sind angekommen. Die nächste Frage findest du oben; zur Übersicht kannst du jederzeit wechseln." : result
    }
    static func wantsOverview(_ text: String) -> Bool {
        let t = text.lowercased()
        guard !t.contains("nicht speichern"), !t.contains("noch nicht"), !t.contains("nicht abschließen") else { return false }
        return t.range(of: "(check.?in|checkin).*(speichern|abschließen|beenden|übersicht)|(speichern|abschließen|beenden|übersicht).*(check.?in|checkin)|^(bitte )?(jetzt )?(speichern|abschließen|zur übersicht)[.! ]*$", options: .regularExpression) != nil
    }
    static func window(question: String, days: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let t = question.lowercased()
        let offset = t.contains("vorgestern") ? 2 : t.contains("gestern") ? 1 : 0
        guard offset > 0, let day = calendar.date(byAdding: .day, value: -offset, to: now), let interval = calendar.dateInterval(of: .day, for: day) else { return now }
        return interval.end.addingTimeInterval(-0.001)
    }
    static func history(_ messages: [AIBuddyMessage], limit: Int = 6500) -> [[String: String]] {
        var result: [[String: String]] = [], remaining = limit
        for message in messages.suffix(8).reversed() where ["user", "assistant"].contains(message.role) {
            guard remaining > 0 else { break }
            var value = String(message.text.prefix(min(1200, remaining)))
            if let reply = message.reply, remaining - value.count > 0 {
                let actions = reply.actions.prefix(4).map { $0.kind.rawValue + " | " + $0.title + " | " + ($0.targetID ?? "") + " | " + (message.appliedActionIDs.contains($0.id) ? "bestätigt" : "Vorschlag") }.joined(separator: "\n")
                value += String(("\nAKTIONEN:\n" + actions).prefix(max(0, min(600, remaining - value.count))))
            }
            remaining -= value.count; result.append(["role": message.role, "content": value])
        }
        return result.reversed()
    }
    static func transcript(_ messages: [AIBuddyMessage]) -> String {
        messages.map { ($0.role == "user" ? "Du" : "Begleiter") + " · " + $0.date.formatted(date: .abbreviated, time: .shortened) + "\n" + AIBuddyText.plain($0.text) }.joined(separator: "\n\n")
    }
    static func boundedTranscript(_ messages: [AIBuddyMessage], limit: Int = 14000) -> String {
        let raw = transcript(messages)
        guard raw.count > limit else { return raw }
        return String(raw.prefix(limit / 3)) + "\n[Mittlerer Verlauf aus Platzgründen ausgelassen; lokales Detail enthält alles.]\n" + String(raw.suffix(limit * 2 / 3 - 110))
    }
    static func hashtags(_ values: [String], text: String, known: [String]) -> [String] {
        let content = AppHashtags.key(text)
        let matches = known.filter { let key = AppHashtags.key($0); return key.count > 2 && content.contains(key) }
        let vocabulary: [(String, [String])] = [("Familie", ["schwester", "bruder", "mutter", "vater", "familie"]), ("Schlaf", ["schlaf", "mude"]), ("Stress", ["stress", "uberfordert"]), ("Erholung", ["pause", "erholung", "auftanken"]), ("Arbeit", ["arbeit", "beruf"]), ("Freude", ["freude", "glucklich"]), ("Grenzen", ["grenzen", "nein sagen"])]
        let inferred = vocabulary.filter { $0.1.contains(where: content.contains) }.map(\.0)
        return Array(AppHashtags.clean(values + matches + inferred, known: known).prefix(12))
    }
}

extension AIConversationMutation {
    static func saveSummary(_ id: UUID, title: String, summary: String, tags: [String], in data: inout AppData) {
        guard let index = data.aiConversations.firstIndex(where: { $0.id == id }) else { return }
        let messages = data.aiMessages.filter { $0.conversationID == id }
        guard messages.contains(where: { $0.role == "user" }), !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cleanTags = AppHashtags.clean(tags, known: AppHashtags.catalog(data))
        let transcript = BuddyInteraction.transcript(messages)
        if let saved = data.aiConversations[index].savedNoteID, let n = data.notes.firstIndex(where: { $0.id == saved }) {
            data.notes[n].title = AIBuddyText.plain(title); data.notes[n].text = AIBuddyText.plain(summary); data.notes[n].tags = cleanTags
            data.notes[n].conversationID = id; data.notes[n].conversationTranscript = transcript; data.notes[n].updatedAt = Date()
        } else {
            let note = TherapyNote(title: AIBuddyText.plain(title), text: AIBuddyText.plain(summary), tags: cleanTags, sessionID: data.aiConversations[index].sessionID, category: "Therapietagebuch", conversationID: id, conversationTranscript: transcript)
            data.notes.insert(note, at: 0); data.aiConversations[index].savedNoteID = note.id
        }
        data.aiConversations[index].savedMessageCount = messages.count; data.hashtagCatalog = AppHashtags.catalog(data)
    }
}

struct WellbeingPreferences: Codable, Equatable {
    var estimateBattery = false
    var hourlyDecline = 0
    init() {}
    enum CodingKeys: String, CodingKey { case estimateBattery, hourlyDecline }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        estimateBattery = try c.decodeIfPresent(Bool.self, forKey: .estimateBattery) ?? false
        hourlyDecline = max(0, min(10, try c.decodeIfPresent(Int.self, forKey: .hourlyDecline) ?? 0))
    }
}
struct WellbeingReading {
    var date: Date
    var value: Int
}
enum WellbeingProfile {
    static func battery(_ data: AppData, now: Date = Date(), start: Date = .distantPast) -> WellbeingReading? {
        let guided = data.guidedCheckIns.filter { !$0.isDraft }.compactMap { entry in entry.batteryPercent.map { WellbeingReading(date: entry.date, value: $0) } }
        let energy = data.energyEntries.map { WellbeingReading(date: $0.createdAt, value: $0.percent ?? (($0.level - 1) * 25)) }
        let mood = data.moodCheckIns.map { WellbeingReading(date: $0.date, value: ($0.battery - 1) * 25) }
        return (guided + energy + mood).filter { $0.date >= start && $0.date <= now }.max { $0.date < $1.date }
    }
    static func estimatedBattery(_ data: AppData, reading: WellbeingReading, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard data.wellbeingPreferences.estimateBattery, calendar.isDate(reading.date, inSameDayAs: now), now >= reading.date else { return max(0, min(100, reading.value)) }
        let points = data.batteryPoints.filter { $0.date > reading.date && $0.date <= now }.reduce(0) { $0 + $1.signedImpact * 5 }
        let decline = Int(now.timeIntervalSince(reading.date) / 3600 * Double(data.wellbeingPreferences.hourlyDecline))
        return max(0, min(100, reading.value + points - decline))
    }
}
