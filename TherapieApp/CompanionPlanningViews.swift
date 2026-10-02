import SwiftUI
import Charts

struct CheckInReminderSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var reminders: [CheckInReminder]
    @State private var error: String?
    let slots: [DailyCheckInSlot]
    init(reminders: [CheckInReminder], slots: [DailyCheckInSlot]) {
        self.slots = slots
        _reminders = State(initialValue: slots.map { slot in
            var value = reminders.first { $0.slotID == slot.id || ($0.slotID == nil && $0.kind == slot.kind && slot.kind != .free) } ?? CheckInReminder(kind: slot.kind, enabled: false, time: RoutineTime(hour: slot.kind == .morning ? 7 : slot.kind == .noon ? 12 : slot.kind == .afternoon ? 16 : slot.kind == .evening ? 20 : slot.startHour, minute: 0))
            value.slotID = slot.id
            return value
        })
    }
    private func valid(_ reminder: CheckInReminder) -> Bool {
        guard reminder.enabled else { return true }
        guard let slot = slots.first(where: { $0.id == reminder.slotID }), slot.enabled, !reminder.time.weekdays.isEmpty else { return false }
        return reminder.time.weekdays.allSatisfy { day in
            let clock = reminder.time.clock(weekday: day)
            let hour = clock.hour
            return slot.startHour == slot.endHour || (slot.startHour < slot.endHour ? hour >= slot.startHour && hour < slot.endHour : hour >= slot.startHour || hour < slot.endHour)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ein freundlicher Hinweis für deinen Check-in. Fragen bleiben freiwillig; Entwürfe kannst du später fortsetzen.")
                    Button("Mitteilungen erlauben", systemImage: "bell") { Task { await TaskNotificationCoordinator.shared.requestAccess(store) } }
                    Button("AlarmKit-Wecker erlauben", systemImage: "alarm") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store) } }
                    Text(store.routineAlarmStatus).font(.caption).foregroundStyle(.secondary)
                    if !store.checkInReminderStatus.isEmpty { Text(store.checkInReminderStatus).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(reminders) { initial in
                    let reminder = identifiedEditorBinding($reminders, to: initial)
                    let slot = slots.first { $0.id == initial.slotID }
                    Section(slot?.title ?? initial.kind.title) {
                        Toggle("Erinnerung aktiv", isOn: reminder.enabled)
                        if reminder.wrappedValue.enabled {
                            CheckInClockFields(time: reminder.time)
                            Toggle("Zusätzlich als AlarmKit-Wecker", isOn: Binding(get: { reminder.wrappedValue.alarmEnabled ?? false }, set: { reminder.wrappedValue.alarmEnabled = $0 }))
                            Toggle("Im Urlaubsmodus pausieren", isOn: reminder.pauseOnVacation)
                            Text("Check-in verfügbar: " + (slot?.windowText ?? "entfernt")).font(.caption).foregroundStyle(.secondary)
                            if !valid(reminder.wrappedValue) { Text("Aktiviere diesen Check-in und wähle eine Zeit innerhalb seines Zeitfensters sowie mindestens einen Wochentag.").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
                Section {
                    Text("Bereits abgeschlossene Check-ins entfernen den Hinweis für den jeweiligen Tag. Zeiten folgen deiner lokalen iPhone-Zeitzone. Die App plant bis zu sieben Tage voraus und erneuert den Vorrat beim Öffnen.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.buttonStyle(.borderless).navigationTitle("Check-in-Erinnerungen").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            store.data.companionSettings.checkInReminders = reminders
                            if let failure = store.lastSaveError { error = failure } else { dismiss() }
                        }.disabled(!reminders.allSatisfy(valid))
                    }
                }
        }
    }
}
private struct CheckInClockFields: View {
    @Binding var time: RoutineTime
    var body: some View {
        DatePicker("Uhrzeit", selection: clock(weekend: false), displayedComponents: .hourAndMinute)
        VStack(alignment: .leading, spacing: 8) {
            Text("Wochentage").font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Button {
                        if time.weekdays.contains(day) { time.weekdays.removeAll { $0 == day } } else { time.weekdays.append(day) }
                    } label: {
                        Text(String(TherapyDateHelper.weekdayName(day).prefix(2))).frame(maxWidth: .infinity).padding(10)
                            .background(time.weekdays.contains(day) ? Color.indigo.opacity(0.18) : Color.primary.opacity(0.05), in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(TherapyDateHelper.weekdayName(day)).accessibilityAddTraits(time.weekdays.contains(day) ? .isSelected : [])
                }
            }
            if time.weekdays.isEmpty { Text("Wähle mindestens einen Tag.").font(.caption).foregroundStyle(.orange) }
        }
        Toggle("Andere Wochenendzeit", isOn: Binding(get: { time.weekendHour != nil }, set: { time.weekendHour = $0 ? time.hour : nil; time.weekendMinute = $0 ? time.minute : nil }))
        if time.weekendHour != nil { DatePicker("Samstag & Sonntag", selection: clock(weekend: true), displayedComponents: .hourAndMinute) }
    }
    private func clock(weekend: Bool) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: weekend ? time.weekendHour ?? time.hour : time.hour, minute: weekend ? time.weekendMinute ?? time.minute : time.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if weekend { time.weekendHour = parts.hour; time.weekendMinute = parts.minute }
            else { time.hour = parts.hour ?? 7; time.minute = parts.minute ?? 0 }
        })
    }
}

struct TherapyReportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var checkIns = true
    @State private var moodEntries = true
    @State private var tasks = true
    @State private var goals = true
    @State private var routines = false
    @State private var notes = false
    @State private var names = false
    @State private var excluded = Set<UUID>()
    @State private var preview = false
    private var options: TherapyReportOptions {
        TherapyReportOptions(start: Calendar.current.startOfDay(for: start), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end, includeCheckIns: checkIns, includeMoodEntries: moodEntries, includeTasks: tasks, includeGoals: goals, includeRoutines: routines, includeNotes: notes, includeNames: names, excludedCheckInIDs: excluded)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bereite deinen nächsten Therapietermin vor. Du bestimmst, welche Angaben in der Vorschau und beim Teilen erscheinen.")
                    if let next = TherapyDateHelper.nextOccurrence(schedule: store.data.schedule) {
                        Label("Nächster Termin: " + next.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                }
                Section("Zeitraum") {
                    Picker("Schnellauswahl", selection: Binding<Int>(get: { 0 }, set: { days in
                        if days > 0 { end = Date(); start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end) ?? end }
                    })) {
                        Text("Zeitraum wählen").tag(0); Text("Letzte 7 Tage").tag(7); Text("Letzte 14 Tage").tag(14); Text("Letzte 30 Tage").tag(30)
                    }
                    DatePicker("Von", selection: $start, in: ...end, displayedComponents: .date)
                    DatePicker("Bis einschließlich", selection: $end, in: start...Date(), displayedComponents: .date)
                }
                Section("Diese Inhalte aufnehmen") {
                    Toggle("Abgeschlossene Check-ins", isOn: $checkIns)
                    Toggle("Stimmungseinträge", isOn: $moodEntries)
                    Toggle("Aufgaben aus dem Zeitraum", isOn: $tasks)
                    Toggle("Ziele · aktueller Stand", isOn: $goals)
                    Toggle("Routinenprotokoll", isOn: $routines)
                    Toggle("Notizen", isOn: $notes)
                    Toggle("Meine Namen", isOn: $names)
                    Text("Entwürfe und Aufgaben aus abgewählten Check-ins sind ausgeschlossen. Aufgaben und Ziele zeigen ihren heutigen Stand. Fotos und Aufnahmen werden nicht mitgesendet.").font(.caption).foregroundStyle(.secondary)
                }
                if checkIns {
                    Section("Einzelne Check-ins auswählen") {
                        let candidates = store.data.guidedCheckIns.filter { !$0.isDraft && $0.date >= options.start && $0.date < options.end }.sorted { $0.date > $1.date }
                        if candidates.isEmpty { Text("Noch keine abgeschlossenen Check-ins in diesem Zeitraum.").foregroundStyle(.secondary) }
                        ForEach(candidates) { entry in
                            Toggle(isOn: Binding(get: { !excluded.contains(entry.id) }, set: { if $0 { excluded.remove(entry.id) } else { excluded.insert(entry.id) } })) {
                                VStack(alignment: .leading) { Text(entry.kind.title); Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section {
                    Button("Vorschau ansehen", systemImage: "doc.text.magnifyingglass") { preview = true }
                    Text("Teilen öffnet erst in der Vorschau das iOS-Teilen-Menü. Es wird nichts automatisch an deine Therapeutin oder deinen Therapeuten gesendet.").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.borderless).navigationTitle("Für deinen Therapietermin").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
                .sheet(isPresented: $preview) { TherapyReportPreview(options: options) }
        }
    }
}
private struct TherapyReportPreview: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let options: TherapyReportOptions
    var body: some View {
        let text = TherapyReport.text(data: store.data, options: options)
        let entries = TherapyReport.checkIns(data: store.data, options: options)
        NavigationStack {
            TherapyScreen {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if options.includeCheckIns, entries.contains(where: { $0.batteryPercent != nil }) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Dein Akku im Verlauf", icon: "battery.75percent", subtitle: "Nur deine ausgewählten Angaben. Übersprungene Antworten bleiben leer.")
                                Chart(entries) { entry in
                                    if let value = entry.batteryPercent {
                                        LineMark(x: .value("Zeit", entry.date), y: .value("Akku", value)).foregroundStyle(.indigo)
                                        PointMark(x: .value("Zeit", entry.date), y: .value("Akku", value)).foregroundStyle(.indigo)
                                    }
                                }.chartYScale(domain: 0...100).frame(height: 180)
                                    .accessibilityLabel("Akku-Verlauf aus \(entries.compactMap(\.batteryPercent).count) Angaben")
                                if let mean = TherapyReport.meanBattery(entries) { Text("Durchschnitt \(Int(mean.rounded())) %").font(.headline) }
                            }
                        }
                    }
                    GlassCard { Text(text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }.buttonStyle(.borderless).navigationTitle("Deine Vorschau").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Zurück") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: text, subject: Text("Meine Therapieübersicht")) { Label("Teilen", systemImage: "square.and.arrow.up") } }
                }
        }
    }
}
