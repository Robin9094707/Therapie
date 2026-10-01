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
    var signedImpact: Int { direction.sign * impact }
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
                battery: average(entries.map { Double($0.battery) } + old.map { Double($0.level) } + new.compactMap { $0.batteryPercent.map { 1 + Double($0) / 25 } }),
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
                         point.category.title, point.direction.title, String(point.impact), point.title, point.note, "", ""])
        }
        for entry in data.energyEntries.filter({ period.contains($0.createdAt) }) {
            rows.append(["Früherer Energie-Check", formatter.string(from: entry.createdAt), "", String(entry.level),
                         "", "", "", "", "", "", "", entry.givesEnergy + " / " + entry.takesEnergy, entry.note, "", ""])
        }
        for review in data.weekReviews.filter({ period.contains($0.weekStart) }) {
            rows.append(["Wochenrückblick", formatter.string(from: review.weekStart), "", "", "", "", "", "", "", "", "",
                         review.summary, "Hilfreich: " + review.whatHelped + " | Schwierig: " + review.whatWasHard
                         + " | Therapiefrage: " + review.therapyQuestion, review.smallWin, review.nextStep])
        }
        for entry in data.guidedCheckIns.filter({ !$0.isDraft && period.contains($0.date) }).sorted(by: { $0.date < $1.date }) {
            let battery = entry.batteryPercent.map { String(1 + Double($0) / 25) } ?? ""
            let context = "Akku in Prozent: " + (entry.batteryPercent.map(String.init) ?? "offen") + " | Energiegeber: " + entry.givesEnergy + " | Energienehmer: " + entry.takesEnergy + " | Therapiefrage: " + entry.therapyQuestion
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
