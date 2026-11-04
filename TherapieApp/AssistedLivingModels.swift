import Foundation

// MARK: - Betreutes Wohnen (BeWo)
//
// Ambulant betreutes Wohnen: appointments (usually home visits), topics to talk about, agreements and small
// goals. Pure Foundation so the encrypted backup, the readable ZIP and the model checks share the same code.

enum AssistedLivingVisitKind: String, Codable, CaseIterable, Identifiable {
    case homeVisit, phone, accompaniment, office, online, group
    var id: String { rawValue }
    var title: String {
        switch self {
        case .homeVisit: "Hausbesuch"
        case .phone: "Telefonat"
        case .accompaniment: "Begleitung (Amt, Arzt …)"
        case .office: "Im Büro"
        case .online: "Video"
        case .group: "Gruppenangebot"
        }
    }
    var symbol: String {
        switch self {
        case .homeVisit: "house.fill"
        case .phone: "phone.fill"
        case .accompaniment: "figure.2"
        case .office: "building.2.fill"
        case .online: "video.fill"
        case .group: "person.3.fill"
        }
    }
}

enum AssistedLivingStatus: String, Codable, CaseIterable, Identifiable {
    case planned, done, cancelled
    var id: String { rawValue }
    var title: String { switch self { case .planned: "Geplant"; case .done: "Stattgefunden"; case .cancelled: "Abgesagt" } }
}

enum AssistedLivingTopicCategory: String, Codable, CaseIterable, Identifiable {
    case everyday, household, finances, authorities, health, social, work, feelings, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyday: "Alltag & Struktur"
        case .household: "Wohnung & Haushalt"
        case .finances: "Geld & Finanzen"
        case .authorities: "Ämter & Post"
        case .health: "Gesundheit & Termine"
        case .social: "Kontakte & Freizeit"
        case .work: "Arbeit & Tagesstruktur"
        case .feelings: "Gefühle & Belastung"
        case .other: "Sonstiges"
        }
    }
    var symbol: String {
        switch self {
        case .everyday: "calendar.day.timeline.left"
        case .household: "house.fill"
        case .finances: "eurosign.circle.fill"
        case .authorities: "envelope.fill"
        case .health: "cross.case.fill"
        case .social: "person.2.fill"
        case .work: "briefcase.fill"
        case .feelings: "heart.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

enum AssistedLivingTopicStatus: String, Codable, CaseIterable, Identifiable {
    case open, next, discussed, done
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Gesammelt"
        case .next: "Beim nächsten Termin"
        case .discussed: "Besprochen"
        case .done: "Erledigt"
        }
    }
    var symbol: String {
        switch self {
        case .open: "tray.fill"
        case .next: "star.fill"
        case .discussed: "bubble.left.and.bubble.right.fill"
        case .done: "checkmark.circle.fill"
        }
    }
    var isOpen: Bool { self == .open || self == .next }
}

enum AssistedLivingOwner: String, Codable, CaseIterable, Identifiable {
    case me, caregiver, together
    var id: String { rawValue }
    var title: String { switch self { case .me: "Ich"; case .caregiver: "Betreuung"; case .together: "Gemeinsam" } }
    var symbol: String { switch self { case .me: "person.fill"; case .caregiver: "person.badge.shield.checkmark.fill"; case .together: "person.2.fill" } }
}

struct AssistedLivingAgreement: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var owner: AssistedLivingOwner = .me
    var dueDate: Date?
    var done = false
    var doneAt: Date?

    init(id: UUID = UUID(), title: String = "", owner: AssistedLivingOwner = .me, dueDate: Date? = nil, done: Bool = false, doneAt: Date? = nil) {
        self.id = id; self.title = title; self.owner = owner; self.dueDate = dueDate; self.done = done; self.doneAt = doneAt
    }
    enum CodingKeys: String, CodingKey { case id, title, owner, dueDate, done, doneAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); title = try c.value(.title, ""); owner = try c.value(.owner, .me)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate); done = try c.value(.done, false); doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
    }
}

struct AssistedLivingAppointment: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var durationMinutes = 60
    var title = "BeWo-Termin"
    var kind: AssistedLivingVisitKind = .homeVisit
    var caregiver = ""
    var location = ""
    var status: AssistedLivingStatus = .planned
    var preparation = ""
    var moodBefore: Int?
    var moodAfter: Int?
    var summary = ""
    var wentWell = ""
    var agreements: [AssistedLivingAgreement] = []
    var topicIDs: [UUID] = []
    var cancelReason = ""
    var regularVisitID: UUID?
    var createdAt = Date()
    var updatedAt: Date?

    init(id: UUID = UUID(), date: Date = Date(), durationMinutes: Int = 60, title: String = "BeWo-Termin", kind: AssistedLivingVisitKind = .homeVisit, caregiver: String = "", location: String = "", status: AssistedLivingStatus = .planned, preparation: String = "", summary: String = "", agreements: [AssistedLivingAgreement] = [], topicIDs: [UUID] = [], regularVisitID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id; self.date = date; self.durationMinutes = durationMinutes; self.title = title; self.kind = kind; self.caregiver = caregiver
        self.location = location; self.status = status; self.preparation = preparation; self.summary = summary; self.agreements = agreements
        self.topicIDs = topicIDs; self.regularVisitID = regularVisitID; self.createdAt = createdAt
    }
    enum CodingKeys: String, CodingKey { case id, date, durationMinutes, title, kind, caregiver, location, status, preparation, moodBefore, moodAfter, summary, wentWell, agreements, topicIDs, cancelReason, regularVisitID, createdAt, updatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); date = try c.value(.date, Date.distantPast); durationMinutes = max(5, min(600, try c.value(.durationMinutes, 60)))
        title = try c.value(.title, "BeWo-Termin"); kind = try c.value(.kind, .homeVisit); caregiver = try c.value(.caregiver, ""); location = try c.value(.location, "")
        status = try c.value(.status, .planned); preparation = try c.value(.preparation, "")
        moodBefore = try c.decodeIfPresent(Int.self, forKey: .moodBefore); moodAfter = try c.decodeIfPresent(Int.self, forKey: .moodAfter)
        summary = try c.value(.summary, ""); wentWell = try c.value(.wentWell, ""); agreements = try c.value(.agreements, []); topicIDs = try c.value(.topicIDs, [])
        cancelReason = try c.value(.cancelReason, ""); regularVisitID = try c.decodeIfPresent(UUID.self, forKey: .regularVisitID)
        createdAt = try c.value(.createdAt, Date.distantPast); updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
    var end: Date { date.addingTimeInterval(Double(max(5, durationMinutes)) * 60) }
}

struct AssistedLivingTopic: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var details = ""
    var category: AssistedLivingTopicCategory = .everyday
    var priority = 2
    var status: AssistedLivingTopicStatus = .next
    var discussedAt: Date?
    var appointmentID: UUID?
    var outcome = ""
    var updatedAt: Date?

    init(id: UUID = UUID(), createdAt: Date = Date(), title: String = "", details: String = "", category: AssistedLivingTopicCategory = .everyday, priority: Int = 2, status: AssistedLivingTopicStatus = .next) {
        self.id = id; self.createdAt = createdAt; self.title = title; self.details = details; self.category = category; self.priority = priority; self.status = status
    }
    enum CodingKeys: String, CodingKey { case id, createdAt, title, details, category, priority, status, discussedAt, appointmentID, outcome, updatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); createdAt = try c.value(.createdAt, Date.distantPast); title = try c.value(.title, ""); details = try c.value(.details, "")
        category = try c.value(.category, .everyday); priority = max(1, min(3, try c.value(.priority, 2))); status = try c.value(.status, .next)
        discussedAt = try c.decodeIfPresent(Date.self, forKey: .discussedAt); appointmentID = try c.decodeIfPresent(UUID.self, forKey: .appointmentID)
        outcome = try c.value(.outcome, ""); updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct AssistedLivingStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var done = false
    var doneAt: Date?
    init(id: UUID = UUID(), title: String = "", done: Bool = false, doneAt: Date? = nil) { self.id = id; self.title = title; self.done = done; self.doneAt = doneAt }
    enum CodingKeys: String, CodingKey { case id, title, done, doneAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); title = try c.value(.title, ""); done = try c.value(.done, false); doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
    }
}

struct AssistedLivingGoal: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var details = ""
    var category: AssistedLivingTopicCategory = .everyday
    var steps: [AssistedLivingStep] = []
    var completedAt: Date?

    init(id: UUID = UUID(), createdAt: Date = Date(), title: String = "", details: String = "", category: AssistedLivingTopicCategory = .everyday, steps: [AssistedLivingStep] = []) {
        self.id = id; self.createdAt = createdAt; self.title = title; self.details = details; self.category = category; self.steps = steps
    }
    enum CodingKeys: String, CodingKey { case id, createdAt, title, details, category, steps, completedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); createdAt = try c.value(.createdAt, Date.distantPast); title = try c.value(.title, ""); details = try c.value(.details, "")
        category = try c.value(.category, .everyday); steps = try c.value(.steps, []); completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
    var progress: Double { steps.isEmpty ? (completedAt == nil ? 0 : 1) : Double(steps.filter(\.done).count) / Double(steps.count) }
}

struct AssistedLivingRegularVisit: Codable, Equatable, Identifiable {
    var id = UUID()
    var weekday = 3
    var hour = 10
    var minute = 0
    var everyWeeks = 1
    var anchor = Date()
    var durationMinutes = 60
    var kind: AssistedLivingVisitKind = .homeVisit
    var enabled = true

    init(id: UUID = UUID(), weekday: Int = 3, hour: Int = 10, minute: Int = 0, everyWeeks: Int = 1, anchor: Date = Date(), durationMinutes: Int = 60, kind: AssistedLivingVisitKind = .homeVisit, enabled: Bool = true) {
        self.id = id; self.weekday = weekday; self.hour = hour; self.minute = minute; self.everyWeeks = everyWeeks; self.anchor = anchor
        self.durationMinutes = durationMinutes; self.kind = kind; self.enabled = enabled
    }
    enum CodingKeys: String, CodingKey { case id, weekday, hour, minute, everyWeeks, anchor, durationMinutes, kind, enabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID()); weekday = max(1, min(7, try c.value(.weekday, 3))); hour = max(0, min(23, try c.value(.hour, 10))); minute = max(0, min(59, try c.value(.minute, 0)))
        everyWeeks = max(1, min(8, try c.value(.everyWeeks, 1))); anchor = try c.value(.anchor, Date.distantPast); durationMinutes = max(5, min(600, try c.value(.durationMinutes, 60)))
        kind = try c.value(.kind, .homeVisit); enabled = try c.value(.enabled, true)
    }
    var label: String {
        let day = TherapyDateHelper.weekdayName(weekday)
        return (everyWeeks == 1 ? "Jeden " : "Alle \(everyWeeks) Wochen ") + day + String(format: " · %02d:%02d", hour, minute)
    }
}

struct AssistedLivingSettings: Codable, Equatable {
    var providerName = ""
    var caregiverName = ""
    var caregiverPhone = ""
    var officePhone = ""
    var defaultLocation = "Bei mir zu Hause"
    var defaultDurationMinutes = 60
    var hoursPerWeek: Double?
    var remindersEnabled = true
    var reminderOffsetsMinutes = [1440, 60]
    var alarmEnabled = false
    var privateTitles = false
    var regularVisits: [AssistedLivingRegularVisit] = []
    var skippedRegularDates: [Date] = []
    var preparationPrompts = AssistedLivingSettings.defaultPrompts
    var notes = ""

    static let defaultPrompts = [
        "Wie geht es mir seit dem letzten Termin?",
        "Was hat gut geklappt?",
        "Wobei brauche ich gerade Unterstützung?",
        "Welche Post, Termine oder Fristen stehen an?"
    ]

    init() {}
    enum CodingKeys: String, CodingKey { case providerName, caregiverName, caregiverPhone, officePhone, defaultLocation, defaultDurationMinutes, hoursPerWeek, remindersEnabled, reminderOffsetsMinutes, alarmEnabled, privateTitles, regularVisits, skippedRegularDates, preparationPrompts, notes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerName = try c.value(.providerName, ""); caregiverName = try c.value(.caregiverName, ""); caregiverPhone = try c.value(.caregiverPhone, "")
        officePhone = try c.value(.officePhone, ""); defaultLocation = try c.value(.defaultLocation, "Bei mir zu Hause")
        defaultDurationMinutes = max(5, min(600, try c.value(.defaultDurationMinutes, 60))); hoursPerWeek = try c.decodeIfPresent(Double.self, forKey: .hoursPerWeek)
        remindersEnabled = try c.value(.remindersEnabled, true); reminderOffsetsMinutes = try c.value(.reminderOffsetsMinutes, [1440, 60])
        alarmEnabled = try c.value(.alarmEnabled, false); privateTitles = try c.value(.privateTitles, false)
        regularVisits = try c.value(.regularVisits, []); skippedRegularDates = try c.value(.skippedRegularDates, [])
        preparationPrompts = try c.value(.preparationPrompts, AssistedLivingSettings.defaultPrompts); notes = try c.value(.notes, "")
    }
}

/// One upcoming visit: either a stored appointment or a regular visit that has not been opened yet.
struct AssistedLivingOccurrence: Identifiable, Equatable {
    var id: String
    var date: Date
    var durationMinutes: Int
    var kind: AssistedLivingVisitKind
    var title: String
    var appointmentID: UUID?
    var regularVisitID: UUID?
    var end: Date { date.addingTimeInterval(Double(max(5, durationMinutes)) * 60) }
}

struct AssistedLivingAgreementEntry: Identifiable, Equatable {
    var appointment: AssistedLivingAppointment
    var agreement: AssistedLivingAgreement
    var id: UUID { agreement.id }
}

struct AssistedLivingReminderSlot: Identifiable, Equatable {
    var id: String
    var fireAt: Date
    var title: String
    var detail: String
    var route: String
    var occurrence: AssistedLivingOccurrence
}

enum AssistedLivingPlanner {
    static func regularDates(_ visit: AssistedLivingRegularVisit, from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        guard visit.enabled, start < end else { return [] }
        var weeks = calendar; weeks.firstWeekday = 2; weeks.minimumDaysInFirstWeek = 4
        guard let firstWeek = weeks.dateInterval(of: .weekOfYear, for: visit.anchor)?.start else { return [] }
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < end && result.count < 120 {
            if calendar.component(.weekday, from: day) == visit.weekday,
               let week = weeks.dateInterval(of: .weekOfYear, for: day)?.start,
               let elapsed = weeks.dateComponents([.weekOfYear], from: firstWeek, to: week).weekOfYear,
               elapsed >= 0, elapsed % max(1, visit.everyWeeks) == 0,
               let date = calendar.date(bySettingHour: visit.hour, minute: visit.minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
               date >= start, date < end {
                result.append(date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func regularID(_ visit: AssistedLivingRegularVisit, date: Date) -> String { "regular.\(visit.id).\(Int(date.timeIntervalSince1970))" }

    /// Planned appointments that have not ended, merged with regular visits. A regular visit is hidden on days
    /// with a stored appointment from the same rhythm, or when it was skipped.
    static func upcoming(_ data: AppData, now: Date = Date(), days: Int = 60, calendar: Calendar = .current) -> [AssistedLivingOccurrence] {
        let settings = data.assistedLivingSettings
        let horizon = calendar.date(byAdding: .day, value: max(1, days), to: now) ?? now.addingTimeInterval(Double(days) * 86400)
        var result = data.assistedLivingAppointments.filter { $0.status == .planned && $0.end > now && $0.date <= horizon }.map {
            AssistedLivingOccurrence(id: "appointment.\($0.id)", date: $0.date, durationMinutes: $0.durationMinutes, kind: $0.kind, title: $0.title, appointmentID: $0.id, regularVisitID: $0.regularVisitID)
        }
        for visit in settings.regularVisits {
            for date in regularDates(visit, from: now.addingTimeInterval(-Double(visit.durationMinutes) * 60), to: horizon, calendar: calendar) {
                let end = date.addingTimeInterval(Double(visit.durationMinutes) * 60)
                guard end > now else { continue }
                if settings.skippedRegularDates.contains(where: { abs($0.timeIntervalSince(date)) < 1 }) { continue }
                if data.assistedLivingAppointments.contains(where: { $0.regularVisitID == visit.id && calendar.isDate($0.date, inSameDayAs: date) }) { continue }
                result.append(AssistedLivingOccurrence(id: regularID(visit, date: date), date: date, durationMinutes: visit.durationMinutes, kind: visit.kind, title: "BeWo-Termin", regularVisitID: visit.id))
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    static func next(_ data: AppData, now: Date = Date(), calendar: Calendar = .current) -> AssistedLivingOccurrence? {
        upcoming(data, now: now, days: 120, calendar: calendar).first
    }

    /// Turns a regular visit into a stored appointment so it can carry topics, preparation and notes.
    static func materialize(_ occurrence: AssistedLivingOccurrence, settings: AssistedLivingSettings, now: Date = Date()) -> AssistedLivingAppointment {
        AssistedLivingAppointment(date: occurrence.date, durationMinutes: occurrence.durationMinutes, title: occurrence.title, kind: occurrence.kind,
                                  caregiver: settings.caregiverName, location: occurrence.kind == .homeVisit ? settings.defaultLocation : "",
                                  regularVisitID: occurrence.regularVisitID, createdAt: now)
    }

    static func reminderSlots(_ data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [AssistedLivingReminderSlot] {
        let settings = data.assistedLivingSettings
        guard settings.remindersEnabled else { return [] }
        let offsets = Set(settings.reminderOffsetsMinutes.filter { (0...10080).contains($0) }).sorted(by: >)
        var slots: [AssistedLivingReminderSlot] = []
        for occurrence in upcoming(data, now: now, days: 21, calendar: calendar).prefix(6) {
            for offset in offsets {
                let fire = occurrence.date.addingTimeInterval(-Double(offset) * 60)
                guard fire > now else { continue }
                let when: String = offset == 0 ? "beginnt jetzt" : offset >= 1440 ? (offset == 1440 ? "ist morgen" : "in \(offset / 1440) Tagen") : offset >= 60 ? "in \(offset / 60) Std." : "in \(offset) Min."
                let title = settings.privateTitles ? "Dein Termin " + when : "BeWo " + when + " · " + occurrence.kind.title
                slots.append(AssistedLivingReminderSlot(id: "therapy.bewo.\(Int(occurrence.date.timeIntervalSince1970)).\(offset)", fireAt: fire, title: title, detail: "Betreutes Wohnen", route: "bewo|\(occurrence.id)", occurrence: occurrence))
            }
        }
        return slots.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }

    static func openTopics(_ data: AppData) -> [AssistedLivingTopic] {
        data.assistedLivingTopics.filter { $0.status.isOpen }.sorted {
            if $0.status != $1.status { return $0.status == .next }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt < $1.createdAt
        }
    }

    static func openAgreements(_ data: AppData) -> [AssistedLivingAgreementEntry] {
        data.assistedLivingAppointments.flatMap { appointment in appointment.agreements.filter { !$0.done }.map { AssistedLivingAgreementEntry(appointment: appointment, agreement: $0) } }
            .sorted { lhs, rhs in
                let left = lhs.agreement.dueDate ?? .distantFuture, right = rhs.agreement.dueDate ?? .distantFuture
                return left == right ? lhs.appointment.date < rhs.appointment.date : left < right
            }
    }

    static func lastVisit(_ data: AppData, now: Date = Date()) -> AssistedLivingAppointment? {
        data.assistedLivingAppointments.filter { $0.status == .done || ($0.status == .planned && $0.end <= now) }.max { $0.date < $1.date }
    }

    /// Marks a topic as discussed in an appointment and links both directions.
    static func discuss(_ topicID: UUID, in appointmentID: UUID, data: inout AppData, outcome: String = "", now: Date = Date()) {
        guard let topic = data.assistedLivingTopics.firstIndex(where: { $0.id == topicID }) else { return }
        data.assistedLivingTopics[topic].status = .discussed
        data.assistedLivingTopics[topic].discussedAt = now
        data.assistedLivingTopics[topic].appointmentID = appointmentID
        if !outcome.isEmpty { data.assistedLivingTopics[topic].outcome = outcome }
        data.assistedLivingTopics[topic].updatedAt = now
        if let appointment = data.assistedLivingAppointments.firstIndex(where: { $0.id == appointmentID }), !data.assistedLivingAppointments[appointment].topicIDs.contains(topicID) {
            data.assistedLivingAppointments[appointment].topicIDs.append(topicID)
        }
    }

    static func countdown(to date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "de_DE"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        switch days {
        case ..<0: return "Läuft · seit " + time
        case 0: return date <= now ? "Läuft gerade" : "Heute · " + time
        case 1: return "Morgen · " + time
        default:
            formatter.dateFormat = "EEEE, d. MMM"
            return "In \(days) Tagen · " + formatter.string(from: date)
        }
    }
}
