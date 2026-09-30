import SwiftUI

struct LegacyEnergyEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var entry: EnergyEntry
    private let initial: EnergyEntry
    init(entry: EnergyEntry) { initial = entry; _entry = State(initialValue: entry) }
    var body: some View {
        TherapyEditorSheet(title: "Energie-Check bearbeiten", dirty: entry != initial, save: {
            if let index = store.data.energyEntries.firstIndex(where: { $0.id == entry.id }) { store.data.energyEntries[index] = entry }
        }) {
            Section("Energie") {
                DatePicker("Datum", selection: $entry.createdAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Stepper("Energie: \(entry.level)/5", value: $entry.level, in: 1...5)
                TextField("Gibt mir Energie", text: $entry.givesEnergy, axis: .vertical).lineLimit(2...6)
                TextField("Nimmt mir Energie", text: $entry.takesEnergy, axis: .vertical).lineLimit(2...6)
                TextField("Notiz", text: $entry.note, axis: .vertical).lineLimit(3...8)
            }
        }
    }
}

struct TherapyReflectionEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var entry: TherapySessionReflection
    private let initial: TherapySessionReflection
    init(entry: TherapySessionReflection = TherapySessionReflection(summary: "", whatHelped: "", nextFocus: "")) {
        initial = entry; _entry = State(initialValue: entry)
    }
    var body: some View {
        TherapyEditorSheet(title: "Therapie-Rückblick", dirty: entry != initial, canSave: [entry.summary, entry.whatHelped, entry.nextFocus].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, save: {
            var snapshot = store.data
            snapshot.reflections.removeAll { $0.id == entry.id }
            snapshot.reflections.insert(entry, at: 0)
            store.data = snapshot
        }) {
            Section("Deine Stunde") {
                DatePicker("Datum", selection: $entry.date, in: ...Date(), displayedComponents: .date)
                TextField("Was haben wir gemacht?", text: $entry.summary, axis: .vertical).lineLimit(3...10)
                TextField("Was hat mir geholfen?", text: $entry.whatHelped, axis: .vertical).lineLimit(3...8)
                TextField("Was möchte ich als Nächstes besprechen?", text: $entry.nextFocus, axis: .vertical).lineLimit(3...8)
            }
        }
    }
}

struct WeeklyTaskEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var task: WeeklyTask
    @State private var weekDate: Date
    private let initial: WeeklyTask
    init(task: WeeklyTask? = nil) {
        let week = Date().therapyWeek
        var value = task ?? WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: "", details: "")
        if task == nil { value.reminder = TaskReminder() }
        initial = value; _task = State(initialValue: value)
        let date = Calendar.therapyCalendar.date(from: DateComponents(weekOfYear: value.weekOfYear, yearForWeekOfYear: value.yearForWeekOfYear)) ?? Date()
        _weekDate = State(initialValue: date)
    }
    var body: some View {
        TherapyEditorSheet(title: "Wochenaufgabe", dirty: task != initial, canSave: !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: {
            var clean = task
            clean.weekOfYear = weekDate.therapyWeek.week; clean.yearForWeekOfYear = weekDate.therapyWeek.year
            clean.completedAt = clean.completed ? (clean.completedAt ?? Date()) : nil
            if clean.completed { clean.progress = 100; clean.reminderShiftedAt = nil }
            var snapshot = store.data; snapshot.weeklyTasks.removeAll { $0.id == clean.id }; snapshot.weeklyTasks.insert(clean, at: 0); store.data = snapshot
        }) {
            Section {
                TextField("Was möchte ich ausprobieren?", text: $task.title, axis: .vertical).lineLimit(2...5)
                TextField("Beschreibung oder kleine Schritte", text: $task.details, axis: .vertical).lineLimit(3...10)
                DatePicker("Woche auswählen", selection: $weekDate, displayedComponents: .date)
                    .onChange(of: weekDate) { _, value in task.weekOfYear = value.therapyWeek.week; task.yearForWeekOfYear = value.therapyWeek.year }
                Toggle("Erledigt", isOn: $task.completed)
                Picker("Therapiethema", selection: $task.topicID) {
                    Text("Ohne Thema").tag(Optional<UUID>.none)
                    ForEach(store.data.therapyTopics) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Therapieziel", selection: $task.goalID) {
                    Text("Ohne Ziel").tag(Optional<UUID>.none)
                    ForEach(store.data.therapyGoals) { Text($0.title).tag(Optional($0.id)) }
                }
            } header: { Text("Aufgabe") } footer: { Text("Erledigte Aufgaben kannst du jederzeit wieder als offen markieren.") }
            Section("In kleinen Schritten") {
                TextField("Mein kleinster nächster Schritt", text: Binding(get: { task.smallStep ?? "" }, set: { task.smallStep = $0 }), axis: .vertical).lineLimit(2...5)
                TextField("Was oder wer unterstützt mich?", text: Binding(get: { task.support ?? "" }, set: { task.support = $0 }), axis: .vertical).lineLimit(2...5)
                Slider(value: Binding(get: { Double(task.progress ?? 0) }, set: { task.progress = Int($0) }), in: 0...100, step: 10)
                Text("Fortschritt: \(task.progress ?? 0) %")
                Toggle("Zieltermin festlegen", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (task.dueDate ?? Date()) : nil }))
                if task.dueDate != nil { DatePicker("Zieltermin", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }), displayedComponents: .date) }
            }
            Section {
                Toggle("Bis zum Erledigen erinnern", isOn: reminder.enabled)
                if reminder.wrappedValue.enabled {
                    DatePicker("Uhrzeit", selection: reminderTime, displayedComponents: .hourAndMinute)
                    WeekdaySelection(days: reminder.weekdays)
                    Button("Täglich erinnern") { reminder.wrappedValue.weekdays = Array(1...7) }
                    if reminder.wrappedValue.weekdays.isEmpty { Text("Wähle mindestens einen Tag.").foregroundStyle(.orange) }
                }
                Text("Mitteilungen wiederholen sich, solange die Aufgabe offen ist. Speichern richtet sie automatisch ein, wenn Mitteilungen erlaubt sind.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Meine Erinnerung") }
        }
    }
    private var reminder: Binding<TaskReminder> { Binding(get: { TaskReminderPlanner.settings(for: task, schedule: store.data.schedule) }, set: { task.reminder = $0 }) }
    private var reminderTime: Binding<Date> {
        Binding { Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: reminder.wrappedValue.hour, minute: reminder.wrappedValue.minute)) ?? Date() } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var value = reminder.wrappedValue; value.hour = parts.hour ?? 18; value.minute = parts.minute ?? 0; reminder.wrappedValue = value
        }
    }
}
