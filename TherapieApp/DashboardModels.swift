import Foundation

enum HomeCard: String, CaseIterable, Identifiable {
    case welcome, methods, appointment, discussion, checkIns, routines, overview, quickActions, session, pinned, wellness, therapy, week, task, latest, reminders, goals
    var id: String { rawValue }
    var title: String {
        switch self {
        case .methods: "Mein Methodenkoffer"
        case .discussion: "Gesprächsliste am Therapietag"
        case .appointment: "Nächste Therapie"
        case .checkIns: "Check-ins"
        case .routines: "Heute fällige Routinen"
        case .overview: "Tagesübersicht"
        case .quickActions: "Schnell erfassen"
        case .session: "Laufende Therapiestunde"
        case .pinned: "Angepinnt"
        case .wellness: "Stimmung & Fortschritt"
        case .therapy: "Aktuelle Therapiethemen"
        case .week: "Meine Woche"
        case .task: "Wochenaufgabe"
        case .latest: "Neueste Notizen"
        case .reminders: "Offene Aufgaben & Erinnerungen"
        case .goals: "Meine Ziele"
        case .welcome: "Persönliche Begrüßung"
        }
    }
    var symbol: String {
        switch self {
        case .methods: "sparkles"
        case .discussion: "text.bubble"
        case .appointment: "calendar.badge.clock"
        case .checkIns: "sparkles"
        case .routines: "checkmark.circle"
        case .overview: "sun.max"
        case .quickActions: "plus.circle"
        case .session: "timer"
        case .pinned: "pin"
        case .wellness: "heart"
        case .therapy: "leaf"
        case .week: "calendar"
        case .task, .reminders: "checklist"
        case .latest: "note.text"
        case .goals: "scope"
        case .welcome: "person.crop.circle"
        }
    }
}

struct DashboardPreferences: Codable, Equatable {
    var cardOrder = HomeCard.allCases.map(\.rawValue)
    var hiddenCards: [String] = []
    var pinnedCards: [String] = []
    var pinnedRecordIDs: [String] = []
    var compactCards = false
    var showWidgetTitles = false
    var welcomeFirst = true
    var showFeatureLinks = true
    var showAIImpulse = true
    var welcomeMessage = ""
    init() {}
    enum CodingKeys: String, CodingKey { case welcomeFirst, showFeatureLinks, showAIImpulse, welcomeMessage, cardOrder, hiddenCards, pinnedCards, pinnedRecordIDs, compactCards, showWidgetTitles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        welcomeFirst = try c.decodeIfPresent(Bool.self, forKey: .welcomeFirst) ?? true
        showFeatureLinks = try c.decodeIfPresent(Bool.self, forKey: .showFeatureLinks) ?? true
        showAIImpulse = try c.decodeIfPresent(Bool.self, forKey: .showAIImpulse) ?? true
        welcomeMessage = try c.decodeIfPresent(String.self, forKey: .welcomeMessage) ?? ""
        cardOrder = try c.decodeIfPresent([String].self, forKey: .cardOrder) ?? HomeCard.allCases.map(\.rawValue)
        hiddenCards = try c.decodeIfPresent([String].self, forKey: .hiddenCards) ?? []
        pinnedCards = try c.decodeIfPresent([String].self, forKey: .pinnedCards) ?? []
        pinnedRecordIDs = try c.decodeIfPresent([String].self, forKey: .pinnedRecordIDs) ?? []
        compactCards = try c.decodeIfPresent(Bool.self, forKey: .compactCards) ?? false
        showWidgetTitles = try c.decodeIfPresent(Bool.self, forKey: .showWidgetTitles) ?? false
    }
    var orderedCards: [HomeCard] {
        var seen = Set<String>()
        return (cardOrder + HomeCard.allCases.map(\.rawValue)).compactMap { raw in
            guard seen.insert(raw).inserted else { return nil }; return HomeCard(rawValue: raw)
        }
    }
    var visibleCards: [HomeCard] {
        let visible = orderedCards.filter { !hiddenCards.contains($0.rawValue) }
        let ordered = visible.filter { pinnedCards.contains($0.rawValue) } + visible.filter { !pinnedCards.contains($0.rawValue) }
        return welcomeFirst && visible.contains(.welcome) ? [.welcome] + ordered.filter { $0 != .welcome } : ordered
    }
}

enum ArchiveGrouping: String, Codable, CaseIterable, Identifiable {
    case day = "Tage", week = "Wochen", month = "Monate", year = "Jahre"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
    }
    func start(of date: Date, calendar: Calendar = .therapyCalendar) -> Date {
        calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }
    func title(for date: Date, calendar: Calendar = .therapyCalendar) -> String {
        if self == .week { return "KW \(calendar.component(.weekOfYear, from: date)) · \(calendar.component(.yearForWeekOfYear, from: date))" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "de_DE"); formatter.calendar = calendar
        formatter.dateFormat = self == .day ? "EEEE, d. MMMM yyyy" : self == .month ? "MMMM yyyy" : "yyyy"
        return formatter.string(from: date)
    }
}
struct ArchivePreferences: Codable, Equatable {
    var grouping: ArchiveGrouping = .day
    var oldestFirst = false
}

enum ArchiveDateFilter {
    static func includes(_ date: Date, day: Date?, from: Date?, through: Date?, calendar: Calendar = .therapyCalendar) -> Bool {
        if let day, !calendar.isDate(date, inSameDayAs: day) { return false }
        if let from, date < calendar.startOfDay(for: from) { return false }
        if let through, let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)), date >= end { return false }
        return true
    }
}
