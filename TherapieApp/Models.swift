import Foundation

struct UserProfile: Codable, Equatable {
    var userName = ""
    var therapistName = ""
    var onboardingCompleted = false
}

struct TherapySchedule: Codable, Equatable {
    /// Calendar weekday: Sunday = 1 ... Saturday = 7
    var weekday = 3
    var hour = 15
    var minute = 0
    var durationMinutes = 60
    var reminderOffsetsMinutes = [1440, 120, 30]
    var taskReminderEnabled = true
    var taskReminderWeekdays = [5, 1]
    var taskReminderHour = 18
    var taskReminderMinute = 0
    var calendarEventIdentifier: String?
    var alarmIDs: [String] = []
    var location: String?
    var preparation: String?
    var cancellations: [TherapyCancellation]?
    var therapyVacations: [TherapyVacation]?
    var therapyAlarmsEnabled: Bool?
    var recurrence: TherapyRecurrence?
    var extraAppointments: [TherapyExtraAppointment]?
}

enum TherapyRecurrenceUnit: String, Codable, CaseIterable, Identifiable {
    case days, weeks, months
    var id: String { rawValue }
    var title: String { switch self { case .days: "Tage"; case .weeks: "Wochen"; case .months: "Monate" } }
}
struct TherapyWeeklySlot: Codable, Equatable, Identifiable {
    var id = UUID()
    var weekday = 5
    var hour = 15
    var minute = 0
}
struct TherapyRecurrence: Codable, Equatable {
    var unit: TherapyRecurrenceUnit = .weeks
    var interval = 1
    var anchor = Date()
    var additionalWeeklySlots: [TherapyWeeklySlot] = []
}
struct TherapyExtraAppointment: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var title = "Zusatztermin"
}

struct AppPreferences: Codable, Equatable {
    var autoBackupToSelectedFolder = true
    var includeLocationForNewMedia = true
}

struct WeeklyTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var weekOfYear: Int
    var yearForWeekOfYear: Int
    var title: String
    var details: String
    var completed = false
    var completedAt: Date?
    var topicID: UUID?
    var goalID: UUID?
    var reminder: TaskReminder?
    var dueDate: Date?
    var smallStep: String?
    var support: String?
    var progress: Int?
    var reminderShiftedAt: Date?
}

struct TherapyNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var title: String
    var text: String
    var tags: [String]
    var folderID: UUID?
    var topicID: UUID?
    var sessionID: UUID?
    var category: String?
    var author: String?
    var isImportant: Bool?
    var mediaIDs: [UUID]?
    var updatedAt: Date?
    var conversationID: UUID?
    var conversationTranscript: String?
}

struct EnergyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var level: Int
    var percent: Int?
    var givesEnergy: String
    var takesEnergy: String
    var note: String
}

enum MediaKind: String, Codable, CaseIterable {
    case photo
    case audio
    case document

    var displayName: String {
        switch self {
        case .photo: "Foto"
        case .audio: "Audio"
        case .document: "Dokument"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo.fill"
        case .audio: "waveform"
        case .document: "doc.fill"
        }
    }
}

struct MediaItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var kind: MediaKind
    var title: String
    var note: String
    var tags: [String]
    var relativePath: String
    var latitude: Double?
    var longitude: Double?
    var duration: TimeInterval?
    var folderID: UUID?
    var topicID: UUID?
    var category: String?
    var source: String?
    /// Metadata remains usable when its binary attachment was intentionally excluded.
    var attachmentOmitted: Bool?
}

struct TherapySessionReflection: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var summary: String
    var whatHelped: String
    var nextFocus: String
}

struct AppData: Codable, Equatable {
    var schemaVersion = 13
    var profile = UserProfile()
    var schedule = TherapySchedule()
    var preferences = AppPreferences()
    var weeklyTasks: [WeeklyTask] = []
    var notes: [TherapyNote] = []
    var energyEntries: [EnergyEntry] = []
    var media: [MediaItem] = []
    var reflections: [TherapySessionReflection] = []
    var moodCheckIns: [MoodCheckIn] = []
    var batteryPoints: [BatteryPoint] = []
    var weekReviews: [WeekReview] = []
    var wellnessSettings = WellnessSettings()
    var therapyFolders: [TherapyFolder] = []
    var therapyTopics: [TherapyTopic] = []
    var therapyGoals: [TherapyGoal] = []
    var sessionTemplates = [TherapySessionTemplate()]
    var currentSession: RunningTherapySession?
    var sessionHistory: [RunningTherapySession] = []
    var sessionPreferences = SessionPreferences()
    var reminderPreferences = ReminderPreferences()
    var weeklyEnergyReviews: [WeeklyEnergyReview] = []

    var guidedCheckIns: [GuidedCheckIn] = []
    var routines: [DailyRoutine] = []
    var routineCompletions: [RoutineCompletion] = []
    var routineSnoozes: [RoutineSnooze] = []
    var companionSettings = CompanionSettings()

    var dashboard = DashboardPreferences()
    var archivePreferences = ArchivePreferences()
    var therapyDiscussionAcknowledgedIDs: [String] = []
    var wellbeingPreferences = WellbeingPreferences()
    var accentTheme = AppAccent.indigo
    var aiSettings = AIBuddySettings()
    var aiMessages: [AIBuddyMessage] = []
    var aiConversations: [AIBuddyConversation] = []
    var hashtagCatalog: [String] = []
    var editorDrafts: [AppEditorDraft] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case wellbeingPreferences, accentTheme, editorDrafts, dashboard, archivePreferences, therapyDiscussionAcknowledgedIDs, aiSettings, aiMessages, aiConversations, hashtagCatalog
        case schemaVersion, profile, schedule, preferences, weeklyTasks, notes, energyEntries, media, reflections
        case moodCheckIns, batteryPoints, weekReviews, wellnessSettings
        case therapyFolders, therapyTopics, therapyGoals, sessionTemplates, currentSession, sessionHistory, sessionPreferences
        case reminderPreferences, weeklyEnergyReviews
        case guidedCheckIns, routines, routineCompletions, routineSnoozes, companionSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...13).contains(version) else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                                                   debugDescription: "Diese Daten benötigen eine neuere App-Version.")
        }
        guidedCheckIns = try c.decodeIfPresent([GuidedCheckIn].self, forKey: .guidedCheckIns) ?? []
        routines = try c.decodeIfPresent([DailyRoutine].self, forKey: .routines) ?? []
        routineCompletions = try c.decodeIfPresent([RoutineCompletion].self, forKey: .routineCompletions) ?? []
        routineSnoozes = try c.decodeIfPresent([RoutineSnooze].self, forKey: .routineSnoozes) ?? []
        companionSettings = try c.decodeIfPresent(CompanionSettings.self, forKey: .companionSettings) ?? CompanionSettings()
        dashboard = try c.decodeIfPresent(DashboardPreferences.self, forKey: .dashboard) ?? DashboardPreferences()
        archivePreferences = try c.decodeIfPresent(ArchivePreferences.self, forKey: .archivePreferences) ?? ArchivePreferences()
        if version < 10, !dashboard.cardOrder.contains(HomeCard.discussion.rawValue) {
            let position = dashboard.cardOrder.firstIndex(of: HomeCard.appointment.rawValue).map { $0 + 1 } ?? 0
            dashboard.cardOrder.insert(HomeCard.discussion.rawValue, at: position)
        }
        therapyDiscussionAcknowledgedIDs = try c.decodeIfPresent([String].self, forKey: .therapyDiscussionAcknowledgedIDs) ?? []
        wellbeingPreferences = try c.decodeIfPresent(WellbeingPreferences.self, forKey: .wellbeingPreferences) ?? WellbeingPreferences()
        accentTheme = try c.decodeIfPresent(AppAccent.self, forKey: .accentTheme) ?? .indigo
        aiSettings = try c.decodeIfPresent(AIBuddySettings.self, forKey: .aiSettings) ?? AIBuddySettings()
        aiMessages = try c.decodeIfPresent([AIBuddyMessage].self, forKey: .aiMessages) ?? []
        schemaVersion = 13
        profile = try c.decode(UserProfile.self, forKey: .profile)
        schedule = try c.decodeIfPresent(TherapySchedule.self, forKey: .schedule) ?? TherapySchedule()
        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        weeklyTasks = try c.decodeIfPresent([WeeklyTask].self, forKey: .weeklyTasks) ?? []
        notes = try c.decodeIfPresent([TherapyNote].self, forKey: .notes) ?? []
        energyEntries = try c.decodeIfPresent([EnergyEntry].self, forKey: .energyEntries) ?? []
        media = try c.decodeIfPresent([MediaItem].self, forKey: .media) ?? []
        reflections = try c.decodeIfPresent([TherapySessionReflection].self, forKey: .reflections) ?? []
        moodCheckIns = try c.decodeIfPresent([MoodCheckIn].self, forKey: .moodCheckIns) ?? []
        batteryPoints = try c.decodeIfPresent([BatteryPoint].self, forKey: .batteryPoints) ?? []
        weekReviews = try c.decodeIfPresent([WeekReview].self, forKey: .weekReviews) ?? []
        wellnessSettings = try c.decodeIfPresent(WellnessSettings.self, forKey: .wellnessSettings) ?? WellnessSettings()
        therapyFolders = try c.decodeIfPresent([TherapyFolder].self, forKey: .therapyFolders) ?? []
        therapyTopics = try c.decodeIfPresent([TherapyTopic].self, forKey: .therapyTopics) ?? []
        therapyGoals = try c.decodeIfPresent([TherapyGoal].self, forKey: .therapyGoals) ?? []
        sessionTemplates = try c.decodeIfPresent([TherapySessionTemplate].self, forKey: .sessionTemplates) ?? [TherapySessionTemplate()]
        currentSession = try c.decodeIfPresent(RunningTherapySession.self, forKey: .currentSession)
        sessionHistory = try c.decodeIfPresent([RunningTherapySession].self, forKey: .sessionHistory) ?? []
        sessionPreferences = try c.decodeIfPresent(SessionPreferences.self, forKey: .sessionPreferences) ?? SessionPreferences()
        reminderPreferences = try c.decodeIfPresent(ReminderPreferences.self, forKey: .reminderPreferences) ?? ReminderPreferences()
        weeklyEnergyReviews = try c.decodeIfPresent([WeeklyEnergyReview].self, forKey: .weeklyEnergyReviews) ?? []
        aiConversations = try c.decodeIfPresent([AIBuddyConversation].self, forKey: .aiConversations) ?? []
        hashtagCatalog = try c.decodeIfPresent([String].self, forKey: .hashtagCatalog) ?? []
        editorDrafts = try c.decodeIfPresent([AppEditorDraft].self, forKey: .editorDrafts) ?? []
        AIConversationMutation.migrate(&self)
    }
}

extension Calendar {
    static var therapyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

extension Date {
    var therapyWeek: (week: Int, year: Int) {
        let c = Calendar.therapyCalendar
        return (
            c.component(.weekOfYear, from: self),
            c.component(.yearForWeekOfYear, from: self)
        )
    }

    func isSameTherapyDay(as other: Date) -> Bool {
        Calendar.therapyCalendar.isDate(self, inSameDayAs: other)
    }
}

struct TherapyDateHelper {
    static func regularOccurrence(schedule: TherapySchedule, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (1...7).contains(schedule.weekday), (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else { return nil }
        var candidates = (schedule.extraAppointments ?? []).map(\.date).filter { $0 >= date.addingTimeInterval(-0.001) }
        if let rule = schedule.recurrence {
            let interval = max(1, min(52, rule.interval))
            let anchor = calendar.startOfDay(for: rule.anchor)
            let start = calendar.startOfDay(for: max(anchor, date))
            // Calendar arithmetic keeps clocks stable across DST and leap years.
            for offset in 0..<4000 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
                var clocks: [(Int, Int)] = []
                switch rule.unit {
                case .days:
                    let elapsed = calendar.dateComponents([.day], from: anchor, to: day).day ?? -1
                    if elapsed >= 0 && elapsed % interval == 0 { clocks = [(schedule.hour, schedule.minute)] }
                case .weeks:
                    var weeks = calendar; weeks.firstWeekday = 2; weeks.minimumDaysInFirstWeek = 4
                    let firstWeek = weeks.dateInterval(of: .weekOfYear, for: anchor)!.start
                    let week = weeks.dateInterval(of: .weekOfYear, for: day)!.start
                    let elapsed = weeks.dateComponents([.weekOfYear], from: firstWeek, to: week).weekOfYear ?? -1
                    if elapsed >= 0 && elapsed % interval == 0 {
                        let weekday = calendar.component(.weekday, from: day)
                        if weekday == schedule.weekday { clocks.append((schedule.hour, schedule.minute)) }
                        clocks += rule.additionalWeeklySlots.filter { $0.weekday == weekday }.map { ($0.hour, $0.minute) }
                    }
                case .months:
                    let firstMonth = calendar.dateInterval(of: .month, for: anchor)!.start
                    let month = calendar.dateInterval(of: .month, for: day)!.start
                    let elapsed = calendar.dateComponents([.month], from: firstMonth, to: month).month ?? -1
                    let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 28
                    if elapsed >= 0 && elapsed % interval == 0 && calendar.component(.day, from: day) == min(lastDay, calendar.component(.day, from: anchor)) { clocks = [(schedule.hour, schedule.minute)] }
                }
                let dates = clocks.compactMap { hour, minute -> Date? in
                    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
                }.filter { $0 >= date.addingTimeInterval(-0.001) && calendar.isDate($0, inSameDayAs: day) }
                if let next = dates.min() { candidates.append(next); break }
            }
        } else {
            let parts = DateComponents(hour: schedule.hour, minute: schedule.minute, second: 0, weekday: schedule.weekday)
            if let next = calendar.nextDate(after: date.addingTimeInterval(-0.001), matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) { candidates.append(next) }
        }
        return candidates.min()
    }
    static func appointments(on day: Date, schedule: TherapySchedule, includeExcluded: Bool = false, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return occurrences(schedule: schedule, after: start, count: 8, includeExcluded: includeExcluded, calendar: calendar).filter { $0 < end }
    }

    static func cancellation(schedule: TherapySchedule, on date: Date, calendar: Calendar = .current) -> TherapyCancellation? {
        schedule.cancellations?.first { $0.restoredAt == nil && ($0.exactTime == true ? abs($0.date.timeIntervalSince(date)) < 1 : calendar.isDate($0.date, inSameDayAs: date)) }
    }
    static func vacation(schedule: TherapySchedule, at date: Date) -> TherapyVacation? {
        schedule.therapyVacations?.first { $0.endedAt == nil && $0.start <= date && date < $0.end }
    }
    static func nextOccurrence(schedule: TherapySchedule, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        var cursor = date
        for _ in 0..<520 {
            guard let next = regularOccurrence(schedule: schedule, after: cursor, calendar: calendar) else { return nil }
            if let pause = vacation(schedule: schedule, at: next) { cursor = max(next.addingTimeInterval(1), pause.end); continue }
            if cancellation(schedule: schedule, on: next, calendar: calendar) == nil { return next }
            cursor = next.addingTimeInterval(1)
        }
        return nil
    }
    static func occurrences(schedule: TherapySchedule, after date: Date = Date(), count: Int = 8, includeExcluded: Bool = false, calendar: Calendar = .current) -> [Date] {
        var cursor = date, result: [Date] = []
        for _ in 0..<max(0, min(52, count)) {
            let next = includeExcluded ? regularOccurrence(schedule: schedule, after: cursor, calendar: calendar) : nextOccurrence(schedule: schedule, after: cursor, calendar: calendar)
            guard let next else { break }; result.append(next); cursor = next.addingTimeInterval(1)
        }
        return result
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = Calendar.therapyCalendar.weekdaySymbols
        guard weekday >= 1, weekday <= 7 else { return "Unbekannt" }
        return names[weekday - 1].capitalized
    }
}


enum TherapyCancellationReason: String, Codable, CaseIterable, Identifiable {
    case me, therapist, other
    var id: String { rawValue }
    var title: String { switch self { case .me: "Von mir abgesagt"; case .therapist: "Von der Therapie abgesagt"; case .other: "Anderer Grund" } }
}
struct TherapyCancellation: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var createdAt = Date()
    var exactTime: Bool?
    var reason: TherapyCancellationReason = .me
    var note = ""
    var restoredAt: Date?
}
struct TherapyVacation: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date // Exclusive; selected final day is included by the editor.
    var note = ""
    var endedAt: Date?
}
enum TherapyScheduleActions {
    static func cancel(_ entry: TherapyCancellation, schedule: inout TherapySchedule, calendar: Calendar = .current) {
        var all = schedule.cancellations ?? []
        if let index = all.firstIndex(where: { $0.restoredAt == nil && (entry.exactTime == true ? abs($0.date.timeIntervalSince(entry.date)) < 1 : calendar.isDate($0.date, inSameDayAs: entry.date)) }) { all[index].reason = entry.reason; all[index].note = entry.note }
        else { all.insert(entry, at: 0) }
        schedule.cancellations = all
    }
    static func restore(_ id: UUID, schedule: inout TherapySchedule, at date: Date = Date()) {
        guard let index = schedule.cancellations?.firstIndex(where: { $0.id == id }) else { return }
        schedule.cancellations?[index].restoredAt = date
    }
    static func endVacation(_ id: UUID, schedule: inout TherapySchedule, at date: Date = Date()) {
        guard let index = schedule.therapyVacations?.firstIndex(where: { $0.id == id }) else { return }
        schedule.therapyVacations?[index].endedAt = date
    }
}
enum TherapyCountdown {
    static func label(until date: Date, from now: Date = Date()) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "Dein Termin beginnt jetzt" }
        if minutes < 60 { return "In \(minutes) Min." }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return "In \(hours) Std. \(rest) Min." }
        return "In \(hours / 24) \(hours / 24 == 1 ? "Tag" : "Tagen") \(hours % 24) Std. \(rest) Min."
    }
}

extension AppData {
    var portableSnapshot: AppData {
        var value = self
        if value.schedule.therapyAlarmsEnabled == nil && !value.schedule.alarmIDs.isEmpty { value.schedule.therapyAlarmsEnabled = true }
        value.schedule.calendarEventIdentifier = nil
        value.schedule.alarmIDs = []
        return value
    }
}
