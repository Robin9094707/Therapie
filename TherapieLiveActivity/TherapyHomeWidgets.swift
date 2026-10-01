import SwiftUI
import WidgetKit

struct TherapyHomeEntry: TimelineEntry {
    var date: Date
    var snapshot: TherapyWidgetSnapshot
}
struct TherapyHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> TherapyHomeEntry { TherapyHomeEntry(date: .now, snapshot: .init()) }
    func getSnapshot(in context: Context, completion: @escaping (TherapyHomeEntry) -> Void) {
        completion(TherapyHomeEntry(date: .now, snapshot: context.isPreview ? preview() : read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TherapyHomeEntry>) -> Void) {
        let snapshot = read(), now = Date(), end = now.addingTimeInterval(24 * 3600)
        var dates = [now]
        dates += snapshot.nextAppointments.filter { $0 > now && $0 < end }.flatMap { [$0, $0.addingTimeInterval(1)] }
        dates += snapshot.reminders.flatMap { [$0.due, $0.expiresAt] }.filter { $0 > now && $0 < end }
        dates += snapshot.session?.phases.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < end } ?? []
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) { dates.append(midnight) }
        let entries = Set(dates).sorted().prefix(120).map { TherapyHomeEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
    private func read() -> TherapyWidgetSnapshot {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TherapyWidgetSnapshot.appGroup),
              let raw = try? Data(contentsOf: container.appendingPathComponent(TherapyWidgetSnapshot.fileName)) else { return .init() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(TherapyWidgetSnapshot.self, from: raw)) ?? .init()
    }
    private func preview() -> TherapyWidgetSnapshot {
        let now = Date()
        return TherapyWidgetSnapshot(generatedAt: now, nextAppointments: [now.addingTimeInterval(7200)], reminders: [TherapyWidgetReminder(id: "example", kind: "routine", title: "Deine Routine", due: now.addingTimeInterval(-300), expiresAt: now.addingTimeInterval(86400), route: "therapie://today")], configured: true)
    }
}

enum TherapyHomeWidgetKind: String {
    case overview, appointment, routines, reminders, session
    var title: String {
        switch self { case .overview: "Heute im Blick"; case .appointment: "Nächste Therapie"; case .routines: "Meine Routinen"; case .reminders: "Meine Erinnerungen"; case .session: "Meine Therapiestunde" }
    }
    var symbol: String {
        switch self { case .overview: "sun.max.fill"; case .appointment: "calendar.badge.clock"; case .routines: "checkmark.circle.fill"; case .reminders: "bell.fill"; case .session: "timer" }
    }
    var route: String {
        switch self { case .appointment: "therapie://appointments"; case .routines: "therapie://routines"; case .reminders: "therapie://reminders"; case .session: "therapie://session"; case .overview: "therapie://today" }
    }
}
struct TherapyOverviewWidget: Widget {
    var body: some WidgetConfiguration { TherapyHomeWidgetConfiguration.make(.overview) }
}
struct TherapyAppointmentWidget: Widget {
    var body: some WidgetConfiguration { TherapyHomeWidgetConfiguration.make(.appointment) }
}
struct TherapyRoutinesWidget: Widget {
    var body: some WidgetConfiguration { TherapyHomeWidgetConfiguration.make(.routines) }
}
struct TherapyRemindersWidget: Widget {
    var body: some WidgetConfiguration { TherapyHomeWidgetConfiguration.make(.reminders) }
}
struct TherapySessionWidget: Widget {
    var body: some WidgetConfiguration { TherapyHomeWidgetConfiguration.make(.session) }
}
enum TherapyHomeWidgetConfiguration {
    static func make(_ category: TherapyHomeWidgetKind) -> some WidgetConfiguration {
        StaticConfiguration(kind: "TherapyHome." + category.rawValue, provider: TherapyHomeProvider()) { entry in
            TherapyHomeWidgetView(entry: entry, category: category)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.indigo.opacity(0.14), Color(uiColor: .systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName(category.title)
        .description(description(for: category))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
    private static func description(for category: TherapyHomeWidgetKind) -> String {
        switch category {
        case .overview: "Therapietermin und fällige Routinen auf einen Blick."
        case .appointment: "Dein nächster Termin, mit Absagen und Urlaubspausen."
        case .routines: "Fällige und kommende Routinen. Tippen öffnet die Bestätigung in der App."
        case .reminders: "Offene Aufgaben und ihre nächsten Erinnerungen."
        case .session: "Verbleibende Therapiezeit und aktueller Abschnitt."
        }
    }
}
struct TherapyHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TherapyHomeEntry
    let category: TherapyHomeWidgetKind
    private var compact: Bool { family == .accessoryRectangular }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            Label(category.title, systemImage: category.symbol).font(compact ? .caption.bold() : .subheadline.bold()).foregroundStyle(.indigo).lineLimit(1)
            if !entry.snapshot.configured {
                Text("App einmal öffnen").font(.headline)
                if !compact { Text("Danach erscheinen deine aktuellen Angaben.").font(.caption).foregroundStyle(.secondary) }
            } else {
                switch category {
                case .appointment: appointment
                case .overview:
                    appointment
                    if !compact { Text("\(entry.snapshot.dueRoutines(at: entry.date).count) Routinen fällig").font(.caption.bold()) }
                case .routines: reminders(kind: "routine")
                case .reminders: reminders(kind: "task")
                case .session: session
                }
            }
            if !compact { Spacer(minLength: 0); Text("Therapie · Für dich").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: category.route))
        .privacySensitive()
    }
    @ViewBuilder private var appointment: some View {
        if let date = entry.snapshot.appointment(after: entry.date) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated)).font(compact ? .caption : .headline).lineLimit(2)
            Text(date, style: .time).font(compact ? .caption.monospacedDigit() : .title2.monospacedDigit().bold())
        } else { Text("Termin in der App prüfen").font(.caption).foregroundStyle(.secondary) }
    }
    @ViewBuilder private func reminders(kind: String) -> some View {
        let values = entry.snapshot.openReminders(at: entry.date, kind: kind)
        let due = values.filter { $0.due <= entry.date }
        Text(due.isEmpty ? "Alles im Blick" : "\(due.count) noch offen").font(compact ? .caption.bold() : .title3.bold())
        if let first = due.first ?? values.first {
            if compact { Text(first.title).font(.caption).lineLimit(1) }
            else {
                Link(destination: URL(string: first.route)!) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(first.title).font(.subheadline.bold()).lineLimit(2)
                        Text(first.due, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if family == .systemMedium {
                    ForEach(Array(values.dropFirst().prefix(2))) { value in
                        Link(destination: URL(string: value.route)!) { Text(value.title).font(.caption).lineLimit(1) }
                    }
                }
            }
        } else { Text(kind == "routine" ? "Keine Routinen geplant" : "Keine offenen Erinnerungen").font(.caption).foregroundStyle(.secondary) }
    }
    @ViewBuilder private var session: some View {
        if let session = entry.snapshot.session, session.paused || session.end > entry.date {
            if session.paused {
                Text("Pause · \(Int(ceil(session.pausedRemaining / 60))) Min. übrig").font(compact ? .caption.bold() : .headline)
            } else {
                Text(timerInterval: entry.date...max(entry.date, session.end), countsDown: true).font(compact ? .headline.monospacedDigit() : .title.monospacedDigit().bold())
                if let phase = session.phase(at: entry.date) { Text(phase.title).font(.caption).lineLimit(2) }
            }
        } else { Text("Keine Stunde aktiv").font(.headline); if !compact { Text("Therapiezeit in der App starten.").font(.caption).foregroundStyle(.secondary) } }
    }
}
