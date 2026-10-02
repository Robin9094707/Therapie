import SwiftUI

struct TherapyAppointmentCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var manage = false
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Deine nächste Therapie", icon: "calendar.badge.clock")
                    if let next = TherapyDateHelper.nextOccurrence(schedule: store.data.schedule, after: context.date) {
                        Text(TherapyCountdown.label(until: next, from: context.date))
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color.accentColor)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("therapy.countdown")
                        Text(next.formatted(date: .complete, time: .shortened)).font(.headline)
                        if !store.data.profile.therapistName.isEmpty { Text("Mit " + store.data.profile.therapistName).foregroundStyle(.secondary) }
                        Label("\(store.data.schedule.durationMinutes) Minuten", systemImage: "clock").font(.subheadline)
                        if let location = store.data.schedule.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.subheadline) }
                        if let preparation = store.data.schedule.preparation, !preparation.isEmpty { Text(preparation).font(.subheadline).foregroundStyle(.secondary) }
                    } else { Text("Kein nächster Termin berechenbar. Prüfe deinen Therapieplan.").foregroundStyle(.secondary) }
                    if let vacation = TherapyDateHelper.vacation(schedule: store.data.schedule, at: context.date) {
                        Label("Therapiepause bis " + vacation.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted), systemImage: "sun.max.fill").font(.subheadline).foregroundStyle(.teal)
                    }
                    Button("Termine, Absagen & Urlaub", systemImage: "calendar.badge.gearshape") { manage = true }
                        .buttonStyle(.bordered).accessibilityIdentifier("therapy.manage")
                }
            }
        }.sheet(isPresented: $manage) { TherapyAppointmentsView() }
    }
}

struct TodayOverviewCard: View {
    @EnvironmentObject private var store: AppStore
    private var todayCheckIns: Int { store.data.guidedCheckIns.filter { !$0.isDraft && $0.date.isSameTherapyDay(as: Date()) }.count + store.data.moodCheckIns.filter { $0.date.isSameTherapyDay(as: Date()) }.count }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Alles im Blick", icon: "square.grid.2x2", subtitle: "Dein Alltag, deine Fortschritte und deine Erinnerungen.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    NavigationLink { InsightsHubView() } label: { tile("Check-ins heute", value: "\(todayCheckIns)", icon: "face.smiling") }
                    NavigationLink { TasksView() } label: { tile("Offene Aufgaben", value: "\(store.data.weeklyTasks.filter { !$0.completed }.count)", icon: "checklist") }
                    NavigationLink { RoutineHubView() } label: { tile("Deine Routinen", value: "\(store.data.routines.count)", icon: "repeat") }
                    NavigationLink { TherapyJournalView() } label: { tile("Therapietagebuch", value: "Gedanken & Rückblicke", icon: "book.closed") }
                    NavigationLink { LibraryView() } label: { tile("Notizen & Medien", value: "\(store.data.notes.count) · \(store.data.media.count)", icon: "photo.on.rectangle.angled") }
                }
                if let mood = store.data.moodCheckIns.sorted(by: { $0.date > $1.date }).first {
                    Label("Zuletzt: \(mood.face) \(mood.moodTitle) · Akku \(mood.battery)/5", systemImage: "battery.100percent").font(.subheadline).foregroundStyle(.secondary)
                }
                let drafts = store.data.guidedCheckIns.filter(\.isDraft)
                if let entry = drafts.sorted(by: { $0.date > $1.date }).first {
                    Button("\(drafts.count) Check-in-Entwürfe · weiterführen", systemImage: "pencil.circle") { store.pendingGuidedCheckIn = entry }.font(.subheadline)
                }
            }
        }
    }
    private func tile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor)
            Text(value).font(.system(.title2, design: .rounded, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private enum AppointmentDestination: Identifiable {
    case cancel(Date), vacation
    var id: String { switch self { case .cancel(let date): "cancel.\(date.timeIntervalSince1970)"; case .vacation: "vacation" } }
}
struct TherapyAppointmentsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var destination: AppointmentDestination?
    @State private var requesting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Therapieplan") {
                    Picker("Wochentag", selection: $store.data.schedule.weekday) { ForEach(1...7, id: \.self) { Text(TherapyDateHelper.weekdayName($0)).tag($0) } }
                    DatePicker("Beginn", selection: Binding(get: { Calendar.current.date(bySettingHour: store.data.schedule.hour, minute: store.data.schedule.minute, second: 0, of: Date()) ?? Date() }, set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        var snapshot = store.data; snapshot.schedule.hour = parts.hour ?? 15; snapshot.schedule.minute = parts.minute ?? 0; store.data = snapshot
                    }), displayedComponents: .hourAndMinute)
                    Stepper("Dauer: \(store.data.schedule.durationMinutes) Minuten", value: $store.data.schedule.durationMinutes, in: 5...240, step: 5)
                }
                TherapyRecurrenceSection()
                Section {
                    ForEach(TherapyDateHelper.occurrences(schedule: store.data.schedule, count: 8, includeExcluded: true), id: \.self) { date in appointment(date) }
                } header: { Text("Kommende Wochen") } footer: { Text("Neue Absagen betreffen den ausgewählten Termin. Dein Therapieplan bleibt erhalten.") }
                Section {
                    Button("Therapiepause / Urlaub anlegen", systemImage: "sun.max") { destination = .vacation }.accessibilityIdentifier("therapy.vacation.add")
                    ForEach((store.data.schedule.therapyVacations ?? []).filter { $0.endedAt == nil && $0.end > Date() }.sorted { $0.start < $1.start }) { vacation in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(vacation.start.formatted(date: .abbreviated, time: .omitted) + " – " + vacation.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted), systemImage: "sun.max.fill")
                            if !vacation.note.isEmpty { Text(vacation.note).font(.caption).foregroundStyle(.secondary) }
                            Button("Pause beenden / wieder einschalten", systemImage: "play.circle") {
                                var snapshot = store.data; TherapyScheduleActions.endVacation(vacation.id, schedule: &snapshot.schedule); store.data = snapshot
                            }.accessibilityIdentifier("therapy.vacation.end")
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Therapiepause") } footer: { Text("Während der gewählten Tage gibt es keine Therapietermine oder Therapie-Wecker. Deine Alltagsroutinen bleiben separat einstellbar.") }
                Section("Therapie-Wecker") {
                    Toggle("Echte Routine-Titel in AlarmKit anzeigen", isOn: Binding(get: { store.data.companionSettings.alarmShowsActualTitles ?? true }, set: { store.data.companionSettings.alarmShowsActualTitles = $0 }))
                    Text("Die Bezeichnung, zum Beispiel Tabletten, erscheint auch auf dem Sperrbildschirm. Neutrale Titel bleiben optional.").font(.caption).foregroundStyle(.secondary)
                    Toggle("AlarmKit vor der Therapie", isOn: Binding(get: { store.data.schedule.therapyAlarmsEnabled ?? !store.data.schedule.alarmIDs.isEmpty }, set: { store.data.schedule.therapyAlarmsEnabled = $0 }))
                    ForEach([0, 5, 15, 30, 60, 120, 1440], id: \.self) { offset in
                        Toggle(offset == 0 ? "Zum Beginn" : offset == 1440 ? "Am Tag davor" : "\(offset) Minuten vorher", isOn: Binding(get: { store.data.schedule.reminderOffsetsMinutes.contains(offset) }, set: { enabled in
                            var offsets = Set(store.data.schedule.reminderOffsetsMinutes); if enabled { offsets.insert(offset) } else { offsets.remove(offset) }; store.data.schedule.reminderOffsetsMinutes = offsets.sorted(by: >)
                        }))
                    }
                    Button(requesting ? "Aktualisiere …" : "Wecker freigeben & aktualisieren", systemImage: "alarm") {
                        requesting = true
                        Task { @MainActor in await RoutineAlarmCoordinator.shared.requestAccess(store); requesting = false }
                    }.disabled(requesting)
                    if !store.routineAlarmStatus.isEmpty { Text(store.routineAlarmStatus).font(.caption).foregroundStyle(.secondary) }
                    Text("Wecker werden beim Öffnen sowie nach Änderungen, Absagen und Wiederherstellen erneuert. Sie benötigen die separate AlarmKit-Freigabe.").font(.caption).foregroundStyle(.secondary)
                }
                if !store.therapyCalendarStatus.isEmpty { Section("iPhone-Kalender") { Text(store.therapyCalendarStatus).font(.caption) } }
                let history = (store.data.schedule.cancellations ?? []).sorted { $0.createdAt > $1.createdAt }
                if !history.isEmpty {
                    Section("Absagen & Wiederherstellungen") {
                        ForEach(history) { entry in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text(entry.restoredAt == nil ? entry.reason.title : "Wiederhergestellt").font(.caption).foregroundStyle(.secondary)
                                if !entry.note.isEmpty { Text(entry.note).font(.caption) }
                                if entry.restoredAt == nil && entry.date > Date() { restoreButton(entry) }
                            }
                        }
                    }
                }
            }.buttonStyle(.borderless).navigationTitle("Deine Therapietermine").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() }.accessibilityIdentifier("therapy.manage.close") } }
                .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
                .sheet(item: $destination) { route in switch route { case .cancel(let date): TherapyCancellationEditor(date: date); case .vacation: TherapyVacationEditor() } }
        }.accessibilityIdentifier("therapy.appointments")
    }
    @ViewBuilder private func appointment(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(date: .complete, time: .shortened)).font(.headline)
            if let entry = TherapyDateHelper.cancellation(schedule: store.data.schedule, on: date) {
                Label(entry.reason.title, systemImage: "calendar.badge.minus").font(.caption).foregroundStyle(.orange)
                restoreButton(entry)
            } else if TherapyDateHelper.vacation(schedule: store.data.schedule, at: date) != nil {
                Label("Therapiepause / Urlaub", systemImage: "sun.max.fill").font(.caption).foregroundStyle(.teal)
            } else {
                Text(TherapyCountdown.label(until: date)).font(.caption).foregroundStyle(.secondary)
                Button("Diesen Termin absagen", systemImage: "calendar.badge.minus") { destination = .cancel(date) }.accessibilityIdentifier("therapy.cancel")
            }
        }.padding(.vertical, 6)
    }
    private func restoreButton(_ entry: TherapyCancellation) -> some View {
        Button("Termin wiederherstellen", systemImage: "arrow.uturn.backward.circle") {
            var snapshot = store.data; TherapyScheduleActions.restore(entry.id, schedule: &snapshot.schedule); store.data = snapshot
        }.accessibilityIdentifier("therapy.restore")
    }
}
private struct TherapyCancellationEditor: View {
    @EnvironmentObject private var store: AppStore
    let date: Date
    @State private var reason: TherapyCancellationReason = .me
    @State private var note = ""
    var body: some View {
        TherapyEditorSheet(title: "Termin absagen", dirty: !note.isEmpty || reason != .me, save: {
            var snapshot = store.data; TherapyScheduleActions.cancel(TherapyCancellation(date: date, exactTime: true, reason: reason, note: note), schedule: &snapshot.schedule); store.data = snapshot
        }) {
            Section { Text(date.formatted(date: .complete, time: .shortened)); Picker("Grund", selection: $reason) { ForEach(TherapyCancellationReason.allCases) { Text($0.title).tag($0) } }; TherapyInputField(title: "Zusätzliche Information", prompt: "Optional", text: $note) }
            Section { Text("Die Absage wird gespeichert und der nächste stattfindende Termin angezeigt. Du kannst diesen Termin jederzeit wiederherstellen.").font(.footnote).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("therapy.cancel.editor")
    }
}
private struct TherapyVacationEditor: View {
    @EnvironmentObject private var store: AppStore
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var note = ""
    var body: some View {
        TherapyEditorSheet(title: "Therapiepause", dirty: true, canSave: Calendar.current.startOfDay(for: end) >= Calendar.current.startOfDay(for: start), save: {
            let first = Calendar.current.startOfDay(for: start)
            guard let afterLast = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) else { return }
            var snapshot = store.data; snapshot.schedule.therapyVacations = (snapshot.schedule.therapyVacations ?? []) + [TherapyVacation(start: first, end: afterLast, note: note)]; store.data = snapshot
        }) {
            Section("Ohne Therapie") { DatePicker("Ab", selection: $start, displayedComponents: .date); DatePicker("Bis einschließlich", selection: $end, in: Calendar.current.startOfDay(for: start)..., displayedComponents: .date); TherapyInputField(title: "Hinweis", prompt: "Optional, zum Beispiel Urlaub", text: $note) }
            Section { Text("Der letzte ausgewählte Tag ist eingeschlossen. Danach wird dein Therapieplan automatisch fortgesetzt. Du kannst die Pause auch vorzeitig beenden.").font(.footnote).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("therapy.vacation.editor")
    }
}
