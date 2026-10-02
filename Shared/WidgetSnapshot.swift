import Foundation

/// Minimal display cache. Never contains journal text, check-in answers or attachment paths.
struct TherapyWidgetSnapshot: Codable, Equatable {
    static let appGroup = "group.eu.rjuhas.therapie"
    static let fileName = "therapy-widget-snapshot.json"
    var generatedAt = Date()
    var nextAppointments: [Date] = []
    var reminders: [TherapyWidgetReminder] = []
    var session: TherapyWidgetSession?
    var configured = false
    var showsPersonalTitles: Bool?
    var cacheProblem: String?
    var nextAppointment: Date? { appointment(after: Date()) }
    func appointment(after now: Date) -> Date? { nextAppointments.first { $0 >= now } }
    func openReminders(at now: Date, kind: String? = nil) -> [TherapyWidgetReminder] {
        reminders.filter { $0.expiresAt > now && (kind == nil || $0.kind == kind) }.sorted {
            $0.due == $1.due ? $0.id < $1.id : $0.due < $1.due
        }
    }
    func dueRoutines(at now: Date) -> [TherapyWidgetReminder] { openReminders(at: now, kind: "routine").filter { $0.due <= now } }
}
struct TherapyWidgetReminder: Codable, Equatable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var due: Date
    var expiresAt: Date
    var route: String
}
struct TherapyWidgetPhase: Codable, Equatable {
    var title: String
    var start: Date
    var end: Date
}
struct TherapyWidgetSession: Codable, Equatable {
    var title: String
    var end: Date
    var paused = false
    var pausedRemaining: TimeInterval = 0
    var phases: [TherapyWidgetPhase] = []
    func phase(at date: Date) -> TherapyWidgetPhase? { phases.first { $0.start <= date && date < $0.end } }
}
