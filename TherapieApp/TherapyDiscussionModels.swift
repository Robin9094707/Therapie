import Foundation

struct TherapyDiscussionPoint: Identifiable, Equatable {
    var id: String
    var date: Date
    var source: String
    var text: String
}
enum TherapyDiscussionPlanner {
    static func points(in data: AppData, includeDiscussed: Bool = false) -> [TherapyDiscussionPoint] {
        var values = data.guidedCheckIns.map { TherapyDiscussionPoint(id: "guided-\($0.id)", date: $0.date, source: $0.displayTitle + ($0.isDraft ? " · Entwurf" : ""), text: $0.therapyQuestion) }
        values += data.weekReviews.map { TherapyDiscussionPoint(id: "review-\($0.id)", date: $0.weekStart, source: "Wochenrückblick", text: $0.therapyQuestion) }
        values += data.weeklyEnergyReviews.map { TherapyDiscussionPoint(id: "weekly-energy-\($0.id)", date: $0.periodEnd, source: "Wochenenergie", text: $0.therapyQuestion) }
        values += data.therapyTopics.filter { $0.isCurrent && $0.status != .completed }.map { TherapyDiscussionPoint(id: "topic-\($0.id)", date: $0.createdAt, source: "Aktuelles Thema", text: $0.title + ($0.description.isEmpty ? "" : "\n" + $0.description)) }
        let discussed = Set(data.therapyDiscussionAcknowledgedIDs)
        return values.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (includeDiscussed || !discussed.contains($0.id)) }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    static func isTherapyDay(_ data: AppData, at date: Date = Date()) -> Bool {
        data.currentSession != nil || !TherapyDateHelper.appointments(on: date, schedule: data.schedule).isEmpty
    }
}
