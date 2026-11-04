import Foundation

// MARK: - Kompass AI (pure Foundation)
//
// The companion's knowledge of Betreutes Wohnen and quiet mode: action validation and application, a compact
// context section, and a local German date detector that also works without any AI.

struct KompassAIError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum KompassAI {
    static let kinds: Set<AIBuddyActionKind> = [.bewoAppointment, .bewoTopic, .bewoAgreement, .bewoGoal, .bewoSummary, .discussBewoTopic, .quietStart, .quietEnd]

    /// Kinds that a single tap may save directly from the chat: additive or easily reversible, previewed on the card.
    static let quickApply: Set<AIBuddyActionKind> = [.note, .topic, .energy, .bewoAppointment, .bewoTopic, .bewoAgreement, .bewoGoal, .bewoSummary, .discussBewoTopic, .quietStart, .quietEnd, .discussTopic, .appointment, .goal]

    // MARK: Validation

    /// `nil` when the action is not a Kompass kind; otherwise whether it is well formed.
    static func validity(_ action: AIBuddyAction) -> Bool? {
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let uuid = action.targetID.flatMap(UUID.init(uuidString:))
        let string = action.options?.valueString
        switch action.kind {
        case .bewoAppointment:
            return action.date != nil && (action.minutes.map { (5...600).contains($0) } ?? true) && (string.map { AssistedLivingVisitKind(rawValue: $0) != nil } ?? true)
        case .bewoTopic:
            return !title.isEmpty && (string.map { AssistedLivingTopicCategory(rawValue: $0) != nil } ?? true)
        case .bewoAgreement:
            return !title.isEmpty && (action.targetID == nil || uuid != nil) && (string.map { AssistedLivingOwner(rawValue: $0) != nil } ?? true)
        case .bewoGoal:
            return !title.isEmpty
        case .bewoSummary:
            return uuid != nil && (!action.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (action.options?.valueInt.map { (1...5).contains($0) } ?? false))
        case .discussBewoTopic:
            return uuid != nil
        case .quietStart:
            return (action.options?.categories ?? []).allSatisfy { ReminderCategory(rawValue: $0) != nil } && (action.minutes.map { (5...43200).contains($0) } ?? true)
        case .quietEnd:
            return action.targetID == nil || uuid != nil
        default:
            return nil
        }
    }

    // MARK: Application

    /// Appointment a topic, agreement or summary belongs to when the model names none: the visit happening now or
    /// most recently, otherwise the next stored one.
    static func defaultAppointment(_ data: AppData, now: Date) -> AssistedLivingAppointment? {
        let recent = data.assistedLivingAppointments.filter { $0.status != .cancelled && $0.date <= now.addingTimeInterval(3600) }.max { $0.date < $1.date }
        if let recent, now.timeIntervalSince(recent.date) < 7 * 86400 { return recent }
        return data.assistedLivingAppointments.filter { $0.status == .planned && $0.date > now }.min { $0.date < $1.date } ?? recent
    }

    static func apply(_ action: AIBuddyAction, to data: inout AppData, now: Date = Date()) throws {
        let title = AIBuddyText.plain(action.title), text = AIBuddyText.plain(action.text)
        let settings = data.assistedLivingSettings
        switch action.kind {
        case .bewoAppointment:
            guard let date = action.date, date > now.addingTimeInterval(-60) else { throw KompassAIError(message: "Der BeWo-Termin liegt in der Vergangenheit. Bitte prüfe Datum und Uhrzeit.") }
            guard !data.assistedLivingAppointments.contains(where: { $0.status != .cancelled && abs($0.date.timeIntervalSince(date)) < 60 }) else { throw KompassAIError(message: "Zu dieser Zeit ist bereits ein BeWo-Termin eingetragen.") }
            let kind = action.options?.valueString.flatMap(AssistedLivingVisitKind.init(rawValue:)) ?? .homeVisit
            var appointment = AssistedLivingAppointment(date: date, durationMinutes: action.minutes ?? settings.defaultDurationMinutes, title: title.isEmpty ? "BeWo-Termin" : String(title.prefix(120)), kind: kind,
                                                        caregiver: settings.caregiverName, location: kind == .homeVisit ? settings.defaultLocation : "", preparation: text,
                                                        topicIDs: data.assistedLivingTopics.filter { $0.status == .next }.map(\.id), createdAt: now)
            appointment.updatedAt = now
            data.assistedLivingAppointments.append(appointment)
            data.assistedLivingAppointments.sort { $0.date > $1.date }
        case .bewoTopic:
            var topic = AssistedLivingTopic(createdAt: now, title: String(title.prefix(160)), details: text, category: action.options?.valueString.flatMap(AssistedLivingTopicCategory.init(rawValue:)) ?? .everyday,
                                            priority: ["low": 1, "normal": 2, "high": 3][action.options?.priority ?? "normal"] ?? 2, status: .next)
            topic.updatedAt = now
            guard !data.assistedLivingTopics.contains(where: { $0.status.isOpen && AppHashtags.key($0.title) == AppHashtags.key(topic.title) }) else { throw KompassAIError(message: "Dieses Thema steht schon auf deiner BeWo-Liste.") }
            data.assistedLivingTopics.insert(topic, at: 0)
        case .bewoAgreement:
            let target = action.targetID.flatMap(UUID.init(uuidString:)) ?? defaultAppointment(data, now: now)?.id
            guard let target, let index = data.assistedLivingAppointments.firstIndex(where: { $0.id == target }) else { throw KompassAIError(message: "Lege zuerst einen BeWo-Termin an, damit die Absprache dort stehen kann.") }
            data.assistedLivingAppointments[index].agreements.append(AssistedLivingAgreement(title: String(title.prefix(160)), owner: action.options?.valueString.flatMap(AssistedLivingOwner.init(rawValue:)) ?? .me, dueDate: action.date))
            data.assistedLivingAppointments[index].updatedAt = now
        case .bewoGoal:
            let steps = (action.options?.steps ?? []).map { AssistedLivingStep(title: String(AIBuddyText.plain($0).prefix(160))) }.filter { !$0.title.isEmpty }
            data.assistedLivingGoals.insert(AssistedLivingGoal(createdAt: now, title: String(title.prefix(160)), details: text, steps: Array(steps.prefix(20))), at: 0)
        case .bewoSummary:
            guard let id = action.targetID.flatMap(UUID.init(uuidString:)), let index = data.assistedLivingAppointments.firstIndex(where: { $0.id == id }) else { throw KompassAIError(message: "Dieser BeWo-Termin ist nicht mehr vorhanden.") }
            if !text.isEmpty {
                let previous = data.assistedLivingAppointments[index].summary
                data.assistedLivingAppointments[index].summary = previous.isEmpty ? text : previous + "\n\n" + text
            }
            if let mood = action.options?.valueInt, (1...5).contains(mood) { data.assistedLivingAppointments[index].moodAfter = mood }
            if data.assistedLivingAppointments[index].date <= now { data.assistedLivingAppointments[index].status = .done }
            data.assistedLivingAppointments[index].updatedAt = now
        case .discussBewoTopic:
            guard let id = action.targetID.flatMap(UUID.init(uuidString:)), let index = data.assistedLivingTopics.firstIndex(where: { $0.id == id }) else { throw KompassAIError(message: "Dieses BeWo-Thema ist nicht mehr vorhanden.") }
            if let appointment = defaultAppointment(data, now: now) {
                AssistedLivingPlanner.discuss(id, in: appointment.id, data: &data, outcome: text, now: now)
            } else {
                data.assistedLivingTopics[index].status = .discussed
                data.assistedLivingTopics[index].discussedAt = now
                if !text.isEmpty { data.assistedLivingTopics[index].outcome = text }
                data.assistedLivingTopics[index].updatedAt = now
            }
        case .quietStart:
            let areas = (action.options?.categories ?? []).compactMap(ReminderCategory.init(rawValue:))
            let until = action.date ?? action.minutes.map { now.addingTimeInterval(Double($0) * 60) }
            if let until, until <= now { throw KompassAIError(message: "Das Ende der Ruhe liegt in der Vergangenheit.") }
            QuietPolicy.pause(&data.quietMode, categories: areas, until: until, now: now, note: String(text.prefix(200)))
        case .quietEnd:
            if let id = action.targetID.flatMap(UUID.init(uuidString:)) {
                guard data.quietMode.pauses.contains(where: { $0.id == id && $0.isActive(at: now) }) else { throw KompassAIError(message: "Diese Ruhe ist bereits beendet.") }
                QuietPolicy.end(id, in: &data.quietMode, now: now)
            } else {
                guard !QuietPolicy.activePauses(data.quietMode, at: now).isEmpty else { throw KompassAIError(message: "Gerade ist keine Ruhe aktiv.") }
                QuietPolicy.endAll(&data.quietMode, now: now)
            }
        default:
            throw KompassAIError(message: "Diese Aktion gehört nicht zu Kompass.")
        }
    }

    /// The record a Kompass action changes, so the review can refuse to save over a newer version.
    static func targetSnapshot(_ action: AIBuddyAction, in data: AppData) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let id = action.targetID.flatMap(UUID.init(uuidString:))
        switch action.kind {
        case .bewoSummary, .bewoAgreement: return data.assistedLivingAppointments.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .discussBewoTopic: return data.assistedLivingTopics.first { $0.id == id }.flatMap { try? encoder.encode($0) }
        case .quietEnd: return try? encoder.encode(data.quietMode.pauses)
        default: return nil
        }
    }

    /// One human line for an action card, e.g. "Di, 10. Nov · 10:00 · 60 Min. · Hausbesuch".
    static func detail(_ action: AIBuddyAction, data: AppData, now: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "de_DE"); formatter.dateFormat = "EE d. MMM · HH:mm"
        let date = action.date.map(formatter.string)
        switch action.kind {
        case .bewoAppointment:
            let kind = action.options?.valueString.flatMap(AssistedLivingVisitKind.init(rawValue:)) ?? .homeVisit
            return [date, "\(action.minutes ?? data.assistedLivingSettings.defaultDurationMinutes) Min.", kind.title].compactMap { $0 }.joined(separator: " · ")
        case .appointment, .routine, .task, .postponeTask, .postponeRoutine:
            return date ?? ""
        case .bewoTopic:
            let category = action.options?.valueString.flatMap(AssistedLivingTopicCategory.init(rawValue:)) ?? .everyday
            return category.title + (action.options?.priority == "high" ? " · wichtig" : "")
        case .bewoAgreement:
            let owner = action.options?.valueString.flatMap(AssistedLivingOwner.init(rawValue:)) ?? .me
            return owner.title + (action.date.map { " · bis " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
        case .bewoGoal:
            let count = action.options?.steps?.count ?? 0
            return count == 0 ? "Ziel ohne Schritte" : "\(count) Schritte"
        case .bewoSummary, .discussBewoTopic:
            let topic = action.targetID.flatMap(UUID.init(uuidString:)).flatMap { id in data.assistedLivingTopics.first { $0.id == id }?.title }
            return topic ?? "Betreutes Wohnen"
        case .quietStart:
            let areas = (action.options?.categories ?? []).compactMap(ReminderCategory.init(rawValue:)).map(\.title)
            let until = action.date ?? action.minutes.map { now.addingTimeInterval(Double($0) * 60) }
            return (areas.isEmpty ? "Alles" : areas.joined(separator: ", ")) + " · " + (until.map { "bis " + QuietPolicy.shortStamp($0, now: now) } ?? "bis du sie beendest")
        case .quietEnd:
            return "Alle Erinnerungen melden sich wieder"
        default:
            return date ?? ""
        }
    }

    // MARK: Context

    static func wantsAssistedLiving(_ question: String) -> Bool {
        let q = question.lowercased()
        return ["bewo", "betreu", "hausbesuch", "betreuer", "betreuerin", "wohnen", "amt", "jobcenter", "brief", "post ", "antrag", "frist", "absprache", "vereinbar"].contains(where: q.contains)
    }
    static func wantsQuiet(_ question: String) -> Bool {
        let q = question.lowercased()
        return ["ruhe", "stumm", "nicht stören", "wecker", "mitteilung", "benachrichtig", "nervt", "pause von", "erinnerungen aus", "lautlos"].contains(where: q.contains)
    }

    /// One short line for the situation summary that is always sent.
    static func situationParts(_ data: AppData, now: Date, calendar: Calendar = .current) -> [String] {
        var parts: [String] = []
        if let visit = AssistedLivingPlanner.next(data, now: now, calendar: calendar) {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: visit.date)).day ?? 0
            parts.append("nächster BeWo-Termin " + (days <= 0 ? "heute" : days == 1 ? "morgen" : "in \(days) Tagen"))
        }
        let topics = AssistedLivingPlanner.openTopics(data).count
        if topics > 0 { parts.append("\(topics) offene BeWo-Themen") }
        if let pause = QuietPolicy.globalPause(data.quietMode, at: now) { parts.append("Ruhe aktiv" + (pause.until.map { " bis " + QuietPolicy.shortStamp($0, calendar: calendar, now: now) } ?? "")) }
        return parts
    }

    /// Compact, ID-bearing section; only the parts relevant to the question are included.
    static func context(_ data: AppData, question: String, now: Date, broad: Bool, calendar: Calendar = .current) -> String {
        let iso = ISO8601DateFormatter()
        var text = ""
        if broad || wantsAssistedLiving(question) || question.lowercased().contains("termin") {
            let settings = data.assistedLivingSettings
            var lines = ["BETREUTES WOHNEN (ambulant; Betreuer:in " + (settings.caregiverName.isEmpty ? "unbekannt" : settings.caregiverName) + ", übliche Dauer \(settings.defaultDurationMinutes) Min.; Arten " + AssistedLivingVisitKind.allCases.map(\.rawValue).joined(separator: ",") + "):"]
            for visit in AssistedLivingPlanner.upcoming(data, now: now, days: 45, calendar: calendar).prefix(4) {
                lines.append("Termin " + (visit.appointmentID.map { "ID " + $0.uuidString } ?? "regelmäßig, noch nicht geöffnet") + " | " + iso.string(from: visit.date) + " | \(visit.durationMinutes) Min. | " + visit.kind.rawValue)
            }
            if let last = AssistedLivingPlanner.lastVisit(data, now: now) {
                lines.append("Letzter Termin ID " + last.id.uuidString + " | " + iso.string(from: last.date) + " | " + String(last.summary.prefix(300)))
            }
            for topic in AssistedLivingPlanner.openTopics(data).prefix(12) {
                lines.append("Thema-ID " + topic.id.uuidString + " | " + topic.status.rawValue + " | " + topic.category.rawValue + " | P\(topic.priority) | " + String(topic.title.prefix(120)) + (topic.details.isEmpty ? "" : " – " + String(topic.details.prefix(160))))
            }
            for entry in AssistedLivingPlanner.openAgreements(data).prefix(8) {
                lines.append("Absprache offen | " + entry.agreement.owner.rawValue + " | " + String(entry.agreement.title.prefix(120)) + (entry.agreement.dueDate.map { " | bis " + iso.string(from: $0) } ?? ""))
            }
            for goal in data.assistedLivingGoals.filter({ $0.completedAt == nil }).prefix(5) {
                lines.append("BeWo-Ziel | " + String(goal.title.prefix(100)) + " | \(Int(goal.progress * 100)) %")
            }
            lines.append("Themen-Bereiche: " + AssistedLivingTopicCategory.allCases.map(\.rawValue).joined(separator: ","))
            text += lines.joined(separator: "\n") + "\n"
        }
        if broad || wantsQuiet(question) {
            let quiet = data.quietMode
            var lines = ["RUHEMODUS (Bereiche " + ReminderCategory.allCases.map(\.rawValue).joined(separator: ",") + "):"]
            for pause in QuietPolicy.activePauses(quiet, at: now) {
                lines.append("Ruhe-ID " + pause.id.uuidString + " | " + (pause.isGlobal ? "alles" : pause.categories.map(\.rawValue).joined(separator: ",")) + " | bis " + (pause.until.map(iso.string) ?? "offen"))
            }
            if !quiet.mutedCategories.isEmpty { lines.append("Dauerhaft stumm: " + quiet.mutedCategories.map(\.rawValue).joined(separator: ",")) }
            if quiet.quietHours.enabled { lines.append("Tägliche Ruhezeit " + quiet.quietHours.label) }
            let upcoming = ReminderInventory.upcoming(data, now: now, days: 1, calendar: calendar).filter { !$0.isQuiet }.prefix(6)
            for item in upcoming { lines.append("Kommt bald: " + iso.string(from: item.fireAt) + " | " + item.category.rawValue + " | " + String(item.title.prefix(80))) }
            text += lines.joined(separator: "\n") + "\n"
        }
        return BuddyInteraction.completeLines(text, limit: 2600)
    }

    static let instructions = """
    BETREUTES WOHNEN: Der Nutzer wird ambulant zu Hause betreut (BeWo). bewoAppointment legt einen BeWo-Termin an: dateISO Beginn (Pflicht), minutes Dauer, options.valueString Art (homeVisit, phone, accompaniment, office, online, group), text Vorbereitung. bewoTopic: Gesprächsthema, options.valueString Bereich aus dem Kontext, options.priority low/normal/high. bewoAgreement: Absprache (wer macht was), options.valueString me/caregiver/together, dateISO Frist, targetID Termin-ID oder null für den aktuellen/letzten Termin. bewoGoal: Ziel mit options.steps. bewoSummary: Zusammenfassung eines Termins, targetID Termin-ID, options.valueInt Stimmung danach 1–5. discussBewoTopic: Thema-ID als besprochen markieren, text Ergebnis. Hilf beim Vorbereiten (Themen sortieren, Fragen formulieren, Unterlagen nennen) und Nachbereiten (Ergebnisse, Absprachen). Nutze nur Thema-/Termin-IDs aus dem Kontext.
    TERMINERKENNUNG: Nennt der Nutzer einen Termin mit Tag/Datum (z. B. „Dienstag um 10 kommt meine Betreuerin“, „am 12.11. um 14 Uhr Therapie“, „morgen Jobcenter um 9“), schlage sofort den passenden Termin als Aktion vor: BeWo/Betreuung → bewoAppointment; zusätzlicher Therapietermin → appointment; sonstige Erledigung mit Zeitpunkt → task mit dateISO. Rechne relative Angaben mit LOKALE ZEIT in ein exaktes dateISO mit Zeitzone um. Ist unklar, welche Art, biete bis zu zwei Varianten als getrennte actions an und frage kurz nach. Fehlt die Uhrzeit, frage danach statt zu raten.
    RUHE: quietStart pausiert Erinnerungen: minutes Dauer (z. B. 1440 für 24 Stunden) oder dateISO Ende, beides null = bis zum Beenden; options.categories Bereiche aus dem Ruhemodus-Kontext, null = alles. quietEnd beendet eine Ruhe (targetID Ruhe-ID oder null für alle). Wenn Wecker oder Hinweise nerven, biete passende Ruhe-Varianten an und den Bereich quiet.
    DARSTELLUNG: Antworte knapp und gut gegliedert. Biete passende quickReplies als nächste Schritte an. Aktionen werden als interaktive Karten mit Übernehmen-Knopf gezeigt; beschreibe sie nicht zusätzlich lang im Text.
    """
}

// MARK: - Local date detection (works without AI)

struct DetectedDate: Equatable {
    var date: Date
    var hasTime: Bool
    var hint: Hint
    enum Hint: String { case assistedLiving, therapy, other }
}

enum GermanDateDetector {
    private static let weekdays: [(String, Int)] = [("montag", 2), ("dienstag", 3), ("mittwoch", 4), ("donnerstag", 5), ("freitag", 6), ("samstag", 7), ("sonnabend", 7), ("sonntag", 1)]
    private static let months = ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]

    static func detect(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> DetectedDate? {
        let text = " " + raw.lowercased().replacingOccurrences(of: "\n", with: " ") + " "
        let today = calendar.startOfDay(for: now)
        var day: Date?
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<result.numberOfRanges).map { index in Range(result.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
        if let parts = match("(?<![0-9])([0-3]?[0-9])\\.([01]?[0-9])\\.(20[0-9]{2}|[0-9]{2})?(?![0-9])"), let d = Int(parts[1]), let m = Int(parts[2]), (1...31).contains(d), (1...12).contains(m) {
            var year = Int(parts[3]) ?? calendar.component(.year, from: now)
            if year < 100 { year += 2000 }
            if var candidate = calendar.date(from: DateComponents(year: year, month: m, day: d)) {
                if parts[3].isEmpty && candidate < today { candidate = calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate }
                day = candidate
            }
        }
        if day == nil, let parts = match("(?<![0-9])([0-3]?[0-9])\\.?\\s*(" + months.joined(separator: "|") + ")"), let d = Int(parts[1]), let m = months.firstIndex(of: parts[2]) {
            if var candidate = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: m + 1, day: d)) {
                if candidate < today { candidate = calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate }
                day = candidate
            }
        }
        if day == nil {
            if text.contains("übermorgen") { day = calendar.date(byAdding: .day, value: 2, to: today) }
            else if text.range(of: "\\bmorgen\\b(?!s)", options: .regularExpression) != nil && !text.contains("heute morgen") { day = calendar.date(byAdding: .day, value: 1, to: today) }
            else if text.range(of: "\\bheute\\b", options: .regularExpression) != nil { day = today }
        }
        var weekdayMatched = false
        if day == nil {
            for (name, weekday) in weekdays where text.range(of: "\\b" + name + "s?\\b", options: .regularExpression) != nil {
                if text.contains("nächste woche") || text.contains("kommende woche") {
                    var weeks = calendar; weeks.firstWeekday = 2; weeks.minimumDaysInFirstWeek = 4
                    let thisWeek = weeks.dateInterval(of: .weekOfYear, for: today)?.start ?? today
                    day = calendar.date(byAdding: .day, value: 7 + (weekday + 5) % 7, to: thisWeek)
                } else {
                    let current = calendar.component(.weekday, from: today)
                    var offset = (weekday - current + 7) % 7
                    if offset == 0 && (text.contains("nächsten " + name) || text.contains("kommenden " + name)) { offset = 7 }
                    day = calendar.date(byAdding: .day, value: offset, to: today)
                }
                weekdayMatched = true
                break
            }
        }
        guard var resolvedDay = day else { return nil }
        let explicitDate = !relativeOrWeekday(text)
        var hour: Int?, minute = 0
        if let parts = match("(?:um|ab|gegen)\\s+([0-2]?[0-9])(?:[:.]([0-5][0-9]))?(?:\\s*uhr)?"), let h = Int(parts[1]), (0...23).contains(h) {
            hour = h; minute = Int(parts[2]) ?? 0
        } else if let parts = match("(?<![0-9.])([0-2]?[0-9])(?:[:.]([0-5][0-9]))?\\s*(?:uhr|h)\\b"), let h = Int(parts[1]), (0...23).contains(h) {
            hour = h; minute = Int(parts[2]) ?? 0
        }
        if hour != nil, (text.contains("nachmittag") || text.contains("abends")), let h = hour, h < 12 { hour = h + 12 }
        var date = calendar.date(bySettingHour: hour ?? 9, minute: minute, second: 0, of: resolvedDay) ?? resolvedDay
        // "Dienstag um 10" on a Tuesday after 10:00 means next week.
        if weekdayMatched && hour != nil && date <= now { resolvedDay = calendar.date(byAdding: .day, value: 7, to: resolvedDay) ?? resolvedDay; date = calendar.date(bySettingHour: hour!, minute: minute, second: 0, of: resolvedDay) ?? date }
        let hint: DetectedDate.Hint = ["bewo", "betreu", "hausbesuch"].contains(where: text.contains) ? .assistedLiving : text.contains("therapie") ? .therapy : .other
        // "Guten Morgen" or "heute war schön" are no appointments: relative days need a time or an appointment word.
        if !explicitDate && hour == nil && !appointmentWords.contains(where: text.contains) { return nil }
        return DetectedDate(date: date, hasTime: hour != nil, hint: hint)
    }
    private static let appointmentWords = ["termin", "besuch", "kommt", "arzt", "ärztin", "amt", "therapie", "bewo", "betreu", "treffen", "praxis", "jobcenter", "gespräch"]
    private static func relativeOrWeekday(_ text: String) -> Bool {
        text.range(of: "(?<![0-9])[0-3]?[0-9]\\.([01]?[0-9]\\.|\\s*(" + months.joined(separator: "|") + "))", options: .regularExpression) == nil
    }
}
