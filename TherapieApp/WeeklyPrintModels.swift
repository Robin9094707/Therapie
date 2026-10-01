import Foundation

struct WeeklyPrintOptions: Equatable {
    var weekStart = Date().therapyWeekStart.therapyAddingWeeks(-1)
    var maxPages = 3
    var includeName = true
    var includeMood = true
    var includeBattery = true
    var includeCheckIns = true
    var includeTasks = true
    var includeGoals = true
    var includeRoutines = true
    var includeNotes = true
    var photoIDs: Set<UUID> = []
    var period: WellnessPeriod { .week(containing: weekStart) }
}
struct WeeklyPrintRow: Equatable {
    var section: String
    var title: String
    var text: String
}
struct WeeklyPrintPlan {
    var name: String
    var period: WellnessPeriod
    var rows: [WeeklyPrintRow]
    var daily: [DailyWellnessValue]
    var photoIDs: [UUID]
    var maxPages: Int
    var summary: String
    static func make(data: AppData, options: WeeklyPrintOptions) -> WeeklyPrintPlan {
        let period = options.period
        func stamp(_ date: Date) -> String { WeeklyPrintDateFormat.stamp(date) }
        var rows: [WeeklyPrintRow] = []
        func row(_ section: String, _ title: String, _ text: String) { rows.append(.init(section: section, title: title, text: text)) }
        let daily = WellnessAnalytics.daily(data, period: period)
        if options.includeBattery {
            for direction in BatteryDirection.allCases {
                let topics = InsightsAnalytics.keywords(data: data, period: period).filter { $0.direction == direction }
                for topic in topics {
                    let notes = topic.points.filter { !$0.note.isEmpty }.prefix(2).map(\.note).joined(separator: " · ")
                    row(direction == .gives ? "Akkugeber" : "Akkunehmer", topic.keyword + " · \(topic.count)× · Wirkung \(topic.impact)", notes)
                }
            }
            for review in data.weeklyEnergyReviews.filter({ period.contains($0.createdAt) }) {
                row("Wochenenergie", "Akku \(review.energy)/5", ([review.nextStep, review.therapyQuestion] + review.gives.map { "Gibt: " + $0.title } + review.takes.map { "Nimmt: " + $0.title }).filter { !$0.isEmpty }.joined(separator: " · "))
            }
            for legacy in data.energyEntries.filter({ period.contains($0.createdAt) }) where !legacy.givesEnergy.isEmpty || !legacy.takesEnergy.isEmpty || !legacy.note.isEmpty {
                row("Frühere Akku-Einträge", stamp(legacy.createdAt) + " · \(legacy.level)/5", "Gibt: \(legacy.givesEnergy) · Nimmt: \(legacy.takesEnergy) · \(legacy.note)")
            }
        }
        if options.includeCheckIns {
            for entry in data.guidedCheckIns.filter({ !$0.isDraft && period.contains($0.date) }).sorted(by: { $0.date > $1.date }) {
                var values = [entry.summary, entry.smallWin.isEmpty ? "" : "Erfolg: " + entry.smallWin, entry.nextNeed.isEmpty ? "" : "Bedarf: " + entry.nextNeed, entry.therapyQuestion.isEmpty ? "" : "Frage: " + entry.therapyQuestion]
                if options.includeMood { if let value = entry.moodPercent { values.insert("Stimmung \(value)/100", at: 0) } else if let value = entry.mood { values.insert("Stimmung \(value)/5", at: 0) } }
                if options.includeBattery {
                    if let value = entry.batteryPercent { values.insert("Akku \(value) %", at: 0) }
                    values += [entry.givesEnergy.isEmpty ? "" : "Gibt: " + entry.givesEnergy, entry.takesEnergy.isEmpty ? "" : "Nimmt: " + entry.takesEnergy]
                }
                if let value = entry.stress { values.append("Stress \(value)/5") }
                if let value = entry.sensoryLoad { values.append("Reize \(value)/5") }
                if let value = entry.sleepHours { values.append("Schlaf \(value.formatted()) h") }
                row("Check-ins", stamp(entry.date) + " · " + entry.displayTitle, values.filter { !$0.isEmpty }.joined(separator: " · "))
            }
            for entry in data.moodCheckIns.filter({ period.contains($0.date) && (!$0.note.isEmpty || !$0.smallWin.isEmpty || !$0.nextNeed.isEmpty || !$0.emotions.isEmpty || $0.stress != nil || $0.sensoryLoad != nil || $0.sleepHours != nil) }).sorted(by: { $0.date > $1.date }) {
                var values = [entry.note, entry.smallWin, entry.nextNeed, entry.emotions.joined(separator: ", ")]
                if let stress = entry.stress { values.append("Stress \(stress)/5") }
                if let sensory = entry.sensoryLoad { values.append("Reize \(sensory)/5") }
                if let sleep = entry.sleepHours { values.append("Schlaf \(sleep.formatted()) h") }
                if options.includeMood { values.insert(entry.moodTitle, at: 0) }
                if options.includeBattery { values.insert("Akku \(entry.battery)/5", at: 0) }
                row("Stimmungseinträge", stamp(entry.date), values.filter { !$0.isEmpty }.joined(separator: " · "))
            }
            for review in data.weekReviews.filter({ period.contains($0.weekStart) }) {
                var values = [review.summary, review.smallWin, review.nextStep, review.therapyQuestion]
                if options.includeBattery { values += [review.whatHelped, review.whatWasHard] }
                row("Wochenrückblicke", stamp(review.weekStart), values.filter { !$0.isEmpty }.joined(separator: " · "))
            }
            for session in data.sessionHistory.filter({ period.contains($0.startedAt) }) { row("Therapiestunden", stamp(session.startedAt) + " · " + session.title, [session.summary, session.nextStep].filter { !$0.isEmpty }.joined(separator: " · ")) }
            for entry in data.reflections.filter({ period.contains($0.date) }) { row("Therapierückblick", stamp(entry.date), [entry.summary, entry.whatHelped, entry.nextFocus].filter { !$0.isEmpty }.joined(separator: " · ")) }
        }
        if options.includeTasks {
            let week = options.weekStart.therapyWeek
            for task in data.weeklyTasks.filter({ ($0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year) || period.contains($0.createdAt) || ($0.completedAt.map(period.contains) ?? false) || ($0.dueDate.map(period.contains) ?? false) }).sorted(by: { $0.completed == $1.completed ? $0.createdAt > $1.createdAt : !$0.completed }) {
                row("Aufgaben · heutiger Stand", (task.completed ? "Erledigt: " : "Offen: ") + task.title, [task.smallStep ?? "", task.details, task.support ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
        if options.includeGoals { for goal in data.therapyGoals { row("Ziele · heutiger Stand", goal.title + " · \(goal.progress) %", [goal.smallStep, goal.support].filter { !$0.isEmpty }.joined(separator: " · ")) } }
        if options.includeRoutines {
            let logs = data.routineCompletions.filter { period.contains($0.scheduledAt) }
            let grouped = Dictionary(grouping: logs, by: { RoutineHistoryMutation.title($0, data: data) })
            for title in grouped.keys.sorted() {
                let items = grouped[title] ?? []
                row("Routinen · eigene Bestätigungen", title, "\(items.filter { $0.outcome == .done }.count) erledigt · \(items.filter { $0.outcome == .skipped }.count) ausgelassen. " + items.filter { !$0.note.isEmpty }.prefix(2).map(\.note).joined(separator: " · "))
            }
        }
        if options.includeNotes {
            for note in data.notes.filter({ period.contains($0.createdAt) || ($0.updatedAt.map(period.contains) ?? false) }).sorted(by: { ($0.isImportant ?? false) == ($1.isImportant ?? false) ? $0.createdAt > $1.createdAt : $0.isImportant == true }) {
                row("Notizen", note.title + " · " + stamp(note.createdAt), note.text)
            }
        }
        let mood = options.includeMood ? WellnessAnalytics.average(daily.compactMap(\.mood)) : nil
        let battery = options.includeBattery ? WellnessAnalytics.average(daily.compactMap(\.battery)) : nil
        let summary = [mood.map { String(format: "Stimmung Ø %.1f/5", $0) }, battery.map { String(format: "Akku Ø %.0f %%", ($0 - 1) * 25) }].compactMap { $0 }.joined(separator: "   ·   ")
        let selected = data.media.filter { $0.kind == .photo && options.photoIDs.contains($0.id) && $0.attachmentOmitted != true }.sorted { $0.createdAt < $1.createdAt }.prefix(3).map(\.id)
        let plotted = daily.map { value -> DailyWellnessValue in return DailyWellnessValue(date: value.date, mood: options.includeMood ? value.mood : nil, battery: options.includeBattery ? value.battery : nil, stress: value.stress, sensory: value.sensory, count: value.count, segment: value.segment) }
        return WeeklyPrintPlan(name: options.includeName ? data.profile.userName : "", period: period, rows: rows, daily: plotted, photoIDs: selected, maxPages: max(1, min(3, options.maxPages)), summary: summary.isEmpty ? "Keine Angaben in den gewählten Messwerten." : summary)
    }
}

enum WeeklyPrintDateFormat {
    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "de_DE"); formatter.calendar = .therapyCalendar; formatter.timeZone = Calendar.therapyCalendar.timeZone; formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
    static func day(_ date: Date) -> String { format(date, pattern: "dd.MM.yyyy") }
    static func stamp(_ date: Date) -> String { format(date, pattern: "dd.MM. HH:mm") }
    static func weekday(_ date: Date) -> String { format(date, pattern: "EE") }
}
