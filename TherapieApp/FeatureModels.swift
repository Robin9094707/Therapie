import Foundation

struct EntryLocation: Codable, Equatable, Identifiable {
    var id: String // ArchiveRecord identity, never an OS device identifier.
    var capturedAt: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && accuracy.isFinite && (0...2000).contains(accuracy) }
}
struct BuddySuggestion: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var reply: AIBuddyReply
}
enum BatteryLanguage {
    static func strength(percent: Double) -> Int? {
        guard percent.isFinite, percent > 0, percent <= 100 else { return nil }
        return max(1, min(5, Int((percent / 20).rounded())))
    }
    static func hasBatteryLevel(_ text: String) -> Bool {
        let patterns = [
            "(?i)(mein( eigener| aktueller)?|aktueller) akku\\s*(ist|liegt|beträgt|hat|steht|zeigt|auf|bei|:)",
            "(?i)\\bakku\\s*(ist|liegt|beträgt|hat|steht|zeigt|auf|bei|:)\\s*(bei\\s*)?[0-9]",
            "(?i)\\bich\\s+habe\\s+(?:gerade |aktuell |noch |nur |ungefähr |etwa )*[0-9]{1,3}\\s*(%|prozent)\\s*(akku|energie)(?:\\s+(übrig|geladen))?(?:\\s*(,|;|\\.|$)|\\s+und\\b)",
            "(?i)\\bich\\s+(liege|bin|stehe)\\s+(?:gerade |aktuell |noch |ungefähr |etwa )*bei\\s*[0-9]{1,3}\\s*(%|prozent)"
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
    static func hasPointPercentage(_ text: String) -> Bool { text.range(of: "(?i)(nimmt|zieht|kostet|gibt|bringt|raubt|verbraucht)[^.!?;\\n]{0,100}[0-9]+\\s*(%|prozent)", options: .regularExpression) != nil }
    static func factors(_ text: String, known: [BatteryPoint]) -> [AIBuddyEnergyFactor] {
        let clauses = text.replacingOccurrences(of: "(?i)\\s+und\\s+", with: ";", options: .regularExpression).components(separatedBy: CharacterSet(charactersIn: ";,\n.!?"))
        var result: [AIBuddyEnergyFactor] = []
        let direct = text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        if let point = known.first(where: { !$0.hasConfirmedImpact }), let regex = try? NSRegularExpression(pattern: "^([0-9]{1,3})\\s*(%|[Pp]rozent)[.! ]*$"), let match = regex.firstMatch(in: direct as String, range: NSRange(location: 0, length: direct.length)), let percent = Double(direct.substring(with: match.range(at: 1))) {
            return [.init(title: point.title, direction: point.direction, impact: strength(percent: percent))]
        }
        for clause in clauses {
            let value = clause as NSString
            let pattern = "(?i)^\\s*(?:die |der |das )?([\\p{L}][\\p{L}-]*)\\s+(nimmt|zieht|kostet|gibt|bringt|raubt|verbraucht)\\b.*?([0-9]{1,3})\\s*(%|prozent|/5|von 5)"
            if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: clause, range: NSRange(location: 0, length: value.length)), let raw = Int(value.substring(with: match.range(at: 3))) {
                let unit = value.substring(with: match.range(at: 4)).lowercased()
                let impact = unit == "%" || unit == "prozent" ? strength(percent: Double(raw)) : ((1...5).contains(raw) ? raw : nil)
                let verb = value.substring(with: match.range(at: 2)).lowercased()
                let direction: BatteryDirection = ["gibt", "bringt"].contains(verb) ? .gives : .takes
                result.append(.init(title: AIEnergyKeywords.title(value.substring(with: match.range(at: 1))), direction: direction, impact: impact))
                continue
            }
            for point in known {
                let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: point.title) + "\\b[^0-9]{0,60}([0-9]{1,3})\\s*(%|prozent|/5|von 5)"
                guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: clause, range: NSRange(location: 0, length: value.length)), let raw = Int(value.substring(with: match.range(at: 1))) else { continue }
                let unit = value.substring(with: match.range(at: 2)).lowercased()
                let impact = unit == "%" || unit == "prozent" ? strength(percent: Double(raw)) : ((1...5).contains(raw) ? raw : nil)
                result.append(.init(title: point.title, direction: point.direction, impact: impact))
            }
        }
        return result
    }
}
struct TodoTimelineItem: Identifiable {
    var id: String
    var date: Date
    var title: String
    var detail: String
    var kind: String
    var completed: Bool
    var taskID: UUID?
    var discussionID: String?
    var occurrence: RoutineOccurrence?
    var checkInSlotID: UUID?
    var goalID: UUID?
}
enum TodoTimeline {
    static func items(_ data: AppData, now: Date = Date()) -> [TodoTimelineItem] {
        let calendar = Calendar.therapyCalendar
        var values = data.weeklyTasks.map { task in
            let weekStart = calendar.date(from: DateComponents(weekOfYear: task.weekOfYear, yearForWeekOfYear: task.yearForWeekOfYear)) ?? task.createdAt
            return TodoTimelineItem(id: "task-" + task.id.uuidString, date: task.dueDate ?? weekStart, title: task.title, detail: "KW \(task.weekOfYear) · " + task.details, kind: "Aufgaben", completed: task.completed, taskID: task.id)
        }
        let therapy = TherapyDateHelper.nextOccurrence(schedule: data.schedule, after: now) ?? now
        values += TherapyDiscussionPlanner.points(in: data, includeDiscussed: true).map { point in
            let discussed = data.therapyDiscussionAcknowledgedIDs.contains(point.id)
            return TodoTimelineItem(id: "discussion-" + point.id, date: discussed ? point.date : therapy, title: point.text, detail: point.source + (discussed ? " · besprochen, ursprünglicher Eintrag " : " · für den nächsten Termin, erfasst ") + point.date.formatted(date: .abbreviated, time: .omitted), kind: "Therapie", completed: discussed, discussionID: point.id)
        }
        values += RoutinePlanner.occurrences(data: data, now: now).map { occurrence in
            let routine = data.routines.first { $0.id == occurrence.routineID }
            let category = routine.map { ShowerPlanner.isShower($0) ? "Duschen" : ($0.symbol == "pills.fill" || $0.title.localizedCaseInsensitiveContains("tablett") ? "Tabletten" : "Routinen") } ?? "Routinen"
            let log = data.routineCompletions.first { $0.routineID == occurrence.routineID && $0.timeID == occurrence.timeID && $0.scheduledAt == occurrence.scheduledAt }
            let detail = log.map { $0.outcome == .done ? "Erledigt" : "Ausgelassen" } ?? (occurrence.originalDue == nil ? "Noch offen" : "Einmalig verschoben")
            return .init(id: "routine-" + occurrence.id, date: occurrence.due, title: routine?.title ?? "Routine", detail: detail, kind: category, completed: log != nil, occurrence: occurrence)
        }
        for slot in DayCheckInPolicy.slots(data.companionSettings) where slot.enabled {
            let entry = DayCheckInPolicy.entry(slot, at: now)
            let existing = DayCheckInPolicy.existing(for: entry, in: data)
            values.append(.init(id: "checkin-" + slot.id.uuidString, date: now, title: slot.title, detail: slot.windowText + (existing?.isDraft == false ? " · erfasst" : existing != nil ? " · Entwurf fortsetzen" : " · noch nicht erfasst"), kind: "Check-ins", completed: existing?.isDraft == false, checkInSlotID: slot.id))
        }
        values += data.therapyGoals.map { goal in
            .init(id: "goal-" + goal.id.uuidString, date: goal.dueDate ?? now, title: goal.title, detail: "\(goal.progress) % · " + goal.status.rawValue + (goal.smallStep.isEmpty ? "" : " · " + goal.smallStep), kind: "Ziele", completed: goal.status == .completed, goalID: goal.id)
        }
        return values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}


enum EntryLocator {
    static func count(_ data: AppData) -> Int { data.notes.count + data.media.count + data.energyEntries.count + data.reflections.count + data.moodCheckIns.count + data.batteryPoints.count + data.weekReviews.count + data.weeklyEnergyReviews.count + data.guidedCheckIns.count + data.sessionHistory.count + data.weeklyTasks.count + data.therapyTopics.count + data.therapyGoals.count + data.routineCompletions.count + data.aiMessages.count }
    static func recordIDs(_ data: AppData) -> Set<String> {
        Set(ArchiveRecord.all(in: data).map(\.id) + data.aiMessages.filter { $0.role == "user" }.map { "chat-" + $0.id.uuidString })
    }
    static func summary(_ data: AppData) -> String {
        let ids = recordIDs(data)
        let valid = data.entryLocations.filter { $0.valid && ids.contains($0.id) }
        let groups = Dictionary(grouping: valid) { String(format: "%.2f, %.2f", $0.latitude, $0.longitude) }
        return "Standortstatistik nur erfasster Einträge (ungefähre Koordinaten, keine erfundenen Ortsnamen): " + groups.sorted { $0.value.count > $1.value.count }.prefix(8).map { $0.key + ": " + String($0.value.count) + " Einträge" }.joined(separator: "; ") + ". Nicht erfasste / alte Einträge fehlen in dieser Auswertung."
    }
}


/// Current actionable IDs are independent of the journal's date window.
enum BuddyCapabilities {
    static func context(_ data: AppData, question: String, now: Date) -> String {
        let q = question.lowercased(), formatter = ISO8601DateFormatter()
        let words = q.components(separatedBy: .alphanumerics.inverted).filter { $0.count >= 4 }
        var lines = ["Aktionstypen: " + AIBuddyActionKind.allCases.map { $0.rawValue + "=" + $0.label }.joined(separator: "; "), "Wochenziel Duschen: \(data.showerPreferences.weeklyGoal); bestätigt: \(ShowerPlanner.weekCount(data, at: now))"]
        for occurrence in ShowerPlanner.today(data, at: now) where !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions) {
            lines.append("Duschtag heute: " + occurrence.id + " | " + formatter.string(from: occurrence.due))
        }
        let records = ArchiveRecord.all(in: data).filter { record in
            if !data.aiSettings.includeJournal, case .note = record { return false }
            if case .media = record { return false }
            return words.contains { (record.title + " " + record.subtitle).lowercased().contains($0) }
        }.sorted { $0.date > $1.date }
        for record in records.prefix(10) { lines.append("Eintrag: " + record.id + " | UUID=" + String(record.id.suffix(36)) + " | " + record.title + " | " + String(record.subtitle.prefix(160))) }
        for goal in data.therapyGoals.prefix(8) { lines.append("Ziel-UUID: " + goal.id.uuidString + " | " + goal.title + " | \(goal.progress)% | " + goal.status.rawValue) }
        for method in data.copingMethods.prefix(8) { lines.append("Methode-UUID: " + method.id.uuidString + " | " + method.title + " | " + method.kind.rawValue + " | " + String(method.details.prefix(180))) }
        for point in TherapyDiscussionPlanner.points(in: data).prefix(8) { lines.append("Gesprächspunkt-ID: " + point.id + " | " + String(point.text.prefix(160))) }
        lines.append("Methoden-Stufen: " + MethodStage.allCases.map { $0.rawValue + "=" + $0.title }.joined(separator: ", "))
        lines.append("Akku-Kategorien: " + BatteryCategory.allCases.map { $0.rawValue + "=" + $0.title }.joined(separator: ", "))
        return BuddyInteraction.completeLines(lines.joined(separator: "\n"), limit: 6500)
    }
}
