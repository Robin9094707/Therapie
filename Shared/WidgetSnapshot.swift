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
    var accentName: String?
    var cacheProblem: String?
    var showerDays: [TherapyWidgetShowerDay]?
    var showerWeekCount: Int?
    var showerWeekGoal: Int?
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


struct TherapyWidgetShowerDay: Codable, Equatable {
    var date: Date
    var status: String
}
/// Container access is checked by iOS. Provisioning candidates support a signer that
/// renames the group consistently in the app and extension; no private-container fallback.
enum TherapyWidgetStorage {
    static func candidates(profile: Data?) -> [String] {
        var groups = [TherapyWidgetSnapshot.appGroup]
        if let profile, let text = String(data: profile, encoding: .isoLatin1), let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex) {
            let xml = Data(text[start.lowerBound..<end.upperBound].utf8)
            if let object = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any], let entitlements = object["Entitlements"] as? [String: Any], let declared = entitlements["com.apple.security.application-groups"] as? [String] {
                groups += declared.filter { $0.hasPrefix("group.") && !$0.contains("*") && $0.localizedCaseInsensitiveContains("therap") }.sorted()
            }
        }
        var seen = Set<String>(); return groups.filter { seen.insert($0).inserted }
    }
    static func container() -> (url: URL, group: String)? {
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        for group in candidates(profile: profile) {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return (url, group) }
        }
        return nil
    }
    static func read() -> TherapyWidgetSnapshot {
        guard let storage = container() else { return TherapyWidgetSnapshot(cacheProblem: "Kein gemeinsamer Datenzugriff. App öffnen und Widget-Diagnose prüfen; manuelle Widgets funktionieren unabhängig davon.") }
        let file = try? Data(contentsOf: storage.url.appendingPathComponent(TherapyWidgetSnapshot.fileName))
        let shared = UserDefaults(suiteName: storage.group)?.data(forKey: TherapyWidgetSnapshot.fileName)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return [file, shared].compactMap { $0 }.compactMap { try? decoder.decode(TherapyWidgetSnapshot.self, from: $0) }.max { $0.generatedAt < $1.generatedAt } ?? TherapyWidgetSnapshot(cacheProblem: "Noch keine lesbaren App-Daten. App öffnen und Widget-Daten aktualisieren.")
    }
}
