import AppIntents
import WidgetKit
import Foundation

enum TherapyWidgetSource: String, AppEnum {
    case app, manual
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Datenquelle"
    static var caseDisplayRepresentations: [TherapyWidgetSource: DisplayRepresentation] = [.app: "Aktuelle App-Daten", .manual: "Manuell eingestellter Termin / Hinweis"]
}
enum TherapyWidgetWeekday: String, AppEnum {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday
    var number: Int { switch self { case .sunday: 1; case .monday: 2; case .tuesday: 3; case .wednesday: 4; case .thursday: 5; case .friday: 6; case .saturday: 7 } }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Wochentag"
    static var caseDisplayRepresentations: [TherapyWidgetWeekday: DisplayRepresentation] = [.sunday: "Sonntag", .monday: "Montag", .tuesday: "Dienstag", .wednesday: "Mittwoch", .thursday: "Donnerstag", .friday: "Freitag", .saturday: "Samstag"]
}
struct TherapyWidgetOptions: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Therapie-Widget bearbeiten"
    static var description = IntentDescription("Aktuelle App-Daten anzeigen oder einen manuellen Termin einstellen. Manuelle Angaben ändern deine App-Daten nicht.")
    @Parameter(title: "Datenquelle", default: .app) var source: TherapyWidgetSource
    @Parameter(title: "Nur Titel mit diesem Text") var filter: String?
    @Parameter(title: "Manuelle Bezeichnung", default: "Mein Termin") var label: String
    @Parameter(title: "Manuelles Datum") var date: Date?
    @Parameter(title: "Manuell wöchentlich wiederholen", default: false) var repeatsWeekly: Bool
    @Parameter(title: "Manueller Wochentag", default: .tuesday) var weekday: TherapyWidgetWeekday
    @Parameter(title: "Manuelle Stunde", default: 15) var hour: Int
    @Parameter(title: "Manuelle Minute", default: 0) var minute: Int
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$source)") {
            \.$filter
            \.$label
            \.$date
            \.$repeatsWeekly
            \.$weekday
            \.$hour
            \.$minute
        }
    }
    func snapshot(at now: Date) -> TherapyWidgetSnapshot? {
        guard source == .manual else { return nil }
        var dates: [Date] = []
        if repeatsWeekly {
            let calendar = Calendar.current
            var cursor = now
            for _ in 0..<8 {
                guard let next = calendar.nextDate(after: cursor, matching: DateComponents(hour: max(0, min(23, hour)), minute: max(0, min(59, minute)), second: 0, weekday: weekday.number), matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { break }
                dates.append(next); cursor = next.addingTimeInterval(1)
            }
        } else if let date { dates = [date] }
        else {
            let calendar = Calendar.current
            let parts = DateComponents(hour: max(0, min(23, hour)), minute: max(0, min(59, minute)), second: 0)
            if let next = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first) { dates = [next] }
        }
        let reminders = dates.flatMap { date in
            [TherapyWidgetReminder(id: "manual-routine-\(Int(date.timeIntervalSince1970))", kind: "routine", title: String(label.prefix(100)), due: date, expiresAt: date.addingTimeInterval(86400), route: "therapie://routines"), TherapyWidgetReminder(id: "manual-task-\(Int(date.timeIntervalSince1970))", kind: "task", title: String(label.prefix(100)), due: date, expiresAt: date.addingTimeInterval(86400), route: "therapie://reminders")]
        }
        return TherapyWidgetSnapshot(generatedAt: now, nextAppointments: dates, reminders: reminders, configured: !dates.isEmpty)
    }
}
