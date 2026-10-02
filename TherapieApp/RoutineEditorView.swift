import SwiftUI

struct RoutineEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var routine: DailyRoutine
    @State private var error: String?
    @State private var initial: DailyRoutine?
    @State private var confirmExit = false
    private let symbols = ["checkmark.circle", "pills.fill", "shower.fill", "fork.knife", "drop.fill", "figure.walk", "bed.double.fill", "book.fill", "heart.fill", "sun.max.fill", "briefcase.fill", "leaf.fill"]
    private let symbolTitles = ["Allgemein", "Medikament", "Duschen", "Essen", "Trinken", "Bewegung", "Schlafen", "Lesen", "Wohlbefinden", "Morgen", "Arbeit", "Pause"]
    private var valid: Bool { !routine.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !routine.times.isEmpty && routine.times.allSatisfy { !$0.weekdays.isEmpty } && (routine.endsAt == nil || routine.endsAt! >= (routine.recurrenceAnchor ?? routine.createdAt)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Deine Routine") {
                    TextField("Name, z. B. Morgenroutine", text: $routine.title)
                    Picker("Symbol", selection: $routine.symbol) { ForEach(Array(symbols.enumerated()), id: \.element) { index, value in Label(symbolTitles[index], systemImage: value).tag(value) } }.pickerStyle(.menu)
                    TextField("Eigene Hinweise / Vorbereitung", text: $routine.details, axis: .vertical).lineLimit(2...6)
                    Toggle("Aktiv", isOn: $routine.enabled)
                    Toggle("Im Urlaubsmodus pausieren", isOn: $routine.pauseOnVacation)
                    Toggle("Bis zu einem Datum pausieren", isOn: Binding(get: { routine.pausedUntil != nil }, set: { routine.pausedUntil = $0 ? Date().addingTimeInterval(86400) : nil }))
                    if routine.pausedUntil != nil { DatePicker("Pause bis", selection: Binding(get: { routine.pausedUntil ?? Date() }, set: { routine.pausedUntil = $0 }), in: Date()...) }
                    Picker("Verknüpftes Ziel", selection: $routine.goalID) { Text("Kein Ziel").tag(UUID?.none); ForEach(store.data.therapyGoals) { Text($0.title).tag(Optional($0.id)) } }
                }
                Section("Wann möchtest du erinnert werden?") {
                    ForEach(routine.times) { value in
                        let time = identifiedEditorBinding($routine.times, to: value)
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Name dieses Termins (optional)", text: time.title)
                            DatePicker("Uhrzeit", selection: clockBinding(hour: time.hour, minute: time.minute), displayedComponents: .hourAndMinute)
                            weekdayPicker(days: time.weekdays)
                            Toggle("Andere Wochenendzeit", isOn: Binding(get: { time.wrappedValue.weekendHour != nil }, set: { enabled in time.wrappedValue.weekendHour = enabled ? time.wrappedValue.hour : nil; time.wrappedValue.weekendMinute = enabled ? time.wrappedValue.minute : nil }))
                            if time.wrappedValue.weekendHour != nil {
                                DatePicker("Samstag & Sonntag", selection: clockBinding(hour: Binding(get: { time.wrappedValue.weekendHour ?? time.wrappedValue.hour }, set: { time.wrappedValue.weekendHour = $0 }), minute: Binding(get: { time.wrappedValue.weekendMinute ?? time.wrappedValue.minute }, set: { time.wrappedValue.weekendMinute = $0 })), displayedComponents: .hourAndMinute)
                            }
                            if routine.times.count > 1 { Button("Uhrzeit entfernen", role: .destructive) { routine.times.removeAll { $0.id == value.id } } }
                        }.padding(.vertical, 8)
                    }
                    Button("Weitere Uhrzeit", systemImage: "plus.circle") { routine.times.append(RoutineTime(hour: 20, minute: 30)) }
                }
                Section("Erinnern, bis du bestätigst") {
                    Toggle("Mitteilungen", isOn: $routine.remindersEnabled)
                    Stepper("Erneut nach \(routine.retryMinutes) Minuten", value: $routine.retryMinutes, in: 5...180, step: 5)
                    Toggle("Abends häufiger erinnern", isOn: Binding(get: { routine.escalationHour != nil }, set: { routine.escalationHour = $0 ? 23 : nil }))
                    if routine.escalationHour != nil {
                        Stepper("Häufiger ab \(routine.escalationHour ?? 23) Uhr", value: Binding(get: { routine.escalationHour ?? 23 }, set: { routine.escalationHour = $0 }), in: 0...23)
                        Stepper("Dann alle \(routine.escalationMinutes) Minuten", value: $routine.escalationMinutes, in: 5...60, step: 5)
                    }
                    Toggle("Nachtruhe für diese Routine", isOn: Binding(get: { routine.quietStartHour != nil }, set: { routine.quietStartHour = $0 ? 23 : nil }))
                    if routine.quietStartHour != nil {
                        Stepper("Ruhe ab \(routine.quietStartHour ?? 23) Uhr", value: Binding(get: { routine.quietStartHour ?? 23 }, set: { routine.quietStartHour = $0 }), in: 0...23)
                        Stepper("Ruhe bis \(routine.quietEndHour) Uhr", value: $routine.quietEndHour, in: 0...23)
                    }
                    Toggle("Zusätzlich dringender AlarmKit-Wecker", isOn: $routine.urgentAlarm)
                    Text("Nach Erledigt oder Auslassen enden die Erinnerungen für diesen Termin. Verschieben gilt einmalig für eine Stunde. Ein unbestätigter Termin bleibt maximal bis zur gleichen Uhrzeit am Folgetag offen; danach beginnt ein neuer Termin. Die App protokolliert nichts automatisch als erledigt.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privatsphäre & Check-ins") {
                    Toggle("Routinentitel auf dem Sperrbildschirm verbergen", isOn: $store.data.companionSettings.privateRoutineTitles)
                    Toggle("Check-in nach Therapie-Timer anbieten", isOn: $store.data.companionSettings.offerTherapyCheckIn)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section("Wiederholung & Zeitraum") {
                    Stepper("Alle \(routine.repeatEveryWeeks ?? 1) Wochen", value: Binding(get: { routine.repeatEveryWeeks ?? 1 }, set: { routine.repeatEveryWeeks = $0; if routine.recurrenceAnchor == nil { routine.recurrenceAnchor = Date() } }), in: 1...52)
                    if routine.recurrenceAnchor != nil { DatePicker("Start", selection: Binding(get: { routine.recurrenceAnchor ?? Date() }, set: { routine.recurrenceAnchor = $0 })) }
                    Toggle("Enddatum", isOn: Binding(get: { routine.endsAt != nil }, set: { routine.endsAt = $0 ? Date().addingTimeInterval(28 * 86400) : nil }))
                    if routine.endsAt != nil { DatePicker("Letzter Termin bis", selection: Binding(get: { routine.endsAt ?? Date() }, set: { routine.endsAt = $0 })) }
                }
            }.buttonStyle(.borderless).navigationTitle("Routine gestalten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if initial != nil && routine != initial { confirmExit = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { store.saveRoutine(routine); if store.lastSaveError == nil { store.removeEditorDraft(routine.id); if store.lastSaveError == nil { dismiss() } } else { error = store.lastSaveError } }.disabled(!valid) }
                }
        }.onAppear { if initial == nil { initial = routine } }
            .interactiveDismissDisabled(initial != nil && routine != initial)
            .alert("Eingaben behalten?", isPresented: $confirmExit) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Als Entwurf speichern") { store.saveEditorDraft(routine, id: routine.id, kind: "routine", title: routine.title); if store.lastSaveError == nil { dismiss() } }
                Button("Verwerfen", role: .destructive) { store.removeEditorDraft(routine.id); if store.lastSaveError == nil { dismiss() } }
            }
    }
    private func weekdayPicker(days: Binding<[Int]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wochentage").font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Button {
                        if days.wrappedValue.contains(day) { days.wrappedValue.removeAll { $0 == day } } else { days.wrappedValue.append(day) }
                    } label: { Text(String(TherapyDateHelper.weekdayName(day).prefix(2))).frame(maxWidth: .infinity).padding(10).background(days.wrappedValue.contains(day) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: Capsule()) }.buttonStyle(.plain).accessibilityLabel(TherapyDateHelper.weekdayName(day)).accessibilityAddTraits(days.wrappedValue.contains(day) ? .isSelected : [])
                }
            }
        }
    }
    private func clockBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date() }, set: { date in let parts = Calendar.current.dateComponents([.hour, .minute], from: date); hour.wrappedValue = parts.hour ?? 6; minute.wrappedValue = parts.minute ?? 30 })
    }
}
