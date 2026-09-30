import SwiftUI

struct WeekdaySelection: View {
    @Binding var days: [Int]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                Button {
                    if days.contains(day) { days.removeAll { $0 == day } } else { days.append(day); days.sort() }
                    TherapyEffects.shared.light()
                } label: {
                    Text(String(TherapyDateHelper.weekdayName(day).prefix(2))).font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(days.contains(day) ? Color.indigo.opacity(0.2) : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel(TherapyDateHelper.weekdayName(day)).accessibilityAddTraits(days.contains(day) ? .isSelected : [])
            }
        }
    }
}

struct ReminderCenterView: View {
    @EnvironmentObject private var store: AppStore
    private var time: Binding<Date> {
        Binding { Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: store.data.schedule.taskReminderHour, minute: store.data.schedule.taskReminderMinute)) ?? Date() } set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            var data = store.data; data.schedule.taskReminderHour = parts.hour ?? 18; data.schedule.taskReminderMinute = parts.minute ?? 0; store.data = data
        }
    }
    var body: some View {
        Form {
            Section("Aufgaben ohne eigene Einstellung") {
                Toggle("Regelmäßig an offene Aufgaben erinnern", isOn: $store.data.schedule.taskReminderEnabled)
                if store.data.schedule.taskReminderEnabled {
                    DatePicker("Uhrzeit", selection: time, displayedComponents: .hourAndMinute)
                    WeekdaySelection(days: $store.data.schedule.taskReminderWeekdays)
                    Text("Eine neu angelegte Aufgabe erhält eine eigene tägliche Erinnerung, die du beim Anlegen anpassen kannst. Die Einstellungen hier gelten für ältere Aufgaben ohne eigene Erinnerung.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Privatsphäre & Ton") {
                Toggle("Aufgabentitel auf Sperrbildschirm verbergen", isOn: $store.data.reminderPreferences.privateTaskTitles)
                Toggle("Aufgaben mit Ton erinnern", isOn: $store.data.reminderPreferences.taskSound)
            }
            Section("Energie am Therapietag") {
                Toggle("Wochenenergie vor der Therapie eintragen", isOn: $store.data.reminderPreferences.energyReviewEnabled)
                if store.data.reminderPreferences.energyReviewEnabled {
                    Stepper("\(store.data.reminderPreferences.energyReviewMinutesBeforeTherapy) Minuten vorher", value: $store.data.reminderPreferences.energyReviewMinutesBeforeTherapy, in: 0...1440, step: 15)
                    Text("Folgt deinem Therapietag und deiner Uhrzeit. Der Hinweis öffnet den Wochen-Energierückblick.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Status") {
                Button("Mitteilungen freigeben & aktualisieren", systemImage: "bell.badge") { Task { await TaskNotificationCoordinator.shared.requestAccess(store) } }
                Text(store.taskReminderStatus).font(.footnote).foregroundStyle(.secondary)
                Text("Offene Aufgaben werden wiederholt erinnert, auch wenn die App geschlossen ist. Erledigen oder Löschen beendet ihre Erinnerungen. Für Aufgaben einer zukünftigen Woche öffne die App zu Beginn der Woche, damit sie aktiviert werden.").font(.caption).foregroundStyle(.secondary)
                Text("Verschieben passt die regelmäßige Uhrzeit und gegebenenfalls einen Erinnerungstag an. Du kannst beides jederzeit in der Aufgabe bearbeiten.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Therapie-Alarme") {
                Text("Therapietermine verwenden AlarmKit. Aktualisiere sie über Kalender → Mit iPhone synchronisieren. Aufgabenerinnerungen verwenden Mitteilungen mit Aktionen für Erledigen, Verschieben und Weiterarbeiten.").font(.footnote)
                NavigationLink { TherapyCalendarView() } label: { Label("Therapie-Alarme & Kalender", systemImage: "alarm") }
            }
        }.navigationTitle("Erinnerungen")
    }
}
