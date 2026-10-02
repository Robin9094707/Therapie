import SwiftUI

struct TherapyEditableTimeline: View {
    @EnvironmentObject private var store: AppStore
    var searchText: String
    @State private var editing: ArchiveRecord?
    @State private var deleting: ArchiveRecord?
    @State private var confirmDelete = false
    @State private var kind: ArchiveKind = .all
    @State private var showCalendar = false
    @State private var selectedDay = Date()
    @State private var filterDay = false
    @State private var useRange = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd = Date()
    @State private var topicID: UUID?
    @State private var folderID: UUID?
    @State private var onlyPinned = false
    private var records: [ArchiveRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ArchiveRecord.all(in: store.data).filter { record in
            (kind == .all || record.kind == kind) &&
            (topicID == nil || record.topicID == topicID) &&
            (folderID == nil || record.folderID == folderID) &&
            (!onlyPinned || store.data.dashboard.pinnedRecordIDs.contains(record.id)) &&
            ArchiveDateFilter.includes(record.date, day: filterDay ? selectedDay : nil, from: useRange ? rangeStart : nil, through: useRange ? rangeEnd : nil) &&
            (query.isEmpty || (record.title + " " + record.subtitle + " " + record.date.formatted(date: .numeric, time: .omitted)).localizedStandardContains(query))
        }.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return store.data.archivePreferences.oldestFirst ? $0.date < $1.date : $0.date > $1.date
        }
    }
    private var groups: [(date: Date, values: [ArchiveRecord])] {
        let grouped = Dictionary(grouping: records) { store.data.archivePreferences.grouping.start(of: $0.date) }
        return grouped.keys.sorted { store.data.archivePreferences.oldestFirst ? $0 < $1 : $0 > $1 }.map { ($0, grouped[$0] ?? []) }
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            filterControls
            Text("\(records.count) Einträge · \(groups.count) \(store.data.archivePreferences.grouping.rawValue)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if records.isEmpty {
                GlassCard { ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease", description: Text("Wähle einen anderen Tag oder setze deine Filter zurück.")) }
            }
            ForEach(groups, id: \.date) { group in
                Section {
                    ForEach(group.values) { record in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 4) {
                                Circle().fill(.indigo).frame(width: 8, height: 8)
                                Rectangle().fill(.indigo.opacity(0.15)).frame(width: 2, height: 80)
                            }.padding(.top, 20).accessibilityHidden(true)
                            ArchiveTimelineCard(record: record, open: { editing = record }, delete: {
                                deleting = record; confirmDelete = true
                            })
                        }
                    }
                } header: {
                    HStack {
                        Text(store.data.archivePreferences.grouping.title(for: group.date)).font(.headline)
                        Spacer()
                        Text("\(group.values.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            }
        }
        .sheet(item: $editing) { ArchiveRecordEditor(record: $0) }
        .alert("Eintrag löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { if let deleting { remove(deleting) }; deleting = nil }
        } message: { Text(deleting?.deletionMessage ?? "") }
    }
    private var filterControls: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Deine Zeitreise", icon: "calendar.day.timeline.left", subtitle: "Nach Datum, Inhalt und Thema entdecken.")
                ViewThatFits(in: .horizontal) {
                    HStack { groupingPicker; kindPicker }
                    VStack(alignment: .leading) { groupingPicker; kindPicker }
                }
                HStack {
                    Button(showCalendar ? "Kalender schließen" : "Kalender öffnen", systemImage: "calendar") { showCalendar.toggle() }
                    Spacer()
                    Menu {
                        Toggle("Älteste zuerst", isOn: $store.data.archivePreferences.oldestFirst)
                        Toggle("Nur angepinnte Einträge", isOn: $onlyPinned)
                        Toggle("Zeitraum eingrenzen", isOn: $useRange)
                        Picker("Thema", selection: $topicID) {
                            Text("Alle Themen").tag(Optional<UUID>.none)
                            ForEach(store.data.therapyTopics) { Text($0.title).tag(Optional($0.id)) }
                        }
                        Picker("Ordner", selection: $folderID) {
                            Text("Alle Ordner").tag(Optional<UUID>.none)
                            ForEach(store.data.therapyFolders) { Text($0.title).tag(Optional($0.id)) }
                        }
                        Button("Filter zurücksetzen") { kind = .all; filterDay = false; useRange = false; topicID = nil; folderID = nil; onlyPinned = false }
                    } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
                }.font(.subheadline)
                if showCalendar {
                    DatePicker("Archivtag", selection: $selectedDay, displayedComponents: .date).datePickerStyle(.graphical)
                        .onChange(of: selectedDay) { _, _ in filterDay = true }
                    Toggle("Nur ausgewählten Tag anzeigen", isOn: $filterDay)
                    Text("\(ArchiveRecord.all(in: store.data).filter { $0.date.isSameTherapyDay(as: selectedDay) }.count) Einträge an diesem Tag").font(.caption).foregroundStyle(.secondary)
                }
                if filterDay && !showCalendar {
                    Button { filterDay = false } label: { Label(selectedDay.formatted(date: .abbreviated, time: .omitted) + " · Alle Tage anzeigen", systemImage: "xmark.circle") }.font(.caption)
                }
                if useRange {
                    DatePicker("Von", selection: $rangeStart, in: ...rangeEnd, displayedComponents: .date)
                    DatePicker("Bis einschließlich", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                }
                if let id = topicID, let topic = store.data.therapyTopics.first(where: { $0.id == id }) { Text("Thema: " + topic.title).font(.caption) }
                if let id = folderID, let folder = store.data.therapyFolders.first(where: { $0.id == id }) { Text("Ordner: " + folder.title).font(.caption) }
            }
        }
    }
    private var groupingPicker: some View {
        Picker("Gruppierung", selection: $store.data.archivePreferences.grouping) { ForEach(ArchiveGrouping.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
    }
    private var kindPicker: some View {
        Picker("Inhalt", selection: $kind) { ForEach(ArchiveKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
    }
    private func remove(_ record: ArchiveRecord) {
        var snapshot = store.data
        snapshot.dashboard.pinnedRecordIDs.removeAll { $0 == record.id }
        switch record {
        case .routineLog: return
        case .note(let value): snapshot.notes.removeAll { $0.id == value.id }
        case .media(let value): store.deleteMedia(value); return
        case .energy(let value): snapshot.energyEntries.removeAll { $0.id == value.id }
        case .reflection(let value): snapshot.reflections.removeAll { $0.id == value.id }
        case .mood(let value): store.deleteCheckIn(value); return
        case .point(let value): store.deleteBatteryPoint(value.id); return
        case .review(let value): snapshot.weekReviews.removeAll { $0.id == value.id }
        case .weeklyEnergy(let value): snapshot.weeklyEnergyReviews.removeAll { $0.id == value.id }
        case .guided(let value): store.deleteGuided(value.id); return
        case .session(let value):
            snapshot.sessionHistory.removeAll { $0.id == value.id }
            for i in snapshot.notes.indices where snapshot.notes[i].sessionID == value.id { snapshot.notes[i].sessionID = nil }
        case .task(let value): snapshot.weeklyTasks.removeAll { $0.id == value.id }
        case .topic(let value): TherapyHierarchy.removeTopic(value.id, data: &snapshot)
        case .goal(let value):
            snapshot.therapyGoals.removeAll { $0.id == value.id }
            for i in snapshot.weeklyTasks.indices where snapshot.weeklyTasks[i].goalID == value.id { snapshot.weeklyTasks[i].goalID = nil }
            for i in snapshot.routines.indices where snapshot.routines[i].goalID == value.id { snapshot.routines[i].goalID = nil }
        }
        store.data = snapshot
    }
}

struct ArchiveRecordEditor: View {
    @EnvironmentObject private var store: AppStore
    let record: ArchiveRecord
    @ViewBuilder var body: some View {
        switch record {
        case .note(let value): TherapyNoteDetailView(noteID: value.id)
        case .media(let value): TherapyMediaDetailView(itemID: value.id)
        case .energy(let value): LegacyEnergyEditorView(entry: value)
        case .reflection(let value): TherapyReflectionEditorView(entry: value)
        case .mood(let value): MoodCheckInDetailView(entryID: value.id)
        case .point(let value): BatteryPointEditorView(point: value) { store.saveBatteryPoint($0); return store.lastSaveError == nil }
        case .review(let value): WeekReviewEditorView(review: value)
        case .session(let value): SessionHistoryEditorView(session: value)
        case .task(let value): WeeklyTaskEditorView(task: value)
        case .topic(let value): TopicEditorView(topic: value)
        case .goal(let value): GoalEditorView(goal: value)
        case .weeklyEnergy(let value): WeeklyEnergyEditorView(review: value)
        case .guided(let value): GuidedCheckInDestination(entry: value)
        case .routineLog(let value): RoutineLogDestination(log: value)
        }
    }
 }

struct RoutineLogDestination: View {
    @Environment(\.dismiss) private var dismiss
    let log: RoutineCompletion
    var body: some View {
        NavigationStack {
            TherapyScreen { RoutineHistoryCard(log: log, showTitle: true) }
                .navigationTitle("Routinenprotokoll")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
struct ArchiveTimelineCard: View {
    @EnvironmentObject private var store: AppStore
    let record: ArchiveRecord
    var open: () -> Void
    var delete: (() -> Void)? = nil
    private var pinned: Bool { store.data.dashboard.pinnedRecordIDs.contains(record.id) }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: record.symbol).font(.title3).foregroundStyle(.indigo).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: open) { Text(record.title).font(.headline).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                        Text(record.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        var preferences = store.data.dashboard
                        if pinned { preferences.pinnedRecordIDs.removeAll { $0 == record.id } } else { preferences.pinnedRecordIDs.append(record.id) }
                        store.data.dashboard = preferences
                    } label: { Image(systemName: pinned ? "pin.fill" : "pin").frame(width: 32, height: 44) }
                        .accessibilityLabel(pinned ? "Von Heute lösen" : "Auf Heute anpinnen")
                }
                HashtagChips(tags: AppHashtags.tags(record))
                HStack {
                    Button("Übersicht öffnen", systemImage: "arrow.up.right.square", action: open)
                    Spacer()
                    if record.canDelete, let delete { Button(role: .destructive, action: delete) { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Eintrag löschen") }
                }.font(.caption.bold())
            }
        }
    }
}
