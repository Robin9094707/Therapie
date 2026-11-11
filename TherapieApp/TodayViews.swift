import SwiftUI
import MapKit

// MARK: - Kompass 7: calm Today page
//
// One short page: greeting, what comes next (therapy, BeWo, start the round), this week's tasks with an inline
// add field, today's routines, quick capture. Everything else is one tap away ("Mehr" menu, search tab) or can be
// added below via "Heute anpassen".

/// Small greeting line instead of a big card.
struct TodayGreetingHeader: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(PersonalGreeting.title(at: context.date, name: store.data.profile.userName))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if !store.data.dashboard.welcomeMessage.isEmpty {
                    Text(store.data.dashboard.welcomeMessage).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Next therapy and next BeWo appointment in one calm card, plus starting the therapy round.
struct TodayNextUpCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let therapy = TherapyDateHelper.nextOccurrence(schedule: store.data.schedule, after: context.date.addingTimeInterval(-Double(max(0, store.data.schedule.durationMinutes)) * 60))
            let bewo = AssistedLivingPlanner.next(store.data, now: context.date)
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    TodaySectionTitle(title: "Als Nächstes", icon: "calendar")
                        .padding(.bottom, 6)
                    NextUpRow(icon: "leaf.fill", tint: .green, title: "Therapie", date: therapy, now: context.date,
                              detail: store.data.profile.therapistName, empty: "Kein Termin geplant") { store.notificationTherapy = true }
                    Divider().padding(.leading, 48)
                    NextUpRow(icon: bewo?.kind.symbol ?? "house.fill", tint: .brown, title: bewo.map { $0.title.isEmpty ? "Betreutes Wohnen" : $0.title } ?? "Betreutes Wohnen",
                              date: bewo?.date, now: context.date, detail: store.data.assistedLivingSettings.caregiverName, empty: "Kein BeWo-Termin geplant") { store.openAssistedLiving() }
                    if store.data.currentSession == nil {
                        Button { store.notificationSession = true } label: {
                            Label("Therapiestunde starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .padding(.top, 10)
                        .accessibilityIdentifier("today.startSession")
                    }
                }
            }
        }
    }
}

private struct NextUpRow: View {
    let icon: String
    let tint: Color
    let title: String
    let date: Date?
    let now: Date
    let detail: String
    let empty: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TherapyIconTile(icon: icon, size: 36, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let date {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()) + (detail.isEmpty ? "" : " · " + detail))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(empty).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                if let date {
                    Text(AssistedLivingPlanner.countdown(to: date, now: now))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// This week's tasks: tick off, open, and add a new one without leaving Today.
struct WeeklyTasksQuickCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var newTitle = ""
    @State private var editing: WeeklyTask?
    @State private var showAll = false
    @FocusState private var focused: Bool

    private var tasks: [WeeklyTask] {
        let week = Date().therapyWeek
        return store.data.weeklyTasks
            .filter { $0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year }
            .sorted { $0.completed != $1.completed ? !$0.completed : $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let list = tasks
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TodaySectionTitle(title: "Wochenaufgaben", icon: "checklist")
                    Spacer()
                    if !list.isEmpty {
                        Text("\(list.filter(\.completed).count)/\(list.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                ForEach(list.prefix(showAll ? list.count : 5)) { task in
                    HStack(spacing: 10) {
                        Button { withAnimation(.snappy) { store.toggleTask(task.id) } } label: {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.completed ? Color.green : Color.secondary)
                                .frame(width: 36, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.completed ? "„\(task.title)“ wieder öffnen" : "„\(task.title)“ erledigen")
                        Button { editing = task } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).font(.subheadline).strikethrough(task.completed).foregroundStyle(task.completed ? Color.secondary : Color.primary)
                                    .multilineTextAlignment(.leading)
                                if let due = task.dueDate {
                                    Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if list.count > 5 {
                    Button(showAll ? "Weniger anzeigen" : "Alle \(list.count) anzeigen") { withAnimation(.snappy) { showAll.toggle() } }
                        .font(.footnote.weight(.semibold))
                        .padding(.leading, 46)
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color.accentColor).frame(width: 36)
                    TextField("Neue Aufgabe für diese Woche", text: $newTitle)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("today.newTask")
                    if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Hinzufügen", action: add).font(.subheadline.weight(.semibold)).buttonStyle(.glassProminent)
                    }
                }
                .padding(.top, 4)
                NavigationLink { TasksView() } label: {
                    Label("Aufgaben verwalten", systemImage: "slider.horizontal.3").font(.footnote.weight(.semibold))
                }
                .padding(.top, 6)
            }
        }
        .sheet(item: $editing) { WeeklyTaskEditorView(task: $0) }
    }

    private func add() {
        let title = String(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !title.isEmpty else { return }
        let week = Date().therapyWeek
        withAnimation(.snappy) {
            store.data.weeklyTasks.insert(WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: title, details: ""), at: 0)
        }
        if store.lastSaveError == nil { newTitle = ""; TherapyEffects.shared.light() }
    }
}

/// Plain section title used by the calm cards.
struct TodaySectionTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title).font(.system(.headline, design: .rounded))
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Where an entry was made

/// A small "where" chip for history entries that have a stored location. Tapping shows the place on a map.
struct EntryLocationBadge: View {
    @EnvironmentObject private var store: AppStore
    let recordID: String
    @State private var showMap = false

    var body: some View {
        if let location = store.data.entryLocations.first(where: { $0.id == recordID && $0.valid }) {
            Button { showMap = true } label: {
                Label("Ort", systemImage: "mappin.and.ellipse")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ort dieses Eintrags auf der Karte zeigen")
            .sheet(isPresented: $showMap) { EntryLocationSheet(location: location).presentationDetents([.medium, .large]) }
        }
    }
}

struct EntryLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let location: EntryLocation
    @State private var placeName = ""

    private var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: max(400, location.accuracy * 6), longitudinalMeters: max(400, location.accuracy * 6)))) {
                    Marker(placeName.isEmpty ? "Eintrag" : placeName, coordinate: coordinate)
                    MapCircle(center: coordinate, radius: max(10, location.accuracy)).foregroundStyle(Color.accentColor.opacity(0.15))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    if !placeName.isEmpty { Text(placeName).font(.headline) }
                    Text(location.capturedAt.formatted(date: .abbreviated, time: .shortened) + " · Genauigkeit ±\(Int(location.accuracy)) m")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = placeName.isEmpty ? "Kompass-Eintrag" : placeName
                    item.openInMaps()
                } label: { Label("In Karten öffnen", systemImage: "map").frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
            }
            .padding(16)
            .navigationTitle("Hier festgehalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .task {
                // Only the place name is looked up, on demand; nothing is stored.
                if let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: location.latitude, longitude: location.longitude)).first {
                    placeName = [mark.name, mark.locality].compactMap { $0 }.removingDuplicates().joined(separator: ", ")
                }
            }
        }
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] { var seen = Set<String>(); return filter { seen.insert($0).inserted } }
}
