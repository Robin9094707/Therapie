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
    static func hasBatteryLevel(_ text: String) -> Bool { text.range(of: "(?i)(mein( eigener)?|aktueller|mein aktueller) akku\\s*(ist|liegt|beträgt|bei|:)|akku\\s*(ist|liegt|beträgt|bei|:)\\s*(bei\\s*)?[0-9]", options: .regularExpression) != nil }
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
        values += RoutinePlanner.occurrences(data.routines, settings: data.companionSettings, now: now).map { occurrence in
            .init(id: "routine-" + occurrence.id, date: occurrence.due, title: data.routines.first { $0.id == occurrence.routineID }?.title ?? "Routine", detail: "Geplanter Zeitpunkt", kind: "Routinen", completed: RoutinePlanner.resolved(occurrence, completions: data.routineCompletions), occurrence: occurrence)
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
