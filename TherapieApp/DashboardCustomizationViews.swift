import SwiftUI

struct DashboardCustomizationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardPreferences
    @State private var reset = false
    init(preferences: DashboardPreferences) { _draft = State(initialValue: preferences) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ziehe die Karten in deine Reihenfolge. Blende Karten aus oder pinne sie ganz oben an. Deine Auswahl wird mit allen Backups gesichert.").font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Kompakte Kartenabstände", isOn: $draft.compactCards)
                }
                Section("Deine Heute-Karten") {
                    ForEach(draft.orderedCards) { card in
                        HStack(spacing: 12) {
                            Image(systemName: card.symbol).foregroundStyle(.indigo).frame(width: 24)
                            Text(card.title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                toggle(card.rawValue, in: &draft.pinnedCards)
                            } label: { Image(systemName: draft.pinnedCards.contains(card.rawValue) ? "pin.fill" : "pin").frame(width: 36, height: 44) }.buttonStyle(.borderless).accessibilityLabel(card.title + " anpinnen")
                            Toggle("\(card.title) anzeigen", isOn: Binding(get: { !draft.hiddenCards.contains(card.rawValue) }, set: { visible in
                                draft.hiddenCards.removeAll { $0 == card.rawValue }; if !visible { draft.hiddenCards.append(card.rawValue) }
                            })).labelsHidden()
                        }
                    }.onMove { from, to in
                        var order = draft.orderedCards.map(\.rawValue); order.move(fromOffsets: from, toOffset: to); draft.cardOrder = order
                    }
                }
                Section("Widgets") {
                    Toggle("Titel in Widgets anzeigen", isOn: $draft.showWidgetTitles)
                    Text("Standardmäßig zeigen Widgets nur neutrale Bezeichnungen, Uhrzeiten und Anzahlen. Notiztexte und Check-in-Antworten werden niemals geteilt.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Standardlayout wiederherstellen", role: .destructive) { reset = true }
                }
            }
            .navigationTitle("Heute gestalten").navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                    store.data.dashboard = draft
                    if store.lastSaveError == nil { dismiss() }
                }.bold() }
            }
            .alert("Standardlayout verwenden?", isPresented: $reset) {
                Button("Abbrechen", role: .cancel) {}
                Button("Zurücksetzen") { let records = draft.pinnedRecordIDs; draft = DashboardPreferences(); draft.pinnedRecordIDs = records }
            } message: { Text("Angepinnte Archiveinträge bleiben erhalten.") }
        }
    }
    private func toggle(_ value: String, in values: inout [String]) {
        if values.contains(value) { values.removeAll { $0 == value } } else { values.append(value) }
    }
}

struct TodayRoutinesCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirming: RoutineOccurrence?
    @State private var showConfirmation = false
    @State private var detailID: UUID?
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            let due = RoutinePlanner.due(data: store.data, now: context.date)
            GlassCard(emphasized: !due.isEmpty) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Deine Routinen heute", icon: "checkmark.circle", subtitle: due.isEmpty ? "Aktuell ist nichts fällig." : "\(due.count) fällig · ein kleiner Schritt nach dem anderen")
                    if due.isEmpty {
                        let upcoming = RoutinePlanner.occurrences(store.data.routines, settings: store.data.companionSettings, now: context.date, days: 1).filter { $0.due > context.date && Calendar.current.isDate($0.due, inSameDayAs: context.date) && !RoutinePlanner.resolved($0, completions: store.data.routineCompletions) }
                        if let next = upcoming.first, let routine = store.data.routines.first(where: { $0.id == next.routineID }) {
                            Text("Als Nächstes: \(routine.title) · \(next.due.formatted(date: .omitted, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("Du hast gerade Zeit für dich.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    ForEach(due) { occurrence in
                        if let routine = store.data.routines.first(where: { $0.id == occurrence.routineID }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Button { detailID = routine.id } label: { Label(routine.title, systemImage: routine.symbol).font(.headline).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                                Text("Fällig seit " + occurrence.due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                if let snooze = store.data.routineSnoozes.first(where: { $0.id == occurrence.id && $0.until > context.date }) { Text("Erinnerung verschoben bis " + snooze.until.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                                Button("Als erledigt bestätigen", systemImage: "checkmark.circle.fill") { confirming = occurrence; showConfirmation = true }.buttonStyle(.bordered).accessibilityIdentifier("today.routine.complete")
                            }
                            if occurrence.id != due.last?.id { Divider() }
                        }
                    }
                    NavigationLink { RoutineHubView() } label: { Label("Alle Routinen", systemImage: "arrow.right.circle") }.font(.subheadline)
                }
            }
        }
        .alert("Routine wirklich erledigt?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) { confirming = nil }
            Button("Ja, ich habe sie erledigt") {
                if let occurrence = confirming { store.resolveRoutine(occurrence, outcome: .done) }
                confirming = nil
            }
        } message: {
            Text("Bestätige nur, wenn du „\(store.data.routines.first { $0.id == confirming?.routineID }?.title ?? "diese Routine")“ wirklich abgeschlossen hast.")
        }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) { if let detailID { RoutineDetailView(routineID: detailID) } }
    }
}

struct PinnedArchiveCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var opened: ArchiveRecord?
    private var records: [ArchiveRecord] {
        let byID = Dictionary(uniqueKeysWithValues: ArchiveRecord.all(in: store.data).map { ($0.id, $0) })
        return store.data.dashboard.pinnedRecordIDs.compactMap { byID[$0] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Angepinnt für dich", icon: "pin.fill")
            if records.isEmpty { GlassCard { Text("Tippe im Archiv auf die Stecknadel, um wichtige Einträge hier wiederzufinden.").font(.subheadline).foregroundStyle(.secondary) } }
            ForEach(records) { record in ArchiveTimelineCard(record: record, open: { opened = record }) }
        }.sheet(item: $opened) { ArchiveRecordEditor(record: $0) }
    }
}

struct TodaySessionCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let session = store.data.currentSession {
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: session.pausedAt == nil ? "Deine Therapie läuft" : "Therapie pausiert", icon: "timer")
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let index = session.phaseIndex(at: context.date) { Text(session.phases[index].title).font(.headline) }
                        Text("Noch \(Int(ceil(session.remaining(at: context.date) / 60))) Minuten insgesamt").font(.subheadline).foregroundStyle(.secondary)
                    }
                    NavigationLink { SessionConductorView() } label: { Label("Stunde öffnen", systemImage: "arrow.up.right.square") }
                }
            }
        }
    }
}

struct TodayRemindersCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var task: WeeklyTask?
    private var tasks: [WeeklyTask] {
        store.data.weeklyTasks.filter {
            !$0.completed && TaskReminderPlanner.slots(tasks: [$0], schedule: store.data.schedule).count > 0
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Offene Aufgaben & Erinnerungen", icon: "bell.badge", subtitle: "\(tasks.count) offene Aufgaben mit Erinnerungen")
                ForEach(tasks.prefix(5)) { item in
                    Button { task = item } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.bold())
                            if let due = item.dueDate { Text("Fällig " + due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(due < Date() ? .orange : .secondary) }
                        }
                    }.buttonStyle(.plain)
                }
                if tasks.isEmpty { Text("Keine offenen Aufgabenerinnerungen.").font(.subheadline).foregroundStyle(.secondary) }
                NavigationLink { ReminderCenterView() } label: { Label("Erinnerungen verwalten", systemImage: "slider.horizontal.3") }.font(.subheadline)
            }
        }.sheet(item: $task) { WeeklyTaskEditorView(task: $0) }
    }
}
struct TodayGoalsCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var goal: TherapyGoal?
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Meine Ziele", icon: "scope")
                if store.data.therapyGoals.isEmpty { Text("Lege deine persönlichen Ziele im Therapie-Bereich an.").foregroundStyle(.secondary) }
                ForEach(store.data.therapyGoals.prefix(3)) { item in
                    Button { goal = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.subheadline.bold())
                            ProgressView(value: Double(max(0, min(100, item.progress))), total: 100)
                            if !item.smallStep.isEmpty { Text(item.smallStep).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.sheet(item: $goal) { GoalEditorView(goal: $0) }
    }
}


struct HomeAndWidgetSettingsCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var customize = false
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Heute & iPhone-Widgets", icon: "square.grid.2x2")
                Button("Heute-Seite gestalten", systemImage: "slider.horizontal.3") { customize = true }.buttonStyle(.bordered)
                Toggle("Titel in Widgets anzeigen", isOn: $store.data.dashboard.showWidgetTitles)
                Text("Halte den iPhone-Home-Bildschirm gedrückt und wähle Bearbeiten → Widget hinzufügen → Therapie. Du findest Übersichten für Termine, Routinen, Erinnerungen und deine laufende Stunde.").font(.subheadline).foregroundStyle(.secondary)
                Text("Widget gedrückt halten → Widget bearbeiten: Datenquelle und Titel-Filter wählen. Ohne gemeinsamen Datenzugriff lässt sich ein manueller Termin einstellen; er ist klar als manuell gekennzeichnet.").font(.caption).foregroundStyle(.secondary)
                Text(store.widgetStatus).font(.caption).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $customize) { DashboardCustomizationView(preferences: store.data.dashboard) }
    }
}

struct WidgetSetupHelpView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Widget") {
                    Text(store.widgetStatus)
                    Button("App-Daten jetzt aktualisieren", systemImage: "arrow.clockwise") { TherapyWidgetBridge.refresh(store, force: true) }
                    Toggle("Titel in Widgets anzeigen", isOn: $store.data.dashboard.showWidgetTitles)
                }
                Section("Am iPhone einstellen") {
                    Text("Halte das Widget gedrückt und wähle Widget bearbeiten. Aktuelle App-Daten zeigen Termine, fällige Routinen, offene Erinnerungen und den laufenden Timer. Du kannst Routinen/Erinnerungen nach einem Titel filtern.")
                    Text("Falls die Installation keinen gemeinsamen App-Gruppen-Zugriff erlaubt: Manuell eingestellter Termin / Hinweis wählen, Datum oder wöchentlichen Wochentag und Uhrzeit festlegen. Das Widget kennzeichnet diese Angaben als manuell und verändert deine App-Daten nicht.")
                }
                Section("Gemeinsame Daten") {
                    Text("Automatische Live-Daten brauchen beim Signieren dieselbe App-Gruppe group.eu.rjuhas.therapie in App und Erweiterung. Eine Widget-Einstellung kann eine entfernte iOS-Berechtigung nicht ersetzen. Nach einer passenden Installation App öffnen und das Widget gegebenenfalls neu hinzufügen.").font(.caption)
                }
            }.navigationTitle("Widget einrichten").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .onAppear { TherapyWidgetBridge.refresh(store, force: true) }
        }
    }
}
