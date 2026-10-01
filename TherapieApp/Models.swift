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
}

struct EnergyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var level: Int
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
    var schemaVersion = 8
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

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, schedule, preferences, weeklyTasks, notes, energyEntries, media, reflections
        case moodCheckIns, batteryPoints, weekReviews, wellnessSettings
        case therapyFolders, therapyTopics, therapyGoals, sessionTemplates, currentSession, sessionHistory, sessionPreferences
        case reminderPreferences, weeklyEnergyReviews
        case guidedCheckIns, routines, routineCompletions, routineSnoozes, companionSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...8).contains(version) else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                                                   debugDescription: "Diese Daten benötigen eine neuere App-Version.")
        }
        guidedCheckIns = try c.decodeIfPresent([GuidedCheckIn].self, forKey: .guidedCheckIns) ?? []
        routines = try c.decodeIfPresent([DailyRoutine].self, forKey: .routines) ?? []
        routineCompletions = try c.decodeIfPresent([RoutineCompletion].self, forKey: .routineCompletions) ?? []
        routineSnoozes = try c.decodeIfPresent([RoutineSnooze].self, forKey: .routineSnoozes) ?? []
        companionSettings = try c.decodeIfPresent(CompanionSettings.self, forKey: .companionSettings) ?? CompanionSettings()
        schemaVersion = 8
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
    static func nextOccurrence(schedule: TherapySchedule, after date: Date = Date()) -> Date? {
        var components = DateComponents()
        components.weekday = schedule.weekday
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0

        return Calendar.current.nextDate(
            after: date.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = Calendar.therapyCalendar.weekdaySymbols
        guard weekday >= 1, weekday <= 7 else { return "Unbekannt" }
        return names[weekday - 1].capitalized
    }
}
