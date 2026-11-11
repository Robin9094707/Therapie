import SwiftUI
import AlarmKit
import UserNotifications

// MARK: - Mitteilungen & Wecker (Kompass 6)
//
// One native place for every current and future reminder: rest for a while (and end it early), silence single
// areas or single reminders, quiet hours, and the live state of iOS notifications and AlarmKit alarms.

extension ReminderCategory {
    var tint: Color {
        switch self {
        case .tasks: .orange
        case .routines: .green
        case .checkIns: .yellow
        case .therapy: .indigo
        case .session: .teal
        case .wake: .red
        case .wellbeing: .pink
        case .assistedLiving: .brown
        }
    }
}

enum QuietDuration: String, CaseIterable, Identifiable {
    case halfHour, oneHour, threeHours, untilMorning, oneDay, threeDays, oneWeek, open
    var id: String { rawValue }
    var title: String {
        switch self {
        case .halfHour: "30 Minuten"
        case .oneHour: "1 Stunde"
        case .threeHours: "3 Stunden"
        case .untilMorning: "Bis morgen früh"
        case .oneDay: "24 Stunden"
        case .threeDays: "3 Tage"
        case .oneWeek: "1 Woche"
        case .open: "Bis ich sie beende"
        }
    }
    var short: String {
        switch self {
        case .halfHour: "30 Min."
        case .oneHour: "1 Std."
        case .threeHours: "3 Std."
        case .untilMorning: "Bis 8 Uhr"
        case .oneDay: "24 Std."
        case .threeDays: "3 Tage"
        case .oneWeek: "1 Woche"
        case .open: "Offen"
        }
    }
    var symbol: String {
        switch self {
        case .halfHour, .oneHour, .threeHours: "clock.fill"
        case .untilMorning: "sunrise.fill"
        case .oneDay: "moon.zzz.fill"
        case .threeDays, .oneWeek: "calendar"
        case .open: "infinity"
        }
    }
    func end(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .halfHour: return now.addingTimeInterval(1800)
        case .oneHour: return now.addingTimeInterval(3600)
        case .threeHours: return now.addingTimeInterval(3 * 3600)
        case .untilMorning:
            let today = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
            return today > now.addingTimeInterval(1800) ? today : calendar.date(byAdding: .day, value: 1, to: today)
        case .oneDay: return now.addingTimeInterval(86400)
        case .threeDays: return calendar.date(byAdding: .day, value: 3, to: now)
        case .oneWeek: return calendar.date(byAdding: .day, value: 7, to: now)
        case .open: return nil
        }
    }
}

@MainActor
final class ReminderSystemState: ObservableObject {
    @Published var pendingNotifications = 0
    @Published var scheduledAlarms = 0
    @Published var notificationsAllowed: Bool?
    @Published var alarmsAllowed: Bool?

    func load() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsAllowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        pendingNotifications = await center.pendingNotificationRequests().count
        alarmsAllowed = AlarmManager.shared.authorizationState == .authorized
        scheduledAlarms = (try? AlarmManager.shared.alarms.count) ?? 0
    }
}

private struct ReminderDay: Identifiable {
    let id: Date
    let items: [PlannedReminder]
}

struct QuietCenterView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var system = ReminderSystemState()
    @State private var filter = 0
    @State private var composer = false
    @State private var editing: QuietSourceRoute?
    @State private var showAllUpcoming = false
    @State private var sheetPage: QuietSheetPage?

    enum QuietSheetPage: String, Identifiable { case checkIns, therapy; var id: String { rawValue } }

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            let items = ReminderInventory.upcoming(store.data, now: context.date, days: 7)
            TherapyScreen {
                VStack(spacing: 20) {
                    QuietHeroCard(now: context.date) { composer = true }
                    AIAskButton(title: "Mit KI klären, was ruhen soll", question: "Mich nerven gerade Wecker oder Erinnerungen. Schau dir an, was heute noch kommt, frag mich kurz, was mich stört, und schlage passende Ruhe-Varianten als Aktionen vor.", icon: "sparkles", prominent: false)
                    categoryCard(now: context.date)
                    upcomingCard(items, now: context.date)
                    if !store.data.quietMode.silenced.isEmpty { silencedCard(now: context.date) }
                    quietHoursCard
                    systemCard
                    sourcesCard
                    historyCard(now: context.date)
                }
            }
        }
        .navigationTitle("Mitteilungen & Wecker")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $composer) { QuietComposerView() }
        .sheet(item: $editing) { route in QuietSourceDestination(route: route) }
        .sheet(item: $sheetPage) { page in
            switch page {
            case .checkIns: DayCheckInSettingsView(slots: DayCheckInPolicy.slots(store.data.companionSettings))
            case .therapy: TherapyAppointmentsView()
            }
        }
        .task { await system.load() }
        .refreshable { await replan() }
    }

    private func replan() async {
        TaskNotificationCoordinator.shared.refresh(store)
        try? await Task.sleep(for: .milliseconds(900))
        await system.load()
    }

    // MARK: Areas

    private func categoryCard(now: Date) -> some View {
        TherapySettingsSection(title: "Bereiche", footer: "Tippe auf einen Bereich, um ihn für eine Weile ruhen zu lassen oder dauerhaft stummzuschalten.") {
            ForEach(ReminderCategory.allCases) { category in
                Menu {
                    let muted = store.data.quietMode.mutedCategories.contains(category)
                    if let pause = QuietPolicy.activePauses(store.data.quietMode, at: now).first(where: { !$0.isGlobal && $0.covers(category) }) {
                        Button("Ruhe für diesen Bereich beenden", systemImage: "bell.fill") { store.endQuiet(pause.id) }
                    }
                    if muted {
                        Button("Wieder einschalten", systemImage: "bell.fill") { store.setCategoryMuted(category, muted: false) }
                    } else {
                        Section("Ruhen lassen") {
                            ForEach([QuietDuration.oneHour, .threeHours, .untilMorning, .oneDay, .oneWeek, .open]) { duration in
                                Button(duration.title, systemImage: duration.symbol) { store.startQuiet(categories: [category], until: duration.end(from: Date())) }
                            }
                        }
                        Button("Dauerhaft stumm", systemImage: "bell.slash.fill", role: .destructive) { store.setCategoryMuted(category, muted: true) }
                    }
                } label: {
                    TherapySettingsRow(title: category.title, icon: category.symbol, subtitle: category.subtitle, tint: category.tint, value: state(category, now: now))
                }
                .buttonStyle(TherapyRowPressStyle())
                .accessibilityIdentifier("quiet.category." + category.rawValue)
            }
        }
    }

    private func state(_ category: ReminderCategory, now: Date) -> String {
        let settings = store.data.quietMode
        if settings.mutedCategories.contains(category) { return "Stumm" }
        if let pause = QuietPolicy.activePauses(settings, at: now).first(where: { $0.covers(category) && !($0.isGlobal && category == .wake && settings.wakeAlarmsIgnorePause) && !($0.isGlobal && category == .session && settings.runningSessionIgnoresPause) }) {
            return pause.until.map { "bis " + QuietPolicy.shortStamp($0, now: now) } ?? "Ruht"
        }
        return "An"
    }

    // MARK: Upcoming

    private func upcomingCard(_ all: [PlannedReminder], now: Date) -> some View {
        let filtered: [PlannedReminder] = all.filter { item in
            switch filter {
            case 1: return item.channel == .alarm
            case 2: return item.channel == .notification
            case 3: return item.isQuiet
            default: return true
            }
        }
        let visible = showAllUpcoming ? filtered : Array(filtered.prefix(25))
        let days: [ReminderDay] = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.fireAt) }
            .map { ReminderDay(id: $0.key, items: $0.value) }
            .sorted { $0.id < $1.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Kommende 7 Tage", systemImage: "list.bullet.below.rectangle").font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(all.filter { !$0.isQuiet }.count) aktiv · \(all.filter(\.isQuiet).count) ruhen").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            Picker("Filter", selection: $filter) {
                Text("Alle").tag(0); Text("Wecker").tag(1); Text("Mitteilungen").tag(2); Text("Ruhend").tag(3)
            }
            .pickerStyle(.segmented)
            if visible.isEmpty {
                ContentUnavailableView("Nichts geplant", systemImage: "bell.slash", description: Text(filter == 3 ? "Gerade ruht keine Erinnerung." : "In den nächsten sieben Tagen ist hier nichts geplant."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 4, style: .continuous))
            }
            ForEach(days) { day in
                let entries = day.items
                VStack(alignment: .leading, spacing: 6) {
                    Text(dayTitle(day.id, now: now)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        ForEach(entries) { item in
                            reminderRow(item, now: now)
                            if item.id != entries.last?.id { Divider().padding(.leading, 64) }
                        }
                    }
                    .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 4, style: .continuous))
                }
            }
            if filtered.count > visible.count {
                Button("Alle \(filtered.count) anzeigen", systemImage: "chevron.down") { withAnimation { showAllUpcoming = true } }
                    .buttonStyle(.glass).frame(maxWidth: .infinity)
            }
        }
    }

    private func reminderRow(_ item: PlannedReminder, now: Date) -> some View {
        HStack(spacing: 12) {
            TherapyIconTile(icon: item.channel == .alarm ? "alarm.fill" : item.category.symbol, size: 36, tint: item.isQuiet ? .gray : item.category.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.fireAt.formatted(date: .omitted, time: .shortened)).font(.subheadline.weight(.bold)).monospacedDigit()
                    if item.channel == .alarm { Text("Wecker").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.red.opacity(0.15), in: Capsule()).foregroundStyle(.red) }
                }
                Text(item.title).font(.subheadline).lineLimit(1).strikethrough(item.isQuiet).foregroundStyle(item.isQuiet ? .secondary : .primary)
                if let reason = item.quietReason {
                    Label(reason, systemImage: "moon.fill").font(.caption).foregroundStyle(.indigo)
                } else {
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                rowActions(item)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Aktionen für " + item.title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu { rowActions(item) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func rowActions(_ item: PlannedReminder) -> some View {
        let silenced = store.data.quietMode.silenced.filter { ($0.wholeSource && $0.key == item.source) || (!$0.wholeSource && $0.key == item.key) }
        if !silenced.isEmpty {
            Button("Wieder einschalten", systemImage: "bell.fill") { for entry in silenced { store.restoreSilenced(entry.id) } }
        } else {
            Button("Nur dieses Mal überspringen", systemImage: "forward.end.fill") { store.silence(item, wholeSource: false, until: item.fireAt.addingTimeInterval(3600)) }
            Button("24 Stunden stumm", systemImage: "moon.zzz.fill") { store.silence(item, wholeSource: true, until: Date().addingTimeInterval(86400)) }
            Button("Stumm, bis ich es ändere", systemImage: "bell.slash.fill") { store.silence(item, wholeSource: true, until: nil) }
        }
        if let route = QuietSourceRoute(item: item, data: store.data) {
            Divider()
            Button("Einstellungen öffnen", systemImage: "slider.horizontal.3") { editing = route }
        }
    }

    private func dayTitle(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Heute" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) { return "Morgen" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: Silenced

    private func silencedCard(now: Date) -> some View {
        TherapySettingsSection(title: "Einzeln stummgeschaltet") {
            ForEach(store.data.quietMode.silenced) { item in
                HStack(spacing: 12) {
                    TherapyIconTile(icon: item.category.symbol, size: 32, tint: .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? item.category.title : item.title).font(.subheadline).lineLimit(1)
                        Text((item.wholeSource ? "Alle Hinweise" : "Ein Termin") + " · " + (item.until.map { $0 > now ? "bis " + QuietPolicy.shortStamp($0, now: now) : "abgelaufen" } ?? "bis du es änderst"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ein") { store.restoreSilenced(item.id) }.buttonStyle(.glass).font(.caption.weight(.bold))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    // MARK: Quiet hours

    private var quietHoursCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Ruhezeiten", icon: "moon.stars.fill", subtitle: "Jeden Tag, zum Beispiel nachts – ohne daran denken zu müssen.")
                Toggle("Tägliche Ruhezeit", isOn: $store.data.quietMode.quietHours.enabled)
                if store.data.quietMode.quietHours.enabled {
                    HStack {
                        DatePicker("Von", selection: clock(hour: \.startHour, minute: \.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Bis", selection: clock(hour: \.endHour, minute: \.endMinute), displayedComponents: .hourAndMinute)
                    }
                    Text("Ruhig in dieser Zeit:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowChips(items: ReminderCategory.allCases.map { (id: $0.rawValue, title: $0.title, symbol: $0.symbol) }, selected: Set(store.data.quietMode.quietHours.categories.map(\.rawValue))) { raw in
                        guard let category = ReminderCategory(rawValue: raw) else { return }
                        var categories = store.data.quietMode.quietHours.categories
                        if categories.contains(category) { categories.removeAll { $0 == category } } else { categories.append(category) }
                        store.data.quietMode.quietHours.categories = categories
                    }
                }
                Divider()
                Toggle("Aufsteh-Wecker klingeln trotz Ruhe", isOn: $store.data.quietMode.wakeAlarmsIgnorePause)
                Toggle("Laufende Therapiestunde meldet sich trotz Ruhe", isOn: $store.data.quietMode.runningSessionIgnoresPause)
                Toggle("Hinweis, wenn eine Ruhe endet", isOn: $store.data.quietMode.announceEnd)
                Text("Gilt für „Alles in Ruhe“. Wenn du einen Bereich ausdrücklich ruhen lässt, schweigt auch er.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clock(hour: WritableKeyPath<QuietHours, Int>, minute: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(get: {
            let value = store.data.quietMode.quietHours
            return Calendar.current.date(bySettingHour: value[keyPath: hour], minute: value[keyPath: minute], second: 0, of: Date()) ?? Date()
        }, set: { date in
            var value = store.data.quietMode.quietHours
            value[keyPath: hour] = Calendar.current.component(.hour, from: date)
            value[keyPath: minute] = Calendar.current.component(.minute, from: date)
            store.data.quietMode.quietHours = value
        })
    }

    // MARK: System

    private var systemCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Auf deinem iPhone", icon: "iphone.gen3", subtitle: "Was iOS gerade wirklich bereithält.")
                HStack(spacing: 10) {
                    statTile(value: "\(system.pendingNotifications)", title: "Mitteilungen", icon: "bell.badge.fill", ok: system.notificationsAllowed)
                    statTile(value: "\(system.scheduledAlarms)", title: "Wecker", icon: "alarm.fill", ok: system.alarmsAllowed)
                }
                if system.notificationsAllowed == false {
                    Button("Mitteilungen erlauben", systemImage: "bell.fill") { Task { await TaskNotificationCoordinator.shared.requestAccess(store); await system.load() } }.buttonStyle(.glass)
                }
                if system.alarmsAllowed == false {
                    Button("Wecker (AlarmKit) erlauben", systemImage: "alarm.fill") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store); await system.load() } }.buttonStyle(.glass)
                }
                ForEach([store.quietStatus, store.taskReminderStatus, store.routineReminderStatus, store.checkInReminderStatus, store.routineAlarmStatus].filter { !$0.isEmpty }, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                Button("Jetzt neu planen", systemImage: "arrow.triangle.2.circlepath") {
                    TaskNotificationCoordinator.shared.refresh(store)
                    Task { try? await Task.sleep(for: .seconds(1.5)); await system.load() }
                }
                .buttonStyle(.glass)
                Text("Kalender-Erinnerungen deines iPhone-Kalenders verwaltet die Kalender-App. iOS begrenzt geplante Mitteilungen; die App füllt den Vorrat bei jedem Öffnen auf.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(value: String, title: String, icon: String, ok: Bool?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(ok == false ? Color.orange : Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.bold)).monospacedDigit()
                Text(ok == false ? title + " · nicht erlaubt" : title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .therapyInsetSurface()
    }

    // MARK: Sources

    private var sourcesCard: some View {
        TherapySettingsSection(title: "Einrichten") {
            TherapySettingsLink(title: "Routinen", icon: "repeat", tint: .green, value: "\(store.data.routines.count)") { RoutineHubView() }
            TherapySettingsLink(title: "Wecker & Aufstehen", icon: "alarm.fill", tint: .red, value: "\(store.data.wakeAlarms.count)") { WakeAlarmHubView() }
            TherapySettingsLink(title: "Aufgaben & Wochenenergie", icon: "checklist", tint: .orange) { ReminderCenterView() }
            Button { sheetPage = .checkIns } label: { TherapySettingsRow(title: "Check-in-Zeiten", icon: "sun.horizon.fill", tint: .yellow) }
                .buttonStyle(TherapyRowPressStyle())
            Button { sheetPage = .therapy } label: { TherapySettingsRow(title: "Therapie-Termine & Wecker", icon: "calendar.badge.clock", tint: .indigo) }
                .buttonStyle(TherapyRowPressStyle())
            TherapySettingsLink(title: "Betreutes Wohnen", icon: "house.fill", tint: .brown) { AssistedLivingSettingsView() }
        }
    }

    private func historyCard(now: Date) -> some View {
        let past = store.data.quietMode.pauses.filter { !$0.isActive(at: now) }.prefix(5)
        return Group {
            if !past.isEmpty {
                TherapySettingsSection(title: "Zuletzt geruht") {
                    ForEach(Array(past)) { pause in
                        TherapySettingsRow(title: pause.title, icon: "moon.fill",
                                           subtitle: pause.start.formatted(date: .abbreviated, time: .shortened) + " – " + (pause.end?.formatted(date: .omitted, time: .shortened) ?? "offen") + (pause.endedAt != nil && (pause.until.map { pause.endedAt! < $0 } ?? true) ? " · vorzeitig beendet" : ""),
                                           tint: .gray, showsChevron: false)
                    }
                }
            }
        }
    }
}

/// The big rest card: start quickly, see what rests, end early.
struct QuietHeroCard: View {
    @EnvironmentObject private var store: AppStore
    let now: Date
    var compose: () -> Void

    var body: some View {
        let settings = store.data.quietMode
        let global = QuietPolicy.globalPause(settings, at: now)
        let partial = QuietPolicy.activePauses(settings, at: now).filter { !$0.isGlobal }
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 16) {
                if let global {
                    HStack(spacing: 14) {
                        TherapyIconTile(icon: "moon.zzz.fill", size: 52, tint: .indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ruhe ist an").font(.system(.title2, design: .rounded, weight: .bold))
                            if let until = global.until {
                                Text("bis " + QuietPolicy.shortStamp(until, now: now) + " · noch " + remaining(until)).font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("bis du sie beendest").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let until = global.until {
                        ProgressView(value: max(0, min(1, now.timeIntervalSince(global.start) / max(60, until.timeIntervalSince(global.start))))).tint(.indigo)
                    }
                    Text(exemptions(settings)).font(.caption).foregroundStyle(.secondary)
                    PrimaryActionButton(title: "Ruhe jetzt beenden", icon: "bell.fill") { store.endQuiet(global.id) }
                        .accessibilityIdentifier("quiet.end")
                    HStack(spacing: 8) {
                        Button("+1 Std.") { store.extendQuiet(global.id, hours: 1) }
                        Button("+3 Std.") { store.extendQuiet(global.id, hours: 3) }
                        Button("+24 Std.") { store.extendQuiet(global.id, hours: 24) }
                    }
                    .buttonStyle(.glass).font(.subheadline.weight(.semibold))
                } else {
                    HStack(spacing: 14) {
                        TherapyIconTile(icon: "bell.and.waves.left.and.right.fill", size: 52, tint: .accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Alles meldet sich").font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Brauchst du eine Pause von Weckern und Hinweisen?").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach([QuietDuration.oneHour, .threeHours, .untilMorning, .oneDay, .threeDays, .open]) { duration in
                            Button {
                                store.startQuiet(until: duration.end(from: Date()))
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: duration.symbol).font(.headline)
                                    Text(duration.short).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TherapyPressStyle())
                            .therapyInsetSurface()
                            .accessibilityLabel("Ruhe " + duration.title)
                            .accessibilityIdentifier("quiet.start." + duration.rawValue)
                        }
                    }
                    Text(exemptions(settings)).font(.caption).foregroundStyle(.secondary)
                }
                if !partial.isEmpty {
                    Divider()
                    ForEach(partial) { pause in
                        HStack(spacing: 10) {
                            Image(systemName: "moon.fill").foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pause.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(pause.until.map { "bis " + QuietPolicy.shortStamp($0, now: now) } ?? "bis du sie beendest").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Beenden") { store.endQuiet(pause.id) }.buttonStyle(.glass).font(.caption.weight(.bold))
                        }
                    }
                }
                Button("Nur bestimmte Bereiche ruhen lassen …", systemImage: "slider.horizontal.3", action: compose)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func remaining(_ until: Date) -> String {
        let minutes = max(0, Int(until.timeIntervalSince(now) / 60))
        if minutes < 60 { return "\(minutes) Min." }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) Std. \(minutes % 60) Min." }
        return "\(hours / 24) Tage"
    }

    private func exemptions(_ settings: QuietModeSettings) -> String {
        var parts: [String] = []
        if settings.wakeAlarmsIgnorePause { parts.append("Aufsteh-Wecker") }
        if settings.runningSessionIgnoresPause { parts.append("eine laufende Therapiestunde") }
        return parts.isEmpty ? "Während der Ruhe schweigen alle Wecker und Hinweise der App." : "Ausgenommen: " + parts.joined(separator: " und ") + ". Notfallplan und Einträge bleiben immer verfügbar."
    }
}

/// Choose areas and a duration for a pause.
struct QuietComposerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var categories: Set<ReminderCategory> = []
    @State private var duration = QuietDuration.oneDay
    @State private var custom = false
    @State private var customEnd = Date().addingTimeInterval(86400)
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReminderCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { categories.contains(category) }, set: { on in if on { categories.insert(category) } else { categories.remove(category) } })) {
                            Label { VStack(alignment: .leading) { Text(category.title); Text(category.subtitle).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: category.symbol).foregroundStyle(category.tint) }
                        }
                    }
                } header: { Text("Was soll ruhen?") } footer: { Text(categories.isEmpty ? "Nichts ausgewählt bedeutet: alles (mit den Ausnahmen aus den Ruhe-Einstellungen)." : "\(categories.count) Bereiche ruhen, alles andere meldet sich weiter.") }
                Section("Wie lange?") {
                    Picker("Dauer", selection: $duration) {
                        ForEach(QuietDuration.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .disabled(custom)
                    Toggle("Eigenes Ende wählen", isOn: $custom)
                    if custom { DatePicker("Ende", selection: $customEnd, in: Date().addingTimeInterval(300)..., displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("Notiz (optional)") { TextField("z. B. Urlaub, krank, Ruhetag", text: $note) }
            }
            .therapyFormStyle()
            .navigationTitle("Ruhe einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten") {
                        store.startQuiet(categories: Array(categories), until: custom ? customEnd : duration.end(from: Date()), note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A banner for Heute while a general pause is active.
struct QuietStatusBanner: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            if let pause = QuietPolicy.globalPause(store.data.quietMode, at: context.date) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill").font(.title3).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ruhe ist an").font(.subheadline.weight(.bold))
                        Text(pause.until.map { "bis " + QuietPolicy.shortStamp($0, now: context.date) } ?? "bis du sie beendest").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Beenden") { store.endQuiet(pause.id) }.buttonStyle(.glassProminent).font(.caption.weight(.bold))
                }
                .padding(14)
                .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius, style: .continuous), tint: Color.indigo.opacity(0.12))
                .onTapGesture { store.notificationQuietCenter = true }
            }
        }
    }
}

/// Simple wrapping chips for multi-selection.
struct FlowChips: View {
    let items: [(id: String, title: String, symbol: String)]
    let selected: Set<String>
    let toggle: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let on = selected.contains(item.id)
                Button { toggle(item.id) } label: {
                    Label(item.title, systemImage: on ? "checkmark.circle.fill" : item.symbol)
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .therapyInsetSurface(cornerRadius: 12, selected: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Where a planned reminder is configured.
struct QuietSourceRoute: Identifiable {
    enum Kind { case routine(UUID), task(WeeklyTask), wake, therapy, checkIns, session, energy, wellness, bewo }
    let id: String
    let kind: Kind

    init?(item: PlannedReminder, data: AppData) {
        id = item.id
        let parts = item.route.split(separator: "|").map(String.init)
        switch parts.first ?? "" {
        case "routine": guard parts.count > 1, let value = UUID(uuidString: parts[1]) else { return nil }; kind = .routine(value)
        case "task": guard parts.count > 1, let value = UUID(uuidString: parts[1]), let task = data.weeklyTasks.first(where: { $0.id == value }) else { return nil }; kind = .task(task)
        case "wake": kind = .wake
        case "therapy": kind = .therapy
        case "checkin": kind = .checkIns
        case "session": kind = .session
        case "energy": kind = .energy
        case "wellness": kind = .wellness
        case "bewo": kind = .bewo
        default: return nil
        }
    }
}

struct QuietSourceDestination: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let route: QuietSourceRoute
    var body: some View {
        switch route.kind {
        case .routine(let id): RoutineDetailView(routineID: id)
        case .task(let task): WeeklyTaskEditorView(task: task)
        case .therapy: TherapyAppointmentsView()
        case .checkIns: DayCheckInSettingsView(slots: DayCheckInPolicy.slots(store.data.companionSettings))
        default:
            NavigationStack {
                content
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            }
        }
    }
    @ViewBuilder private var content: some View {
        switch route.kind {
        case .wake: WakeAlarmHubView()
        case .session: SessionPreferencesView(controller: store.sessionController)
        case .energy: ReminderCenterView()
        case .wellness: WellnessSettingsView()
        case .bewo: AssistedLivingSettingsView()
        default: EmptyView()
        }
    }
}
