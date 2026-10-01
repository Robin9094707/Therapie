import SwiftUI

struct RoutineHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showHistory = false
    @State private var draft: DailyRoutine?
    @State private var goal: TherapyGoal?
    @State private var historyRoutine: DailyRoutine?
    @State private var deleting: DailyRoutine?
    @State private var confirmDelete = false
    @State private var vacationEnd = Date().addingTimeInterval(7 * 86400)
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Dein Alltag, dein Rhythmus", icon: "sun.horizon.fill", subtitle: "Kleine Schritte. Flexible Zeiten. Bewusste Pausen.")
                        Menu {
                            Button("Eigene Routine") { draft = DailyRoutine() }
                            Button("Beispiel: Medikament") { draft = DailyRoutine(title: "", symbol: "pills.fill", pauseOnVacation: false, times: [RoutineTime(title: "Morgens"), RoutineTime(title: "Abends", hour: 20, minute: 30)], urgentAlarm: true) }
                            Button("Beispiel: Duschen") { draft = DailyRoutine(title: "Duschen", symbol: "shower.fill", times: [RoutineTime(weekdays: [2, 4, 6], hour: 19, minute: 0)]) }
                            Button("Beispiel: Frühstück vorbereiten") { draft = DailyRoutine(title: "Frühstück vorbereiten", symbol: "fork.knife", times: [RoutineTime(weekdays: [2, 3, 4, 5, 6], hour: 6, minute: 15)]) }
                        } label: { Label("Routine anlegen", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent)
                        Toggle("Urlaubsmodus", isOn: Binding(get: { store.data.companionSettings.vacationUntil.map { $0 > Date() } ?? false }, set: { store.data.companionSettings.vacationUntil = $0 ? vacationEnd : nil }))
                        if let date = store.data.companionSettings.vacationUntil, date > Date() {
                            DatePicker("Pause bis", selection: Binding(get: { date }, set: { vacationEnd = $0; store.data.companionSettings.vacationUntil = $0 }), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                        Text("Nur Routinen mit aktivierter Urlaubspause pausieren. Die Uhrzeiten und deine Ziele bleiben gespeichert.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Gesamten Routinenverlauf ansehen", systemImage: "clock.arrow.circlepath") { showHistory = true }.buttonStyle(.bordered)
                RoutinePermissionCard()
                SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
                    let due = RoutinePlanner.due(data: store.data, now: context.date)
                    if !due.isEmpty {
                        Text("Jetzt offen").font(.title3.bold())
                        ForEach(due) { occurrence in RoutineDueCard(occurrence: occurrence) }
                    }
                }
                ForEach(store.data.routines) { routine in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Label(routine.title, systemImage: routine.symbol).font(.headline); Spacer(); Toggle("Aktiv", isOn: Binding(get: { routine.enabled }, set: { enabled in var copy = routine; copy.enabled = enabled; store.saveRoutine(copy) })).labelsHidden().accessibilityLabel(routine.title + " aktiv") }
                            if !routine.details.isEmpty { Text(routine.details).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(routine.times) { time in
                                Text(timeDescription(time)).font(.caption).foregroundStyle(.secondary)
                            }
                            let done = store.data.routineCompletions.filter { $0.routineID == routine.id && $0.outcome == .done && $0.recordedAt >= Date().therapyWeekStart }.count
                            Text("\(done) bestätigte Schritte diese Woche").font(.caption.weight(.semibold))
                            if let paused = routine.pausedUntil, paused > Date() { Text("Pausiert bis " + paused.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.orange) }
                            ResponsiveButtonRow {
                                Button("Bearbeiten", systemImage: "pencil") { draft = routine }.buttonStyle(.bordered)
                                Button("Verlauf", systemImage: "clock.arrow.circlepath") { historyRoutine = routine }.buttonStyle(.bordered)
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = routine; confirmDelete = true }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Was du erreichen möchtest", icon: "scope", subtitle: "Deine Ziele dürfen wachsen und auch pausieren.")
                        Button("Ziel anlegen", systemImage: "plus.circle") { goal = TherapyGoal() }
                        ForEach(store.data.therapyGoals) { value in
                            Button { goal = value } label: {
                                VStack(alignment: .leading, spacing: 6) { Text(value.title).font(.headline); if !value.smallStep.isEmpty { Text(value.smallStep).font(.caption) }; ProgressView(value: Double(value.progress), total: 100); Text("\(value.progress) % · \(value.status.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.navigationTitle("Routinen & Ziele").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .sheet(isPresented: $showHistory) { RoutineHistoryView() }
            .sheet(item: $draft) { RoutineEditorView(routine: $0) }
            .sheet(item: $historyRoutine) { RoutineDetailView(routineID: $0.id) }
            .sheet(item: $goal) { GoalEditorView(goal: $0) }
            .alert("Routine löschen?", isPresented: $confirmDelete) { Button("Abbrechen", role: .cancel) {}; Button("Löschen", role: .destructive) { if let item = deleting { store.deleteRoutine(item.id) } } } message: { Text("Ihre Erinnerungen werden entfernt. Bestätigungen bleiben im Routinenverlauf und in deinen Sicherungen erhalten.") }
    }
    private func timeDescription(_ time: RoutineTime) -> String {
        let days = time.weekdays.count == 7 ? "Täglich" : time.weekdays.map(TherapyDateHelper.weekdayName).joined(separator: ", ")
        let clock = String(format: "%02d:%02d", time.hour, time.minute)
        let weekend = time.weekendHour.map { " · Wochenende " + String(format: "%02d:%02d", $0, time.weekendMinute ?? time.minute) } ?? ""
        return (time.title.isEmpty ? "" : time.title + " · ") + days + " · " + clock + weekend
    }
}
struct RoutinePermissionCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Erinnerungen", icon: "bell.badge")
                Button("Mitteilungen erlauben", systemImage: "bell") { Task { await TaskNotificationCoordinator.shared.requestAccess(store) } }.buttonStyle(.bordered)
                Button("Dringende Wecker erlauben", systemImage: "alarm") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store) } }.buttonStyle(.bordered)
                Text(store.routineReminderStatus.isEmpty ? "Erinnerungen werden beim Speichern geplant." : store.routineReminderStatus).font(.caption).foregroundStyle(.secondary)
                if !store.routineAlarmStatus.isEmpty { Text(store.routineAlarmStatus).font(.caption).foregroundStyle(.secondary) }
                Text("iOS hält einen begrenzten Erinnerungsvorrat. Öffne die App regelmäßig, um ihn zu erneuern. Ton und Zustellung hängen von deinen Freigaben und iPhone-Einstellungen ab. Ein Wecker-Stopp bestätigt keine Erledigung.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct RoutineDueCard: View {
    @EnvironmentObject private var store: AppStore
    let occurrence: RoutineOccurrence
    @State private var confirmDone = false
    @State private var showSkip = false
    @State private var reason = ""
    var body: some View {
        if let routine = store.data.routines.first(where: { $0.id == occurrence.routineID }) {
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(routine.title, systemImage: routine.symbol).font(.headline)
                    if let time = routine.times.first(where: { $0.id == occurrence.timeID }), !time.title.isEmpty {
                        Text(time.title).font(.subheadline.weight(.semibold))
                    }
                    Text("Fällig " + occurrence.due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if let snooze = store.data.routineSnoozes.first(where: { $0.id == occurrence.id }), snooze.until > Date() { Text("Verschoben bis " + snooze.until.formatted(date: .omitted, time: .shortened)).font(.caption) }
                    if !routine.details.isEmpty { Text(routine.details).font(.subheadline) }
                    if let goal = store.data.therapyGoals.first(where: { $0.id == routine.goalID }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(goal.title, systemImage: "scope").font(.subheadline.bold())
                            if !goal.smallStep.isEmpty { Text("Dein kleiner Schritt: " + goal.smallStep).font(.subheadline) }
                            if !goal.support.isEmpty { Text("Unterstützung: " + goal.support).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    ResponsiveButtonRow {
                        Button("Erledigt", systemImage: "checkmark.circle.fill") { confirmDone = true }.buttonStyle(.borderedProminent)
                        Button("1 Stunde später", systemImage: "clock") { store.snoozeRoutine(occurrence) }.buttonStyle(.bordered)
                    }
                    Button("Heute auslassen", systemImage: "forward.end") { showSkip = true }.font(.caption)
                }
            }.alert("Wirklich erledigt?", isPresented: $confirmDone) {
                Button("Noch nicht", role: .cancel) {}
                Button("Ja, erledigt") { store.resolveRoutine(occurrence, outcome: .done) }
            } message: { Text("Damit bestätigst du nur diesen fälligen Termin. Die nächste Wiederholung bleibt aktiv.") }
                .alert("Diesen Termin auslassen?", isPresented: $showSkip) {
                    TextField("Grund (optional)", text: $reason)
                    Button("Abbrechen", role: .cancel) {}
                    Button("Als ausgelassen speichern") { store.resolveRoutine(occurrence, outcome: .skipped, note: reason) }
                } message: { Text("Auslassen wird getrennt von Erledigt protokolliert. Bei Medikamenten gelten deine ärztlichen Anweisungen; die App gibt keine Einnahme- oder Dosierungsempfehlung.") }
        }
    }
}
struct RoutineDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let routineID: UUID
    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(alignment: .leading, spacing: 16) {
                    let due = RoutinePlanner.due(data: store.data).filter { $0.routineID == routineID }
                    ForEach(due) { RoutineDueCard(occurrence: $0) }
                    if due.isEmpty { GlassCard { Label("Aktuell kein offener Termin", systemImage: "checkmark.circle") } }
                    Text("Dein Verlauf").font(.title3.bold())
                    ForEach(store.data.routineCompletions.filter { $0.routineID == routineID }.sorted { $0.recordedAt > $1.recordedAt }) { log in
                        RoutineHistoryCard(log: log)
                    }
                }
            }.navigationTitle(store.data.routines.first(where: { $0.id == routineID })?.title ?? "Routine").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
