import Foundation

enum BatteryDirection: String, Codable, CaseIterable, Identifiable {
    case gives, takes
    var id: String { rawValue }
    var title: String { self == .gives ? "Gibt Akku" : "Nimmt Akku" }
    var symbol: String { self == .gives ? "battery.100percent" : "battery.25percent" }
    var sign: Int { self == .gives ? 1 : -1 }
}

enum BatteryCategory: String, Codable, CaseIterable, Identifiable {
    case people, work, sensory, rest, movement, interests, sleep, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .people: "Menschen"
        case .work: "Arbeit & Termine"
        case .sensory: "Reize & Umgebung"
        case .rest: "Ruhe & Pausen"
        case .movement: "Bewegung"
        case .interests: "Interessen"
        case .sleep: "Schlaf"
        case .other: "Sonstiges"
        }
    }
    var symbol: String {
        switch self {
        case .people: "person.2"
        case .work: "calendar"
        case .sensory: "ear"
        case .rest: "leaf"
        case .movement: "figure.walk"
        case .interests: "star"
        case .sleep: "moon"
        case .other: "ellipsis.circle"
        }
    }
}

struct MoodCheckIn: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var date = Date()
    var mood = 3
    var battery = 3
    var stress: Int?
    var sensoryLoad: Int?
    var sleepHours: Double?
    var emotions: [String] = []
    var note = ""
    var smallWin = ""
    var nextNeed = ""
    var favorite = false
    var moodPercent: Int?
    var daySlotID: UUID?

    static let emotionOptions = ["Ruhig", "Glücklich", "Zufrieden", "Stolz", "Dankbar", "Unsicher",
                                 "Traurig", "Ängstlich", "Gereizt", "Überfordert", "Müde", "Motiviert"]
    static let moodTitles = ["Sehr schlecht", "Eher schlecht", "Gemischt", "Eher gut", "Sehr gut"]
    static let moodFaces = ["😞", "🙁", "😐", "🙂", "😊"]
    var moodTitle: String { Self.moodTitles[max(0, min(4, mood - 1))] }
    var face: String { Self.moodFaces[max(0, min(4, mood - 1))] }
}

struct BatteryPoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var title = ""
    var direction: BatteryDirection = .gives
    var category: BatteryCategory = .other
    var impact = 3
    var note = ""
    var checkInID: UUID?
    // nil preserves the meaning of older, manually rated points.
    var impactConfirmed: Bool?
    var hasConfirmedImpact: Bool { impactConfirmed != false }
    var impactDescription: String { hasConfirmedImpact ? "\(impact)/5" : "noch offen" }
    var signedImpact: Int { hasConfirmedImpact ? direction.sign * impact : 0 }
}

struct WeekReview: Identifiable, Codable, Equatable {
    var id = UUID()
    var weekStart = Date().therapyWeekStart
    var createdAt = Date()
    var summary = ""
    var whatHelped = ""
    var whatWasHard = ""
    var smallWin = ""
    var nextStep = ""
    var therapyQuestion = ""
}

struct WellnessSettings: Codable, Equatable {
    var weeklyGoal = 1
    var reminderEnabled = false
    var reminderWeekday = 1
    var reminderHour = 18
    var reminderMinute = 0
}

extension Date {
    var therapyWeekStart: Date {
        Calendar.therapyCalendar.dateInterval(of: .weekOfYear, for: self)!.start
    }
    func therapyAddingWeeks(_ count: Int) -> Date {
        Calendar.therapyCalendar.date(byAdding: .weekOfYear, value: count, to: self)!
    }
}

struct WellnessPeriod: Equatable {
    let start: Date
    let end: Date // Exclusive.
    func contains(_ date: Date) -> Bool { date >= start && date < end }
    static func week(containing date: Date) -> WellnessPeriod {
        let start = date.therapyWeekStart
        return WellnessPeriod(start: start, end: start.therapyAddingWeeks(1))
    }
    static func rolling(days: Int, now: Date = Date()) -> WellnessPeriod {
        let calendar = Calendar.therapyCalendar
        let today = calendar.startOfDay(for: now)
        return WellnessPeriod(start: calendar.date(byAdding: .day, value: -(days - 1), to: today)!,
                              end: now.addingTimeInterval(0.001))
    }
}

struct DailyWellnessValue: Identifiable {
    let date: Date
    var id: Date { date }
    let mood: Double?
    let battery: Double?
    let stress: Double?
    let sensory: Double?
    let count: Int
    let segment: Int
}

struct BatteryCategoryTotal: Identifiable {
    var id: String { category.rawValue + direction.rawValue }
    let category: BatteryCategory
    let direction: BatteryDirection
    let count: Int
    let impact: Int
}

struct WellnessStreak: Equatable {
    let current: Int
    let longest: Int
    let thisWeekRecorded: Bool
}

enum WellnessAnalytics {
    static func activityDates(_ data: AppData) -> [Date] {
        data.moodCheckIns.map(\.date) + data.batteryPoints.map(\.date)
            + data.weekReviews.map(\.weekStart) + data.energyEntries.map(\.createdAt)
            + data.weeklyEnergyReviews.map(\.periodEnd) + data.guidedCheckIns.filter { !$0.isDraft }.map(\.date)
    }
    static func streak(_ dates: [Date], now: Date = Date()) -> WellnessStreak {
        let currentWeek = now.therapyWeekStart
        let weeks = Set(dates.filter { $0 <= now }.map(\.therapyWeekStart))
        let recorded = weeks.contains(currentWeek)
        var cursor = recorded ? currentWeek : currentWeek.therapyAddingWeeks(-1)
        var current = 0
        while weeks.contains(cursor) {
            current += 1
            cursor = cursor.therapyAddingWeeks(-1)
        }
        var longest = 0, run = 0
        var previous: Date?
        for week in weeks.sorted() {
            run = previous?.therapyAddingWeeks(1) == week ? run + 1 : 1
            longest = max(longest, run)
            previous = week
        }
        return WellnessStreak(current: current, longest: longest, thisWeekRecorded: recorded)
    }
    static func daily(_ data: AppData, period: WellnessPeriod) -> [DailyWellnessValue] {
        let calendar = Calendar.therapyCalendar
        let moods = Dictionary(grouping: data.moodCheckIns.filter { period.contains($0.date) },
                               by: { calendar.startOfDay(for: $0.date) })
        let legacy = Dictionary(grouping: data.energyEntries.filter { period.contains($0.createdAt) },
                                by: { calendar.startOfDay(for: $0.createdAt) })
        let guided = Dictionary(grouping: data.guidedCheckIns.filter { !$0.isDraft && period.contains($0.date) }, by: { calendar.startOfDay(for: $0.date) })
        let days = Set(moods.keys).union(legacy.keys).union(guided.keys).sorted()
        var segment = 0
        var previous: Date?
        return days.map { day in
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day != 1 { segment += 1 }
            previous = day
            let entries = moods[day] ?? []
            let old = legacy[day] ?? []
            let new = guided[day] ?? []
            return DailyWellnessValue(date: day,
                mood: average(entries.map { ($0.moodPercent.map { 1 + Double($0) / 25 } ?? Double($0.mood)) } + new.compactMap { $0.moodPercent.map { 1 + Double($0) / 25 } ?? $0.mood.map(Double.init) }),
                battery: average(entries.map { Double($0.battery) } + old.map { $0.percent.map { 1 + Double($0) / 25 } ?? Double($0.level) } + new.compactMap { $0.batteryPercent.map { 1 + Double($0) / 25 } }),
                stress: average(entries.compactMap { $0.stress.map(Double.init) } + new.compactMap { $0.stress.map(Double.init) }),
                sensory: average(entries.compactMap { $0.sensoryLoad.map(Double.init) } + new.compactMap { $0.sensoryLoad.map(Double.init) }),
                count: entries.count + old.count + new.count, segment: segment)
        }
    }
    static func categoryTotals(_ points: [BatteryPoint]) -> [BatteryCategoryTotal] {
        BatteryCategory.allCases.flatMap { category in
            BatteryDirection.allCases.compactMap { direction -> BatteryCategoryTotal? in
                let selected = points.filter { $0.category == category && $0.direction == direction }
                guard !selected.isEmpty else { return nil }
                return BatteryCategoryTotal(category: category, direction: direction,
                                            count: selected.count, impact: selected.reduce(0) { $0 + $1.signedImpact })
            }
        }
    }
    static func average(_ numbers: [Double]) -> Double? {
        numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
    }
    static func recordedDays(_ data: AppData, period: WellnessPeriod) -> Int {
        Set(data.moodCheckIns.filter { period.contains($0.date) }
            .map { Calendar.therapyCalendar.startOfDay(for: $0.date) } + data.guidedCheckIns.filter { !$0.isDraft && period.contains($0.date) }.map { Calendar.therapyCalendar.startOfDay(for: $0.date) }).count
    }
}

enum WellnessExport {
    static func csv(_ data: AppData, period: WellnessPeriod) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = [["Typ", "Datum", "Stimmung 1-5", "Akku 1-5", "Stress 1-5", "Reize 1-5", "Schlafstunden",
                     "Gefühle", "Bereich", "Richtung", "Wirkung 1-5", "Text", "Notiz", "Kleiner Erfolg", "Nächster Bedarf"]]
        for entry in data.moodCheckIns.filter({ period.contains($0.date) }).sorted(by: { $0.date < $1.date }) {
            rows.append(["Check-in", formatter.string(from: entry.date), String(entry.mood), String(entry.battery),
                         entry.stress.map(String.init) ?? "", entry.sensoryLoad.map(String.init) ?? "",
                         entry.sleepHours.map { String($0) } ?? "", entry.emotions.joined(separator: ", "),
                         "", "", "", "", entry.note, entry.smallWin, entry.nextNeed])
        }
        for point in data.batteryPoints.filter({ period.contains($0.date) }).sorted(by: { $0.date < $1.date }) {
            rows.append(["Akku-Punkt", formatter.string(from: point.date), "", "", "", "", "", "",
                         point.category.title, point.direction.title, (point.hasConfirmedImpact ? String(point.impact) : "nicht angegeben"), point.title, point.note, "", ""])
        }
        for entry in data.energyEntries.filter({ period.contains($0.createdAt) }) {
            rows.append(["Früherer Energie-Check", formatter.string(from: entry.createdAt), "", String(entry.level),
                         "", "", "", "", "", "", "", entry.givesEnergy + " / " + entry.takesEnergy, (entry.percent.map { "Akku: \($0) % | " } ?? "") + entry.note, "", ""])
        }
        for review in data.weekReviews.filter({ period.contains($0.weekStart) }) {
            rows.append(["Wochenrückblick", formatter.string(from: review.weekStart), "", "", "", "", "", "", "", "", "",
                         review.summary, "Hilfreich: " + review.whatHelped + " | Schwierig: " + review.whatWasHard
                         + " | Therapiefrage: " + review.therapyQuestion, review.smallWin, review.nextStep])
        }
        for entry in data.guidedCheckIns.filter({ !$0.isDraft && period.contains($0.date) }).sorted(by: { $0.date < $1.date }) {
            let battery = entry.batteryPercent.map { String(1 + Double($0) / 25) } ?? ""
            let context = "Akku in Prozent: " + (entry.batteryPercent.map(String.init) ?? "offen") + " | Energiegeber: " + entry.givesEnergy + " | Energienehmer: " + entry.takesEnergy + " | Therapiefrage: " + entry.therapyQuestion + (entry.satisfaction.map { " | Zufriedenheit: \($0)/5" } ?? "")
            rows.append([entry.kind.title, formatter.string(from: entry.date), entry.mood.map(String.init) ?? "", battery,
                         entry.stress.map(String.init) ?? "", entry.sensoryLoad.map(String.init) ?? "", entry.sleepHours.map { String($0) } ?? "",
                         "", "", "", "", entry.summary, context, entry.smallWin, entry.nextNeed])
        }
        return "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ";") }.joined(separator: "\r\n")
    }
    static func cell(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Personal methods and support (schema 15, entirely portable)
enum MethodStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case prevent, contain, calm
    var id: String { rawValue }
    var title: String { switch self { case .prevent: "Vorbeugen"; case .contain: "Eindämmen"; case .calm: "Beruhigen" } }
    var symbol: String { switch self { case .prevent: "shield.lefthalf.filled"; case .contain: "hand.raised.fill"; case .calm: "leaf.fill" } }
}
enum CopingMethodKind: String, Codable, CaseIterable, Identifiable {
    case method, thoughtStop
    var id: String { rawValue }
    var title: String { self == .method ? "Methode" : "Gedankenstopp" }
}
struct CopingMethod: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var title = ""
    var kind: CopingMethodKind = .method
    var situation = ""
    var details = ""
    var steps: [String] = []
    var categories: [BatteryCategory] = []
    var stages: [MethodStage] = [.calm]
    var batteryPointIDs: [UUID] = []
    var favorite = false
    static var asmrExample: CopingMethod {
        CopingMethod(title: "ASMR", situation: "Geräusche oder Musik werden mir zu laut", details: "Wenn es mir hilft: Reize reduzieren und vertrautes ASMR leise hören. Ich darf jederzeit stoppen oder lieber Stille wählen.", steps: ["Einen ruhigeren Ort suchen", "Vertrautes ASMR leise starten, wenn ich es möchte", "Prüfen: Ist es angenehmer? Sonst stoppen"], categories: [.sensory, .rest], stages: [.contain, .calm])
    }
    static var thoughtStopExample: CopingMethod {
        CopingMethod(title: "Mein Gedankenstopp", kind: .thoughtStop, situation: "Ich gerate ins Grübeln", details: "Stopp. Ich muss das gerade nicht lösen. Ich richte meine Aufmerksamkeit auf einen ruhigen nächsten Schritt.", steps: ["Den Gedanken bemerken", "Meinen Stoppsatz freundlich sagen", "Eine kleine Handlung im Hier und Jetzt wählen"], categories: [.rest], stages: [.contain, .calm])
    }
    func matches(category: BatteryCategory?, stage: MethodStage?, query: String, data: AppData) -> Bool {
        let linked = data.batteryPoints.filter { batteryPointIDs.contains($0.id) }
        let fitsCategory = category.map { selected in categories.contains(selected) || linked.contains { $0.category == selected } } ?? true
        let text = ([title, situation, details] + steps + linked.map(\.title)).joined(separator: " ")
        return fitsCategory && (stage == nil || stages.contains(stage!)) && (query.isEmpty || text.localizedStandardContains(query))
    }
}
struct PersonalEmergencyPlan: Codable, Equatable {
    var title = "Mein Notfallplan"
    var warningSigns = ""
    var firstStep = ""
    var steps: [String] = []
    var support = ""
    var imageID: UUID?
    var methodIDs: [UUID] = []
    var updatedAt: Date?
    var panels: [EmergencyPanel]?
    var compactLayout: Bool?
    var hasContent: Bool { !(panels ?? []).isEmpty || !warningSigns.isEmpty || !firstStep.isEmpty || !steps.isEmpty || !support.isEmpty || imageID != nil || !methodIDs.isEmpty }
}
struct GroundingPractice: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var answers: [[String]] = Array(repeating: [], count: 5)
    var note = ""
}
struct ShowerEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var note = ""
}
enum GroundingGuide {
    static let counts = [5, 4, 3, 2, 1]
    static let titles = ["Fünf Dinge, die du siehst", "Vier Dinge, die du spürst", "Drei Dinge, die du hörst", "Zwei Dinge, die du riechst", "Eine Sache, die du schmeckst"]
    static let symbols = ["eye.fill", "hand.raised.fill", "ear.fill", "nose", "mouth.fill"]
    static let hints = ["Schau dich in deinem Tempo um. Zum Beispiel eine Farbe oder eine Form.", "Zum Beispiel deine Füße am Boden, den Stuhl oder die Kleidung auf deiner Haut.", "Nur angenehme oder neutrale Geräusche. Du musst nichts extra abspielen.", "Wenn gerade kein Geruch da ist, denke an etwas Vertrautes oder überspringe den Schritt.", "Zum Beispiel einen vorhandenen Geschmack. Du brauchst nichts zu essen oder zu trinken."]
}


struct ShowerPreferences: Codable, Equatable {
    var weeklyGoal = 3
}
struct RoutineDeferral: Codable, Equatable, Identifiable {
    var routineID: UUID
    var timeID: UUID
    var scheduledAt: Date
    var deferredUntil: Date
    var createdAt = Date()
    var occurrenceID: String { "\(routineID).\(timeID).\(Int(scheduledAt.timeIntervalSince1970))" }
    var id: String { occurrenceID }
}
enum ShowerPlanner {
    static func isShower(_ routine: DailyRoutine) -> Bool { routine.symbol == "shower.fill" || routine.title.localizedCaseInsensitiveContains("dusch") }
    static func isShower(_ entry: RoutineCompletion, data: AppData) -> Bool {
        data.routines.first { $0.id == entry.routineID }.map(isShower) == true || (entry.routineTitle ?? "").localizedCaseInsensitiveContains("dusch")
    }
    static func dates(_ data: AppData) -> [Date] {
        data.showerEntries.map(\.date) + data.routineCompletions.filter { $0.outcome == .done && isShower($0, data: data) }.map(\.recordedAt)
    }
    static func weekCount(_ data: AppData, at date: Date, calendar: Calendar = .therapyCalendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return Set(dates(data).filter { $0 >= week.start && $0 < week.end }.map { calendar.startOfDay(for: $0) }).count
    }
    static func today(_ data: AppData, at now: Date = Date(), calendar: Calendar = .current) -> [RoutineOccurrence] {
        RoutinePlanner.occurrences(data: data, now: calendar.startOfDay(for: now), days: 1, calendar: calendar).filter { occurrence in
            calendar.isDate(occurrence.due, inSameDayAs: now) && data.routines.first { $0.id == occurrence.routineID }.map(isShower) == true
        }
    }
    static func defaultRoutine(at now: Date = Date(), everyTwoDays: Bool = false, calendar: Calendar = .current) -> DailyRoutine {
        var routine = DailyRoutine(title: "Duschen", symbol: "shower.fill", times: [RoutineTime(weekdays: everyTwoDays ? Array(1...7) : [2,4,6], hour: 19, minute: 0)])
        routine.repeatUntilDone = false
        routine.escalationHour = nil
        if everyTwoDays { routine.recurrenceAnchor = calendar.startOfDay(for: now); routine.repeatEveryDays = 2 }
        return routine
    }
}
enum RoutineDayMutation {
    @discardableResult static func resolve(_ occurrence: RoutineOccurrence, outcome: RoutineOutcome, note: String, in data: inout AppData, at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let routine = data.routines.first(where: { $0.id == occurrence.routineID }),
              calendar.startOfDay(for: occurrence.due) <= calendar.startOfDay(for: now),
              !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions),
              RoutinePlanner.occurrences(data: data, now: calendar.startOfDay(for: now), days: 1, calendar: calendar).contains(where: { $0.id == occurrence.id && $0.due == occurrence.due }) else { return false }
        data.routineCompletions.insert(RoutineCompletion(routineID: routine.id, timeID: occurrence.timeID, scheduledAt: occurrence.scheduledAt, recordedAt: now, outcome: outcome, note: note, routineTitle: routine.title, timeTitle: routine.times.first { $0.id == occurrence.timeID }?.title), at: 0)
        data.routineSnoozes.removeAll { $0.id == occurrence.id }
        return true
    }
    @discardableResult static func postpone(_ occurrence: RoutineOccurrence, until date: Date, in data: inout AppData, at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard date > now, date > occurrence.due, !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions),
              data.routines.contains(where: { $0.id == occurrence.routineID }),
              RoutinePlanner.occurrences(data: data, now: calendar.startOfDay(for: now), days: 1, calendar: calendar).contains(where: { $0.id == occurrence.id && $0.due == occurrence.due }) else { return false }
        if let routine = data.routines.first(where: { $0.id == occurrence.routineID }), ShowerPlanner.isShower(routine), RoutinePlanner.occurrences(data: data, now: now, days: 14, calendar: calendar).contains(where: { $0.id != occurrence.id && $0.routineID == occurrence.routineID && $0.timeID == occurrence.timeID && calendar.isDate($0.due, inSameDayAs: date) && !RoutinePlanner.resolved($0, completions: data.routineCompletions) }) {
            return resolve(occurrence, outcome: .skipped, note: "Verschoben bis zum nächsten regulären Duschtag", in: &data, at: now, calendar: calendar)
        }
        data.routineDeferrals.removeAll { $0.id == occurrence.id }
        data.routineDeferrals.append(RoutineDeferral(routineID: occurrence.routineID, timeID: occurrence.timeID, scheduledAt: occurrence.scheduledAt, deferredUntil: date, createdAt: now))
        data.routineSnoozes.removeAll { $0.id == occurrence.id }
        return true
    }
}

// Apple integration settings contain preferences only. OS grants and identifiers stay on-device.
struct EmergencyPanel: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var text = ""
    var symbol = "heart.fill"
    var methodID: UUID?
    var enabled = true
}
struct MedicalPass: Codable, Equatable {
    var name = ""
    var birthDate: Date?
    var heightCM: Int?
    var medications = ""
    var conditions = ""
    var allergies = ""
    var contacts = ""
    var notes = ""
    func age(at date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthDate, birthDate <= date else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: date).year
    }
}
struct AppleIntegrationPreferences: Codable, Equatable {
    var remindersEnabled = false
    var removeFinishedReminders = true
    var privateReminderTitles = true
    var alarmDelayMinutes = 10
}
enum WakeChallengeKind: String, Codable, CaseIterable, Identifiable {
    case none, math, photo, movement, steps
    var id: String { rawValue }
    var title: String { switch self { case .none: "Bestätigen"; case .math: "Rechenaufgabe"; case .photo: "Frisches Kamerafoto"; case .movement: "Sanfte Bewegung"; case .steps: "Ein paar Schritte" } }
}
struct WakeAlarm: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "Aufstehen"
    var enabled = true
    var hour = 6
    var minute = 30
    var weekdays = [2, 3, 4, 5, 6]
    var excludedDays: [Date] = []
    var challenge: WakeChallengeKind = .math
    var photoObject = "Eine Flasche"
    var movementCount = 5
    var stepCount = 15
    var snoozeMinutes = 5
    var maxSnoozes = 3
    var followUpCount = 3
    var followUpMinutes = 2
    var buttonTitle = "Aufgabe öffnen"
    var snoozeTitle = "Schlummern"
}
enum WakeRunOutcome: String, Codable { case completed, emergencyStopped }
struct WakeRun: Codable, Equatable, Identifiable {
    var id: String
    var alarmID: UUID
    var scheduledAt: Date
    var finishedAt: Date?
    var outcome: WakeRunOutcome?
    var snoozes = 0
    var emergencySnoozeUsed = false
    var snoozedUntil: Date?
    var revision = 0
    var operandA = Int.random(in: 4...19)
    var operandB = Int.random(in: 2...12)
    var answer: Int { operandA + operandB }
}
struct WakeOccurrence: Equatable, Identifiable {
    var alarm: WakeAlarm
    var date: Date
    var id: String { "wake.\(alarm.id).\(Int(date.timeIntervalSince1970))" }
}
enum WakePlanner {
    static func occurrences(data: AppData, now: Date = Date(), days: Int = 8, calendar: Calendar = .current) -> [WakeOccurrence] {
        var result: [WakeOccurrence] = []
        for offset in -1..<max(1, min(31, days)) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for alarm in data.wakeAlarms where alarm.enabled && alarm.weekdays.contains(calendar.component(.weekday, from: day)) {
                guard !alarm.excludedDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }),
                      let due = calendar.date(bySettingHour: max(0,min(23,alarm.hour)), minute: max(0,min(59,alarm.minute)), second: 0, of: day),
                      let end = calendar.date(byAdding: .day, value: 1, to: due), end > now else { continue }
                result.append(.init(alarm: alarm, date: due))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    static func slots(data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [CompanionAlarmSlot] {
        var result: [CompanionAlarmSlot] = []
        for occurrence in occurrences(data: data, now: now, calendar: calendar) {
            let run = data.wakeRuns.first { $0.id == occurrence.id }
            guard run?.outcome == nil else { continue }
            let alarm = occurrence.alarm
            let base = run?.snoozedUntil ?? occurrence.date
            for index in 0...max(0, min(5, alarm.followUpCount)) {
                let fire = base.addingTimeInterval(Double(index * max(1, min(30, alarm.followUpMinutes))) * 60)
                guard fire > now else { continue }
                result.append(.init(id: occurrence.id + ".r\(run?.revision ?? 0).\(index)", group: "wake.\(alarm.id)", fireAt: fire,
                                    title: alarm.title, route: "wake|\(alarm.id)|\(Int(occurrence.date.timeIntervalSince1970))"))
            }
        }
        return result.sorted { $0.fireAt < $1.fireAt }
    }
}
struct OwnedReminderDraft: Equatable, Identifiable {
    var id: String
    var title: String
    var due: Date
    var route: String
    var routineOccurrence: RoutineOccurrence?
    var taskID: UUID?
}
enum AppleReminderPlanner {
    static func drafts(data: AppData, now: Date = Date(), calendar: Calendar = .current) -> [OwnedReminderDraft] {
        guard data.appleIntegration.remindersEnabled else { return [] }
        var result: [OwnedReminderDraft] = []
        for occurrence in RoutinePlanner.occurrences(data: data, now: now, days: 8, calendar: calendar) {
            guard let routine = data.routines.first(where: { $0.id == occurrence.routineID }), routine.remindersEnabled,
                  routine.appleReminders != false, RoutinePlanner.activeReminder(routine, occurrence: occurrence, settings: data.companionSettings, now: now),
                  !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions) else { continue }
            result.append(.init(id: "routine." + occurrence.id, title: data.appleIntegration.privateReminderTitles ? "Deine Routine" : routine.title,
                                due: occurrence.due, route: "routine/\(routine.id)", routineOccurrence: occurrence))
        }
        for task in data.weeklyTasks where !task.completed {
            guard let due = task.dueDate, due > now.addingTimeInterval(-86400), due < now.addingTimeInterval(8 * 86400) else { continue }
            result.append(.init(id: "task.\(task.id)", title: data.appleIntegration.privateReminderTitles ? "Dein nächster Schritt" : task.title, due: due, route: "task/\(task.id)", taskID: task.id))
        }
        return result.sorted { $0.due < $1.due }.prefix(100).map { $0 }
    }
}
