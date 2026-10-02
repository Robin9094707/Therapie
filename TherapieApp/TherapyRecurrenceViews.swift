import SwiftUI

struct TherapyRecurrenceSection: View {
    @EnvironmentObject private var store: AppStore
    let editRhythm: () -> Void
    let editExtra: (TherapyExtraAppointment) -> Void
    var body: some View {
        Section("Dein flexibler Rhythmus") {
            let rule = store.data.schedule.recurrence
            Text(rule.map { "Alle \($0.interval) \($0.unit.title.lowercased())" } ?? "Wöchentlich · bisheriger Plan")
            if let rule, rule.unit == .weeks { Text("\(1 + rule.additionalWeeklySlots.count) Termine in jeder aktiven Woche").font(.caption).foregroundStyle(.secondary) }
            Button("Rhythmus & weitere Wochentermine", systemImage: "repeat", action: editRhythm).accessibilityIdentifier("therapy.recurrence.edit")
            Button("Einzelnen Zusatztermin hinzufügen", systemImage: "calendar.badge.plus") { editExtra(TherapyExtraAppointment()) }.accessibilityIdentifier("therapy.extra.add")
            ForEach((store.data.schedule.extraAppointments ?? []).sorted { $0.date < $1.date }) { appointment in
                HStack {
                    Button { editExtra(appointment) } label: { VStack(alignment: .leading) { Text(appointment.title); Text(appointment.date.formatted(date: .abbreviated, time: .shortened)).font(.caption) } }.accessibilityIdentifier("therapy.extra.edit." + appointment.id.uuidString)
                    Spacer()
                    Button(role: .destructive) { store.data.schedule.extraAppointments?.removeAll { $0.id == appointment.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Zusatztermin entfernen")
                }
            }
        }
    }
}
struct TherapyRecurrenceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var rule: TherapyRecurrence
    @State private var initial: TherapyRecurrence?
    @State private var draftID: UUID
    init(rule: TherapyRecurrence, draftID: UUID? = nil) { _rule = State(initialValue: rule); _draftID = State(initialValue: draftID ?? UUID()) }
    var body: some View {
        TherapyEditorSheet(title: "Therapie-Rhythmus", dirty: initial != nil && rule != initial, draftID: draftID, saveDraft: { store.saveEditorDraft(rule, id: draftID, kind: "recurrence", title: "Therapie-Rhythmus") }, save: { store.data.schedule.recurrence = rule }) {
            Section("Ab jetzt planen") {
                Picker("Einheit", selection: $rule.unit) { ForEach(TherapyRecurrenceUnit.allCases) { Text($0.title).tag($0) } }
                Stepper("Alle \(rule.interval) \(rule.unit.title)", value: $rule.interval, in: 1...52)
                DatePicker(rule.unit == .months ? "Erster Therapietag / Monatstag" : "Erster Therapietag / aktive Woche", selection: $rule.anchor, displayedComponents: .date)
                Text("Der bisherige Wochentag und die Uhrzeit bleiben dein Haupttermin. Bei Tagen zählt das Intervall ab dem Startdatum. Bei Monaten zählt dessen Monatstag; kurze Monate verwenden ihren letzten Tag.").font(.caption).foregroundStyle(.secondary)
            }
            if rule.unit == .weeks {
                ForEach(rule.additionalWeeklySlots) { original in
                    let slot = identifiedEditorBinding($rule.additionalWeeklySlots, to: original)
                    Section("Weiterer Termin") {
                        Picker("Wochentag", selection: slot.weekday) { ForEach(1...7, id: \.self) { Text(TherapyDateHelper.weekdayName($0)).tag($0) } }
                        DatePicker("Uhrzeit", selection: Binding(get: { Calendar.current.date(bySettingHour: slot.wrappedValue.hour, minute: slot.wrappedValue.minute, second: 0, of: Date())! }, set: { date in
                            var changed = slot.wrappedValue; changed.hour = Calendar.current.component(.hour, from: date); changed.minute = Calendar.current.component(.minute, from: date); slot.wrappedValue = changed
                        }), displayedComponents: .hourAndMinute)
                        Button("Wochentermin entfernen", role: .destructive) { rule.additionalWeeklySlots.removeAll { $0.id == original.id } }
                    }
                }
                Button("Weiteren Wochentermin ergänzen", systemImage: "plus.circle") { rule.additionalWeeklySlots.append(TherapyWeeklySlot()) }.disabled(rule.additionalWeeklySlots.count >= 6)
            }
            Section {
                Text("Vorhandene Einträge und Absagen bleiben gespeichert. Kalender, Widgets und Erinnerungen verwenden denselben Plan.").font(.caption).foregroundStyle(.secondary)
                Button("Zum bisherigen Wochenrhythmus zurück", role: .destructive) { store.data.schedule.recurrence = nil; if store.lastSaveError == nil { dismiss() } }
            }
        }.onAppear { if initial == nil { initial = rule } }
    }
}
struct TherapyExtraAppointmentEditor: View {
    @EnvironmentObject private var store: AppStore
    @State var appointment: TherapyExtraAppointment
    @State private var initial: TherapyExtraAppointment?
    var body: some View {
        TherapyEditorSheet(title: "Zusatztermin", dirty: initial != nil && appointment != initial, canSave: !appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftID: appointment.id, saveDraft: { store.saveEditorDraft(appointment, id: appointment.id, kind: "appointment", title: appointment.title) }, save: {
            var values = store.data.schedule.extraAppointments ?? []; values.removeAll { $0.id == appointment.id }; values.append(appointment); store.data.schedule.extraAppointments = values
        }) {
            Section { TextField("Bezeichnung", text: $appointment.title); DatePicker("Datum & Beginn", selection: $appointment.date) }
            Section { Text("Dieser Termin ergänzt deinen Rhythmus. Er wird ebenfalls in Kalender, Widgets und Therapie-Erinnerungen berücksichtigt.").font(.caption).foregroundStyle(.secondary) }
        }.onAppear { if initial == nil { initial = appointment } }
    }
}
