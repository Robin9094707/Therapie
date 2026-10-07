import SwiftUI
import MapKit
import UIKit

struct FeatureHubLinks: View {
    var body: some View {
        GlassCard {
            ViewThatFits(in: .horizontal) {
                HStack { methods; Spacer(); timeline; Spacer(); map }
                VStack(alignment: .leading, spacing: 12) { methods; timeline; map }
            }
        }
    }
    private var methods: some View { NavigationLink { MethodsHubView() } label: { Label("Meine Methoden", systemImage: "sparkles") } }
    private var timeline: some View { NavigationLink { TodoTimelineView() } label: { Label("To-do-Timeline", systemImage: "calendar.day.timeline.left") } }
    private var map: some View { NavigationLink { EntryMapView() } label: { Label("Meine Eintragskarte", systemImage: "map") } }
}
struct BuddySuggestionsCard: View {
    @ObservedObject var controller: AIBuddyController
    @EnvironmentObject private var store: AppStore
    @State private var active: UUID?
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Ein Impuls für dich", systemImage: "sparkles").font(.headline)
                if let suggestion = store.data.buddySuggestions.first {
                    Text(suggestion.reply.title).font(.subheadline.bold())
                    Text(suggestion.reply.journalText).font(.subheadline).textSelection(.enabled)
                    Text(suggestion.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) { HStack {
                        ForEach(suggestion.reply.quickReplies ?? []) { quick in Button(quick.title) { open(suggestion, question: quick.text) }.buttonStyle(.bordered) }
                    } }
                    Button("Im Chat weiterdenken", systemImage: "bubble.left.and.bubble.right") { open(suggestion, question: nil) }
                } else { Text("Ein kurzer Gedanke aus deinen letzten Einträgen. Höchstens einmal täglich automatisch beim Öffnen der App.").font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Button("Neu generieren", systemImage: "arrow.clockwise") { Task { await store.aiController.refreshSuggestion(force: true) } }.disabled(store.aiController.busy)
                    if store.aiController.busy { ProgressView().controlSize(.small) }
                }.font(.caption.bold())
                if let error = store.aiController.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.sheet(item: Binding(get: { active.map(BuddyChatRoute.init) }, set: { active = $0?.id })) { route in NavigationStack { AIBuddyChatContent(controller: store.aiController, inSession: false, conversationID: route.id) } }
    }
    private func open(_ suggestion: BuddySuggestion, question: String?) {
        var snapshot = store.data
        let id = AIConversationMutation.create(in: &snapshot)
        snapshot.aiMessages.append(AIBuddyMessage(role: "assistant", text: suggestion.reply.journalText, reply: suggestion.reply, conversationID: id))
        if let index = snapshot.aiConversations.firstIndex(where: { $0.id == id }) { snapshot.aiConversations[index].title = suggestion.reply.title; snapshot.aiConversations[index].draftText = question }
        store.data = snapshot
        if store.lastSaveError == nil { active = id }
    }
}
private struct BuddyChatRoute: Identifiable { var id: UUID }

struct TodoTimelineView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind = "Alle"
    @State private var horizon = "7 Tage"
    @State private var onlyOpen = true
    @State private var search = ""
    @State private var limit = 50
    @State private var editing: ArchiveRecord?
    @State private var routine: RoutineOccurrence?
    @State private var confirmRoutine = false
    private var scoped: [TodoTimelineItem] {
        let now = Date(), calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: horizon == "Heute" ? 1 : 7, to: calendar.startOfDay(for: now)) ?? now
        return TodoTimeline.items(store.data).filter { horizon == "Alle" || $0.date < end }
    }
    private var items: [TodoTimelineItem] { scoped.filter { (kind == "Alle" || $0.kind == kind) && (!onlyOpen || !$0.completed) && (search.isEmpty || ($0.title + " " + $0.detail).localizedStandardContains(search)) } }
    private var groups: [(date: Date, values: [TodoTimelineItem])] {
        let values = Dictionary(grouping: Array(items.prefix(limit))) { Calendar.current.startOfDay(for: $0.date) }
        return values.keys.sorted().map { ($0, values[$0] ?? []) }
    }
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Was noch offen ist", icon: "checklist", subtitle: "Aufgaben und Alltag nach Kategorie. Ältere offene Aufgaben bleiben sichtbar.")
                Picker("Zeitraum", selection: $horizon) { ForEach(["Heute", "7 Tage", "Alle"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(["Aufgaben", "Tabletten", "Duschen", "Routinen", "Therapie", "Check-ins", "Ziele"], id: \.self) { category in
                        let open = scoped.filter { $0.kind == category && !$0.completed }.count
                        Button { kind = kind == category ? "Alle" : category } label: {
                            VStack(alignment: .leading, spacing: 5) { Text(category).font(.subheadline.bold()); Text(open == 0 ? "Nichts offen" : "\(open) noch offen").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.accentColor.opacity(kind == category ? 0.2 : 0.07), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityAddTraits(kind == category ? .isSelected : [])
                    }
                }
                if kind != "Alle" { Button("Alle Kategorien anzeigen") { kind = "Alle" }.font(.caption) }
                Toggle("Nur offen", isOn: $onlyOpen)
                Text("\(items.count) passende Punkte · \(scoped.filter { !$0.completed }.count) insgesamt offen. Ziele und Check-ins öffnen ihren Editor; bestätigte und ausgelassene Termine sind getrennt beschriftet.").font(.caption).foregroundStyle(.secondary)
                if items.isEmpty { ContentUnavailableView("Hier ist alles frei", systemImage: "checkmark.seal") }
                ForEach(groups, id: \.date) { group in
                    Text(group.date.formatted(date: .complete, time: .omitted)).font(.headline).padding(.top, 8)
                    ForEach(group.values) { item in row(item) }
                }
                if items.count > limit { Button("Weitere 50 Punkte laden") { limit += 50 }.buttonStyle(.bordered) }
            }
        }.navigationTitle("Meine Aufgaben").searchable(text: $search, prompt: "Aufgabe oder Thema suchen")
            .onChange(of: kind) { _, _ in limit = 50 }.onChange(of: search) { _, _ in limit = 50 }
            .sheet(item: $editing) { ArchiveRecordEditor(record: $0) }
            .alert("Routine wirklich erledigt?", isPresented: $confirmRoutine) {
                Button("Abbrechen", role: .cancel) {}
                Button("Erledigt") { if let routine { store.resolveRoutine(routine, outcome: .done) }; routine = nil }
            }
    }
    private func row(_ item: TodoTimelineItem) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Button { toggle(item) } label: { Image(systemName: item.completed ? "checkmark.circle.fill" : item.goalID != nil || item.checkInSlotID != nil ? "arrow.up.right.circle" : "circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel(item.completed ? "Wieder öffnen" : "Als erledigt markieren").disabled(item.occurrence != nil && (item.completed || item.date > Date()))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.kind).font(.caption2.bold()).foregroundStyle(Color.accentColor)
                    Text(item.title).font(.headline).lineLimit(4).strikethrough(item.completed)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Label(item.date.formatted(date: .abbreviated, time: .shortened), systemImage: item.kind == "Therapie" ? "text.bubble" : "clock").font(.caption).foregroundStyle(item.date < Date() && !item.completed ? Color.orange : Color.secondary)
                    if let id = item.taskID { Button("Bearbeiten") { if let task = store.data.weeklyTasks.first(where: { $0.id == id }) { editing = .task(task) } }.font(.caption) }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func toggle(_ item: TodoTimelineItem) {
        if let id = item.goalID, let goal = store.data.therapyGoals.first(where: { $0.id == id }) { editing = .goal(goal) }
        else if let id = item.checkInSlotID, let slot = DayCheckInPolicy.slots(store.data.companionSettings).first(where: { $0.id == id }) { store.openDailyCheckIn(slot.kind, slotID: slot.id) }
        else if let id = item.taskID { store.toggleTask(id) }
        else if let id = item.discussionID { if item.completed { store.data.therapyDiscussionAcknowledgedIDs.removeAll { $0 == id } } else { store.data.therapyDiscussionAcknowledgedIDs.append(id) } }
        else if let value = item.occurrence { routine = value; confirmRoutine = true }
    }
}
struct WeeklyTasksHomeCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: WeeklyTask?
    private var tasks: [WeeklyTask] { let week = Date().therapyWeek; return store.data.weeklyTasks.filter { $0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year }.sorted { if $0.completed != $1.completed { return !$0.completed }; return $0.createdAt < $1.createdAt } }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Deine Wochenaufgaben", icon: "checklist", subtitle: "KW \(Date().therapyWeek.week) · \(tasks.filter(\.completed).count)/\(tasks.count) erledigt")
                ForEach(tasks.prefix(6)) { task in HStack {
                    Button { store.toggleTask(task.id) } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel(task.completed ? "Aufgabe wieder öffnen" : "Aufgabe erledigen")
                    Button { editing = task } label: { VStack(alignment: .leading) { Text(task.title).strikethrough(task.completed); if let due = task.dueDate { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                    Spacer()
                } }
                if tasks.isEmpty { Text("Noch keine Aufgabe für diese Woche.").font(.subheadline).foregroundStyle(.secondary) }
                NavigationLink { TodoTimelineView() } label: { Label("Alle Kategorien & offene Schritte", systemImage: "checklist") }
                NavigationLink { TasksView() } label: { Label("Aufgaben hinzufügen / bearbeiten", systemImage: "plus.circle") }
            }
        }.sheet(item: $editing) { WeeklyTaskEditorView(task: $0) }
    }
}
private struct LocatedEntry: Identifiable {
    var id: String
    var title: String
    var date: Date
    var location: EntryLocation
    var record: ArchiveRecord?
}
struct EntryMapView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days = 30
    @State private var search = ""
    @State private var limit = 100
    @State private var editing: ArchiveRecord?
    @State private var selected: String?
    private var entries: [LocatedEntry] {
        let records = Dictionary(ArchiveRecord.all(in: store.data).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let messages = Dictionary(store.data.aiMessages.filter { $0.role == "user" }.map { ("chat-" + $0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return store.data.entryLocations.filter(\.valid).compactMap { location in
            let record = records[location.id], message = messages[location.id]
            guard let date = record?.date ?? message?.date else { return nil }
            let title = record?.title ?? String(message?.text.prefix(80) ?? "Eintrag")
            guard (days == 0 || date >= start), search.isEmpty || title.localizedStandardContains(search) else { return nil }
            return LocatedEntry(id: location.id, title: title, date: date, location: location, record: record)
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Neue Einträge mit aktuellem Standort", isOn: Binding(get: { store.data.captureEntryLocation != false }, set: { store.data.captureEntryLocation = $0 }))
                Text("Nur nach deiner iPhone-Standortfreigabe, beim Erstellen eines Eintrags. Keine dauerhafte Ortung. Alte Einträge bekommen keinen nachträglichen Standort. Genauigkeit hängt vom iPhone ab.").font(.caption).foregroundStyle(.secondary)
                Link("iPhone-Standortfreigabe prüfen", destination: URL(string: UIApplication.openSettingsURLString)!).font(.caption)
                Picker("Zeitraum", selection: $days) { Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("Alle").tag(0) }.pickerStyle(.segmented)
                Map(selection: $selected) {
                    ForEach(Array(entries.prefix(limit))) { entry in
                        Marker(entry.title, coordinate: CLLocationCoordinate2D(latitude: entry.location.latitude, longitude: entry.location.longitude)).tag(entry.id)
                    }
                }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 20))
                Text("\(min(limit, entries.count)) von \(entries.count) Einträgen auf der Karte").font(.caption).foregroundStyle(.secondary)
                if entries.isEmpty { ContentUnavailableView("Noch keine Standorte", systemImage: "map", description: Text("Neue Einträge erscheinen hier nach deiner Standortfreigabe.")) }
                if let entry = entries.first(where: { $0.id == selected }) { row(entry) }
                LazyVStack { ForEach(Array(entries.prefix(limit))) { row($0) } }
                if entries.count > limit { Button("Weitere 100 Einträge anzeigen") { limit += 100 }.buttonStyle(.bordered) }
            }
        }.navigationTitle("Meine Eintragskarte").searchable(text: $search, prompt: "Einträge suchen")
            .onChange(of: days) { _, _ in limit = 100 }.onChange(of: search) { _, _ in limit = 100 }
            .sheet(item: $editing) { ArchiveRecordEditor(record: $0) }
    }
    private func row(_ entry: LocatedEntry) -> some View {
        Button { if let record = entry.record { editing = record }; selected = entry.id } label: {
            HStack { Image(systemName: "mappin.circle"); VStack(alignment: .leading) { Text(entry.title).lineLimit(2); Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " · ±\(Int(entry.location.accuracy)) m").font(.caption).foregroundStyle(.secondary) }; Spacer() }
        }.buttonStyle(.plain).padding(10)
    }
}
