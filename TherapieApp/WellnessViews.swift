import SwiftUI
import Charts
import UIKit

enum WellnessRange: String, CaseIterable, Identifiable {
    case week = "Letzte Woche", seven = "7 Tage", thirty = "30 Tage", ninety = "90 Tage", all = "Alles"
    var id: String { rawValue }
    var period: WellnessPeriod {
        switch self {
        case .week: return .week(containing: Date().therapyAddingWeeks(-1))
        case .seven: return .rolling(days: 7)
        case .thirty: return .rolling(days: 30)
        case .ninety: return .rolling(days: 90)
        case .all: return WellnessPeriod(start: .distantPast, end: Date().addingTimeInterval(0.001))
        }
    }
}

private enum WellnessDeletion {
    case mood(MoodCheckIn), point(BatteryPoint), review(WeekReview)
    var message: String {
        switch self {
        case .mood: return "Der Check-in und seine zugehörigen Akku-Punkte werden gelöscht. Das kann nicht rückgängig gemacht werden."
        case .point(let point): return "„\(point.title)“ wird endgültig gelöscht."
        case .review: return "Dieser Wochenrückblick wird endgültig gelöscht. Deine Check-ins bleiben erhalten."
        }
    }
}

struct WellnessHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section = 0
    @State private var range: WellnessRange = .thirty
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var direction: BatteryDirection?
    @State private var moodDraft: MoodCheckIn?
    @State private var moodViewing: MoodCheckIn?
    @State private var pointDraft: BatteryPoint?
    @State private var reviewDraft: WeekReview?
    @State private var deletion: WellnessDeletion?
    @State private var showDelete = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showExport = false

    private var period: WellnessPeriod { range.period }
    private var points: [BatteryPoint] {
        store.data.batteryPoints.filter {
            period.contains($0.date) && (direction == nil || $0.direction == direction)
            && matches([$0.title, $0.note, $0.category.title, $0.direction.title])
        }.sorted { $0.date > $1.date }
    }
    private func matches(_ texts: [String]) -> Bool {
        search.isEmpty || texts.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    NavigationLink { BuddyWellbeingProfileView() } label: { Label("Mein Befinden · Live, heute & 7 Tage", systemImage: "heart.text.clipboard") }
                    WeeklyEnergyCard()
                    WellnessProgressCard()
                    actions
                    Picker("Bereich", selection: $section) {
                        Text("Einträge").tag(0)
                        Text("Diagramme").tag(1)
                        Text("Wochen").tag(2)
                    }.pickerStyle(.segmented)
                    if section != 2 {
                        HStack {
                            Label("Zeitraum", systemImage: "calendar")
                            Spacer()
                            Picker("Zeitraum", selection: $range) {
                                ForEach(WellnessRange.allCases) { Text($0.rawValue).tag($0) }
                            }.labelsHidden()
                        }.font(.subheadline)
                    }
                    if section == 0 { history }
                    if section == 1 { WellnessChartsView(period: period) }
                    if section == 2 { WeeklyEnergyHistory(); weeks }
                }
            }
            .navigationTitle("Stimmung")
            .searchable(text: $search, prompt: "Gefühle, Akku-Punkte und Rückblicke")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("CSV für diesen Zeitraum", systemImage: "square.and.arrow.up") {
                            do { exportURL = try store.exportWellnessCSV(period: period); showExport = true }
                            catch { exportError = error.localizedDescription }
                        }
                        NavigationLink { WellnessSettingsView() } label: { Label("Ziele & Erinnerungen", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $moodDraft) { entry in
                MoodEditorView(entry: entry, points: store.data.batteryPoints.filter { $0.checkInID == entry.id })
            }
            .sheet(item: $moodViewing) { MoodCheckInDetailView(entryID: $0.id) }
            .sheet(item: $pointDraft) { BatteryPointEditorView(point: $0) { store.saveBatteryPoint($0); return store.lastSaveError == nil } }
            .sheet(item: $reviewDraft) { WeekReviewEditorView(review: $0) }
            .sheet(isPresented: $showExport) {
                if let exportURL { WellnessShareView(url: exportURL) }
            }
            .alert("Eintrag löschen?", isPresented: $showDelete) {
                Button("Abbrechen", role: .cancel) { deletion = nil }
                Button("Endgültig löschen", role: .destructive) {
                    switch deletion {
                    case .mood(let entry): store.deleteCheckIn(entry)
                    case .point(let point): store.deleteBatteryPoint(point.id)
                    case .review(let review): store.data.weekReviews.removeAll { $0.id == review.id }
                    case nil: break
                    }
                    deletion = nil
                }
            } message: { Text(deletion?.message ?? "") }
            .alert("Export nicht möglich", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 10) {
            Button { moodDraft = MoodCheckIn() } label: { actionLabel("Check-in", "face.smiling", .indigo) }
                .accessibilityIdentifier("wellness.new-checkin")
            Button { pointDraft = BatteryPoint() } label: { actionLabel("Akku-Punkt", "battery.100percent", .teal) }
                .accessibilityIdentifier("wellness.new-point")
            Button { openReview(Date().therapyAddingWeeks(-1)) } label: { actionLabel("Wochenblick", "calendar.badge.checkmark", .orange) }
        }.buttonStyle(.plain)
    }
    private func actionLabel(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(color)
    }
    private func requestDelete(_ target: WellnessDeletion) { deletion = target; showDelete = true }
    private func openReview(_ date: Date) {
        reviewDraft = store.data.weekReviews.first { $0.weekStart == date.therapyWeekStart }
            ?? WeekReview(weekStart: date.therapyWeekStart)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Nur Lieblings-Check-ins", isOn: $favoritesOnly).font(.subheadline)
            let entries = store.data.moodCheckIns.filter {
                period.contains($0.date) && (!favoritesOnly || $0.favorite)
                && matches([$0.note, $0.smallWin, $0.nextNeed, $0.moodTitle] + $0.emotions)
            }.sorted { $0.date > $1.date }
            SectionHeader(title: "Deine Check-ins", icon: "face.smiling", subtitle: "\(entries.count) im gewählten Zeitraum")
            if entries.isEmpty {
                empty("Noch kein passender Check-in", "Ein kurzer Eintrag reicht. Du musst nicht alle Felder ausfüllen.", "face.smiling")
            }
            ForEach(entries) { entry in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text(entry.face).font(.largeTitle).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.moodTitle).font(.headline)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { moodDraft = entry }
                                Button(entry.favorite ? "Favorit entfernen" : "Als Favorit merken", systemImage: "star") {
                                    if let index = store.data.moodCheckIns.firstIndex(where: { $0.id == entry.id }) {
                                        store.data.moodCheckIns[index].favorite.toggle()
                                    }
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { requestDelete(.mood(entry)) }
                            } label: { Image(systemName: entry.favorite ? "star.fill" : "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Label("Akku \(entry.battery)/5", systemImage: "battery.100percent").font(.subheadline.bold()).foregroundStyle(.teal)
                        if !entry.emotions.isEmpty { Text(entry.emotions.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                        if !entry.note.isEmpty { Text(entry.note).lineLimit(4) }
                        if !entry.smallWin.isEmpty { Label(entry.smallWin, systemImage: "sparkles").font(.subheadline) }
                        if !entry.nextNeed.isEmpty { Label(entry.nextNeed, systemImage: "heart").font(.subheadline).foregroundStyle(.secondary) }
                        Button("Check-in öffnen") { moodViewing = entry }.font(.subheadline.bold())
                    }
                }
            }
            Divider()
            SectionHeader(title: "Einzelne Akku-Punkte", icon: "bolt.heart", subtitle: "Jeder Mensch, Termin oder Moment darf ein eigener Punkt sein.")
            Picker("Akku-Richtung", selection: $direction) {
                Text("Alle").tag(Optional<BatteryDirection>.none)
                ForEach(BatteryDirection.allCases) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.segmented)
            if points.isEmpty { empty("Noch keine passenden Akku-Punkte", "Füge Geber und Nehmer einzeln hinzu – auch rückwirkend für letzte Woche.", "battery.50percent") }
            ForEach(points) { point in
                BatteryPointCard(point: point, edit: { pointDraft = point }, delete: { requestDelete(.point(point)) })
            }
            let legacy = store.data.energyEntries.filter { period.contains($0.createdAt) && matches([$0.givesEnergy, $0.takesEnergy, $0.note]) }
            if !legacy.isEmpty {
                DisclosureGroup("\(legacy.count) frühere Energie-Checks") {
                    ForEach(legacy) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.createdAt.formatted(date: .abbreviated, time: .omitted)) · Akku \(entry.level)/5").bold()
                            if !entry.givesEnergy.isEmpty { Text("Gibt: " + entry.givesEnergy) }
                            if !entry.takesEnergy.isEmpty { Text("Nimmt: " + entry.takesEnergy) }
                            if !entry.note.isEmpty { Text(entry.note) }
                        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
            }
        }
    }
    private var weeks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Einmal pro Woche innehalten. Nachtragen ist erlaubt; Pausen sind kein Versagen.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(0..<8, id: \.self) { offset in
                let start = Date().therapyAddingWeeks(-offset).therapyWeekStart
                let interval = WellnessPeriod.week(containing: start)
                let count = WellnessAnalytics.activityDates(store.data).filter { interval.contains($0) }.count
                let review = store.data.weekReviews.first { $0.weekStart == start }
                if search.isEmpty || matches([review?.summary ?? "", review?.therapyQuestion ?? "", review?.nextStep ?? ""]) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(offset == 0 ? "Diese Woche" : "KW \(start.therapyWeek.week) / \(start.therapyWeek.year)").font(.headline)
                                    Text(start.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Label("\(count)", systemImage: count > 0 ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(count > 0 ? .teal : .secondary)
                            }
                            if let review {
                                if !review.summary.isEmpty { Text(review.summary).lineLimit(4) }
                                if !review.nextStep.isEmpty { Label(review.nextStep, systemImage: "arrow.right.circle").font(.subheadline) }
                                HStack {
                                    Button("Rückblick bearbeiten") { reviewDraft = review }
                                    Spacer()
                                    Button("Löschen", role: .destructive) { requestDelete(.review(review)) }
                                }.font(.subheadline)
                            } else {
                                Button("Rückblick festhalten", systemImage: "square.and.pencil") { openReview(start) }
                            }
                        }
                    }
                }
            }
            let older = store.data.weekReviews.filter { $0.weekStart < Date().therapyAddingWeeks(-7).therapyWeekStart && matches([$0.summary, $0.therapyQuestion, $0.nextStep]) }.sorted { $0.weekStart > $1.weekStart }
            ForEach(older) { review in
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(review.weekStart.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                        Text(review.summary).lineLimit(3)
                        HStack {
                            Button("Bearbeiten") { reviewDraft = review }
                            Spacer()
                            Button("Löschen", role: .destructive) { requestDelete(.review(review)) }
                        }
                    }
                }
            }
        }
    }
    private func empty(_ title: String, _ description: String, _ symbol: String) -> some View {
        GlassCard { ContentUnavailableView(title, systemImage: symbol, description: Text(description)) }
    }
}

struct WellnessProgressCard: View {
    @EnvironmentObject private var store: AppStore
    private var streak: WellnessStreak { WellnessAnalytics.streak(WellnessAnalytics.activityDates(store.data)) }
    private var days: Int { WellnessAnalytics.recordedDays(store.data, period: .week(containing: Date())) }
    var body: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Dein Wochenrhythmus", systemImage: "flame").font(.headline)
                        Text("\(streak.current) \(streak.current == 1 ? "Woche" : "Wochen") am Stück").font(.system(.title2, design: .rounded, weight: .bold))
                    }
                    Spacer()
                    Image(systemName: streak.thisWeekRecorded ? "checkmark.seal.fill" : "leaf.fill").font(.title).foregroundStyle(.teal).accessibilityHidden(true)
                }
                Text(streak.thisWeekRecorded ? "Diese Woche hast du dir Zeit für dich genommen." : "Diese Woche ist noch offen. Ein kleiner Eintrag reicht.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(min(days, store.data.wellnessSettings.weeklyGoal)), total: Double(max(1, store.data.wellnessSettings.weeklyGoal))).tint(.teal)
                Text("\(days) von \(store.data.wellnessSettings.weeklyGoal) Check-in-Tagen · Längste Serie: \(streak.longest) Wochen").font(.caption).foregroundStyle(.secondary)
                Text("Die Serie zählt jede Woche mit Check-in, Akku-Punkt oder Rückblick. Das Tagesziel ist davon unabhängig.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct BatteryPointCard: View {
    let point: BatteryPoint
    let edit: () -> Void
    let delete: () -> Void
    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: point.direction.symbol).font(.title2).foregroundStyle(point.direction == .gives ? .teal : .orange).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(point.title).font(.headline)
                    Text("\(point.direction.title) · Wirkung \(point.impactDescription)").font(.subheadline).foregroundStyle(point.direction == .gives ? .teal : .orange)
                    Label(point.category.title, systemImage: point.category.symbol).font(.caption).foregroundStyle(.secondary)
                    Text(point.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if !point.note.isEmpty { Text(point.note).font(.subheadline).lineLimit(4) }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Bearbeiten", systemImage: "pencil", action: edit)
                    Button("Löschen", systemImage: "trash", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
            }
        }
    }
}

private enum WellnessMetric: String, CaseIterable, Identifiable {
    case mood = "Stimmung", battery = "Akku", stress = "Stress", sensory = "Reize"
    var id: String { rawValue }
    func value(_ day: DailyWellnessValue) -> Double? {
        switch self { case .mood: day.mood; case .battery: day.battery; case .stress: day.stress; case .sensory: day.sensory }
    }
    var color: Color { self == .battery ? .green : self == .stress || self == .sensory ? .orange : .green }
}

struct WellnessChartsView: View {
    @EnvironmentObject private var store: AppStore
    let period: WellnessPeriod
    @State private var metric: WellnessMetric = .mood
    @State private var selectedDate: Date?
    private var daily: [DailyWellnessValue] { WellnessAnalytics.daily(store.data, period: period) }
    private var points: [BatteryPoint] { store.data.batteryPoints.filter { period.contains($0.date) } }
    private var chartDays: [DailyWellnessValue] {
        var previous: Date?
        var segment = 0
        return daily.filter { metric.value($0) != nil }.map { day in
            if let previous, Calendar.therapyCalendar.dateComponents([.day], from: previous, to: day.date).day != 1 { segment += 1 }
            previous = day.date
            return DailyWellnessValue(date: day.date, mood: day.mood, battery: day.battery, stress: day.stress, sensory: day.sensory, count: day.count, segment: segment)
        }
    }
    private var selected: DailyWellnessValue? {
        guard let selectedDate else { return nil }
        return daily.filter { metric.value($0) != nil }.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Dein Verlauf", icon: "chart.xyaxis.line", subtitle: "Tagesmittelwerte · keine erfundenen Werte an freien Tagen")
                    Picker("Messwert", selection: $metric) {
                        ForEach(WellnessMetric.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    let values = daily.compactMap { metric.value($0) }
                    if let average = WellnessAnalytics.average(values) {
                        Text("Ø \(average, specifier: "%.1f") / 5").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(metric.color)
                        Text("\(values.count) Tage mit \(metric.rawValue)-Werten").font(.caption).foregroundStyle(.secondary)
                        trendChart
                        if let selected, let value = metric.value(selected) {
                            Text("\(selected.date.formatted(date: .abbreviated, time: .omitted)): \(value, specifier: "%.1f") / 5").font(.subheadline.bold())
                        } else { Text("Tippe oder ziehe im Diagramm, um einen Tag anzusehen.").font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("Werte als Liste") {
                            ForEach(daily) { day in
                                if let value = metric.value(day) {
                                    LabeledContent(day.date.formatted(date: .abbreviated, time: .omitted), value: String(format: "%.1f / 5", value))
                                }
                            }
                        }.font(.subheadline)
                    } else {
                        ContentUnavailableView("Noch keine \(metric.rawValue)-Werte", systemImage: "chart.xyaxis.line", description: Text("Erfasse diesen Wert bei einem Check-in. Freie Tage zählen nicht als Null."))
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Was bewegt deinen Akku?", icon: "battery.100percent", subtitle: "Summierte, selbst eingeschätzte Wirkung deiner einzelnen Punkte")
                    if points.isEmpty {
                        ContentUnavailableView("Noch keine Akku-Punkte", systemImage: "bolt.heart", description: Text("Gib jedem Akku-Geber oder -Nehmer eine Wirkung von 1 bis 5."))
                    } else {
                        batteryChart
                        HStack {
                            Label("Gibt Akku", systemImage: "plus.circle.fill").foregroundStyle(.teal)
                            Spacer()
                            Label("Nimmt Akku", systemImage: "minus.circle.fill").foregroundStyle(.orange)
                        }.font(.caption.bold())
                        Text("\(points.filter { $0.direction == .gives }.count) Geber · \(points.filter { $0.direction == .takes }.count) Nehmer").font(.subheadline)
                        ForEach(Array(points.sorted { $0.impact > $1.impact }.prefix(3))) { point in
                            Label("\(point.title) · \(point.impactDescription)", systemImage: point.direction.symbol)
                                .font(.subheadline).foregroundStyle(point.direction == .gives ? .teal : .orange)
                        }
                    }
                }
            }
            Text("Die Diagramme beschreiben nur deine Einträge, keine Diagnose und keine Ursache-Wirkung-Beziehung. Frühere Energie-Checks erscheinen ausschließlich beim Akku.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var trendChart: some View {
        Chart {
            ForEach(chartDays) { day in
                if let value = metric.value(day) {
                    LineMark(x: .value("Tag", day.date), y: .value(metric.rawValue, value), series: .value("Abschnitt", day.segment))
                        .foregroundStyle(metric.color).interpolationMethod(.linear)
                    PointMark(x: .value("Tag", day.date), y: .value(metric.rawValue, value))
                        .foregroundStyle(metric == .stress || metric == .sensory ? BatteryTone.burden(Int(value.rounded())) : BatteryTone.color(Int(((value - 1) * 25).rounded()))).symbolSize(45)
                }
            }
            if let selected { RuleMark(x: .value("Ausgewählter Tag", selected.date)).foregroundStyle(.secondary.opacity(0.4)) }
        }
        .chartYScale(domain: 1...5)
        .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
        .chartXSelection(value: $selectedDate)
        .frame(height: 210)
        .accessibilityLabel("\(metric.rawValue)-Verlauf, Skala 1 bis 5")
    }
    private var batteryChart: some View {
        Chart(WellnessAnalytics.categoryTotals(points)) { total in
            BarMark(x: .value("Wirkung", total.impact), y: .value("Bereich", total.category.title))
                .foregroundStyle(total.direction == .gives ? Color.green : Color.red)
                .cornerRadius(4)
                .accessibilityLabel("\(total.category.title): \(total.direction.title), \(total.count) Punkte, Wirkung \(abs(total.impact))")
        }.frame(height: CGFloat(max(180, Set(points.map(\.category)).count * 36)))
    }
}

struct MoodEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry: MoodCheckIn
    @State private var points: [BatteryPoint]
    @State private var detailed = false
    @State private var pointDraft: BatteryPoint?
    @State private var deletePoint: UUID?
    @State private var showDelete = false
    @State private var discard = false
    @State private var prepared = false
    @State private var reopened = false
    @State private var initial: MoodCheckIn
    @State private var initialPoints: [BatteryPoint]
    init(entry: MoodCheckIn = MoodCheckIn(), points: [BatteryPoint] = []) {
        _initial = State(initialValue: entry); _initialPoints = State(initialValue: points)
        _entry = State(initialValue: entry); _points = State(initialValue: points)
        _detailed = State(initialValue: entry.stress != nil || entry.sensoryLoad != nil || entry.sleepHours != nil || !entry.note.isEmpty)
    }
    private var dirty: Bool { entry != initial || points != initialPoints }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if reopened { Label("Vorhandener Check-in · du bearbeitest deinen heutigen Eintrag", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                    DatePicker("Wann?", selection: $entry.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    MoodBarometerControl(percent: Binding(get: { entry.moodPercent ?? (entry.mood - 1) * 25 }, set: { entry.moodPercent = $0; entry.mood = MoodBarometer.score($0) }))
                    Stepper("Akku: \(entry.battery)/5", value: $entry.battery, in: 1...5)
                    Text("1 = fast leer · 5 = voll").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Wie geht es dir?") } footer: { Text("Zwei Werte reichen für einen kurzen Check-in. Alles Weitere ist freiwillig.") }
                Section("Gefühle · mehrere möglich") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                        ForEach(MoodCheckIn.emotionOptions, id: \.self) { emotion in
                            Button {
                                if entry.emotions.contains(emotion) { entry.emotions.removeAll { $0 == emotion } }
                                else { entry.emotions.append(emotion) }
                            } label: {
                                Text(emotion).font(.subheadline).padding(.vertical, 10).frame(maxWidth: .infinity)
                                    .background(entry.emotions.contains(emotion) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(entry.emotions.contains(emotion) ? .isSelected : [])
                        }
                    }
                }
                Section("Einzelne Akku-Geber & -Nehmer") {
                    ForEach(points) { point in
                        HStack {
                            Button { pointDraft = point } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title).font(.headline)
                                    Text("\(point.direction.title) · \(point.impactDescription)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) { deletePoint = point.id; showDelete = true } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Akku-Punkt entfernen")
                        }
                    }
                    Button("Gibt mir Akku", systemImage: "plus.circle") { pointDraft = BatteryPoint(direction: .gives) }
                    Button("Nimmt mir Akku", systemImage: "minus.circle") { pointDraft = BatteryPoint(direction: .takes) }
                }
                Section {
                    Toggle("Ausführlicher Check-in", isOn: $detailed)
                    if detailed {
                        optionalScore("Stress", value: $entry.stress)
                        optionalScore("Reizbelastung", value: $entry.sensoryLoad)
                        Toggle("Schlaf festhalten", isOn: Binding(get: { entry.sleepHours != nil }, set: { entry.sleepHours = $0 ? 8 : nil }))
                        if entry.sleepHours != nil {
                            Stepper("Schlaf: \(entry.sleepHours ?? 0, specifier: "%.1f") Stunden", value: Binding(get: { entry.sleepHours ?? 8 }, set: { entry.sleepHours = $0 }), in: 0...24, step: 0.5)
                        }
                        TextField("Was war los?", text: $entry.note, axis: .vertical).lineLimit(3...8)
                        TextField("Mein kleiner Erfolg", text: $entry.smallWin, axis: .vertical).lineLimit(2...5)
                        TextField("Was brauche ich als Nächstes?", text: $entry.nextNeed, axis: .vertical).lineLimit(2...5)
                    }
                    Toggle("Als Favorit merken", isOn: $entry.favorite)
                } header: { Text("Mehr Raum für dich") } footer: { Text("Stress und Reizbelastung: 1 = gering, 5 = sehr hoch. Nicht ausgefüllte Werte bleiben leer.") }
            }
            .onAppear {
                guard !prepared else { return }; prepared = true
                if !store.data.moodCheckIns.contains(where: { $0.id == entry.id }), let saved = MoodDailyPolicy.existing(for: entry, in: store.data) {
                    entry = saved; points = store.data.batteryPoints.filter { $0.checkInID == saved.id }
                    initial = entry; initialPoints = points; reopened = true
                    detailed = entry.stress != nil || entry.sensoryLoad != nil || entry.sleepHours != nil || !entry.note.isEmpty
                }
            }
            .navigationTitle("Stimmungs-Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { store.saveCheckIn(entry, points: points); if store.lastSaveError == nil { store.removeEditorDraft(entry.id); if store.lastSaveError == nil { dismiss() } } }
                        .accessibilityIdentifier("wellness.save-checkin")
                }
            }
            .interactiveDismissDisabled(dirty)
            .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
            .sheet(item: $pointDraft) { point in
                CheckInKeywordEditor(point: point) { saved in
                    points.removeAll { $0.id == saved.id }; points.append(saved)
                }
            }
            .alert("Änderungen verwerfen?", isPresented: $discard) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Als Entwurf speichern") { store.saveEditorDraft(MoodEntryDraft(entry: entry, points: points), id: entry.id, kind: "mood", title: "Stimmungs-Check-in"); if store.lastSaveError == nil { dismiss() } }
                Button("Verwerfen", role: .destructive) { store.removeEditorDraft(entry.id); if store.lastSaveError == nil { dismiss() } }
            }
            .alert("Akku-Punkt entfernen?", isPresented: $showDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Entfernen", role: .destructive) { points.removeAll { $0.id == deletePoint } }
            } message: { Text("Diese Änderung wird erst mit dem Check-in gespeichert.") }
        }
    }
    private func optionalScore(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title + " festhalten", isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? 3 : nil }))
            if value.wrappedValue != nil {
                Stepper("\(title): \(value.wrappedValue ?? 3)/5", value: Binding(get: { value.wrappedValue ?? 3 }, set: { value.wrappedValue = $0 }), in: 1...5)
            }
        }
    }
}

struct BatteryPointEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var point: BatteryPoint
    @State private var discard = false
    let showDate: Bool
    let onSave: (BatteryPoint) -> Bool
    private let initial: BatteryPoint
    init(point: BatteryPoint = BatteryPoint(), showDate: Bool = true, onSave: @escaping (BatteryPoint) -> Bool) {
        initial = point; _point = State(initialValue: point); self.showDate = showDate; self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Ein Moment, ein Punkt") {
                    TextField("Zum Beispiel: Spaziergang im Wald", text: $point.title, axis: .vertical).lineLimit(2...4)
                        .accessibilityIdentifier("wellness.point-title")
                    Picker("Richtung", selection: $point.direction) { ForEach(BatteryDirection.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Picker("Bereich", selection: $point.category) { ForEach(BatteryCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                    Stepper("Wirkung: \(point.impact)/5", value: $point.impact, in: 1...5)
                    Text("1 = wenig · 5 = sehr stark").font(.caption).foregroundStyle(.secondary)
                    if showDate { DatePicker("Wann?", selection: $point.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("Details · freiwillig") { TextField("Was genau hat geholfen oder belastet?", text: $point.note, axis: .vertical).lineLimit(3...8) }
            }
            .navigationTitle("Akku-Punkt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if point != initial { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { var rated = point; rated.impactConfirmed = true; if onSave(rated) { store.removeEditorDraft(point.id); if store.lastSaveError == nil { dismiss() } } }.disabled(point.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(point != initial)
            .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
            .alert("Änderungen verwerfen?", isPresented: $discard) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Als Entwurf speichern") { store.saveEditorDraft(point, id: point.id, kind: "battery", title: point.title); if store.lastSaveError == nil { dismiss() } }
                Button("Verwerfen", role: .destructive) { store.removeEditorDraft(point.id); if store.lastSaveError == nil { dismiss() } }
            }
        }
    }
}

struct WeekReviewEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var review: WeekReview
    @State private var discard = false
    private let initial: WeekReview
    init(review: WeekReview) { initial = review; _review = State(initialValue: review) }
    private var period: WellnessPeriod { .week(containing: review.weekStart) }
    private var hasContent: Bool {
        [review.summary, review.whatHelped, review.whatWasHard, review.smallWin, review.nextStep, review.therapyQuestion]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Woche ab", selection: $review.weekStart, in: ...Date(), displayedComponents: .date)
                        .onChange(of: review.weekStart) { _, value in
                            let start = value.therapyWeekStart
                            if let existing = store.data.weekReviews.first(where: { $0.weekStart == start && $0.id != review.id }) {
                                review = existing
                            } else { review.weekStart = start }
                        }
                    Text("KW \(review.weekStart.therapyWeek.week) · \(WellnessAnalytics.activityDates(store.data).filter { period.contains($0) }.count) Einträge").font(.subheadline).foregroundStyle(.secondary)
                    let points = store.data.batteryPoints.filter { period.contains($0.date) }
                    if !points.isEmpty {
                        DisclosureGroup("Akku-Punkte dieser Woche ansehen") {
                            ForEach(points.sorted { $0.date < $1.date }) { point in
                                Label(point.title, systemImage: point.direction.symbol).foregroundStyle(point.direction == .gives ? .teal : .orange)
                            }
                        }
                    }
                } header: { Text("Dein Wochenrückblick") } footer: { Text("Ein Rückblick pro Woche. Schon ein Feld reicht.") }
                Section("Einmal innehalten") {
                    field("Wie war diese Woche für mich?", $review.summary)
                    field("Was hat mir Akku gegeben?", $review.whatHelped)
                    field("Was hat mich Kraft gekostet?", $review.whatWasHard)
                    field("Ein kleiner Erfolg, den ich würdigen möchte", $review.smallWin)
                }
                Section("Mitnehmen") {
                    field("Ein kleiner nächster Schritt", $review.nextStep)
                    field("Das möchte ich in der Therapie besprechen", $review.therapyQuestion)
                }
            }
            .navigationTitle("Wochenrückblick").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if review != initial { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { store.saveWeekReview(review); if store.lastSaveError == nil { store.removeEditorDraft(review.id); if store.lastSaveError == nil { dismiss() } } }.disabled(!hasContent)
                }
            }
            .interactiveDismissDisabled(review != initial)
            .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
            .alert("Änderungen verwerfen?", isPresented: $discard) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Als Entwurf speichern") { store.saveEditorDraft(review, id: review.id, kind: "weekReview", title: "Wochenrückblick"); if store.lastSaveError == nil { dismiss() } }
            }
        }
    }
    private func field(_ title: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("Freiwillig", text: value, axis: .vertical).lineLimit(2...6)
        }
    }
}

struct WellnessSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var status = ""
    @State private var permissionSetup = false
    @State private var applying = false
    private var reminderTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: store.data.wellnessSettings.reminderHour, minute: store.data.wellnessSettings.reminderMinute)) ?? Date()
        }, set: { value in
            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
            store.data.wellnessSettings.reminderHour = components.hour ?? 18
            store.data.wellnessSettings.reminderMinute = components.minute ?? 0
        })
    }
    var body: some View {
        Form {
            Section("Dein Rhythmus") {
                Stepper("\(store.data.wellnessSettings.weeklyGoal) Check-in-Tage pro Woche", value: $store.data.wellnessSettings.weeklyGoal, in: 1...7)
                Text("Ein Tag zählt einmal, auch mit mehreren Check-ins. Die Wochen-Serie braucht nur einen Eintrag pro Woche.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sanfte Wochen-Erinnerung") {
                Toggle("Wöchentlich erinnern", isOn: $store.data.wellnessSettings.reminderEnabled)
                if store.data.wellnessSettings.reminderEnabled {
                    Toggle("Zusätzlich als AlarmKit-Wecker", isOn: Binding(get: { store.data.companionSettings.wellnessAlarmEnabled ?? false }, set: { store.data.companionSettings.wellnessAlarmEnabled = $0 }))
                    Button("Wecker freigeben", systemImage: "alarm") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store) } }
                    Picker("Wochentag", selection: $store.data.wellnessSettings.reminderWeekday) {
                        ForEach(1...7, id: \.self) { Text(TherapyDateHelper.weekdayName($0)).tag($0) }
                    }
                    DatePicker("Uhrzeit", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                Button(applying ? "Wird übernommen …" : "Erinnerung übernehmen") {
                    applying = true
                    Task {
                        do { try await WeeklyReminderService.apply(store.data.wellnessSettings); status = "Erinnerungseinstellung übernommen." }
                        catch { status = error.localizedDescription }
                        applying = false
                    }
                }.disabled(applying)
                if !status.isEmpty { Text(status).font(.subheadline) }
                Text("Auf dem Sperrbildschirm stehen keine Stimmungswerte oder Therapiedetails.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Berechtigungen") {
                Button("Berechtigungseinrichtung öffnen", systemImage: "hand.raised") { permissionSetup = true }
                Text("Fotos werden über die Systemauswahl freigegeben. Die App braucht keinen Zugriff auf deine ganze Fotomediathek.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ziele & Erinnerungen")
        .sheet(isPresented: $permissionSetup) { PermissionSetupView() }
    }
}

struct WellnessShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct WellnessSaveErrorView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let error = store.lastSaveError {
            Label("Speichern nicht möglich: " + error, systemImage: "exclamationmark.triangle")
                .font(.caption).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.18))
        }
    }
}
