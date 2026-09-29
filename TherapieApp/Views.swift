import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private let therapyContentMaxWidth: CGFloat = 720

struct RootView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.data.profile.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(.indigo)
        .accessibilityIdentifier("therapy.root")
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility2 : dynamicTypeSize)
        .overlay {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                GeometryReader { geometry in
                    Text("\(Int(geometry.size.width))x\(Int(geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom))")
                        .font(.system(size: 1))
                        .accessibilityIdentifier("therapy.viewport")
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Design system

struct AppBackground: View {
    @AppStorage("therapy.calmInterface") private var calmInterface = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if !calmInterface && !reduceTransparency {
                LinearGradient(colors: [.indigo.opacity(0.12), .cyan.opacity(0.05), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
    }
}

struct TherapyScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                content
                    .frame(maxWidth: therapyContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlassCard<Content: View>: View {
    var emphasized = false
    @AppStorage("therapy.calmInterface") private var calmInterface = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if calmInterface || reduceTransparency {
                cardContent
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(emphasized ? Color.indigo.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
                    }
            } else {
                cardContent
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }
    private var cardContent: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
    }
}

struct PrimaryActionButton: View {
    let title: String
    let icon: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

struct ResponsiveButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content
            }

            VStack(spacing: 10) {
                content
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var userName = ""
    @State private var therapistName = ""

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        TherapyLogoMark()

                        Text("Dein Therapiebegleiter")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.82)

                        Text("Therapie, Aufgaben, Notizen, Fotos und Rückblicke – ruhig organisiert an einem Ort.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }
                    .padding(.top, 34)

                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(
                                title: "Einmal einrichten",
                                icon: "person.2.fill",
                                subtitle: "Du kannst beide Namen später jederzeit ändern."
                            )

                            VStack(spacing: 12) {
                                TextField("Dein Name", text: $userName)
                                    .accessibilityIdentifier("onboarding.name")
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .padding(13)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                TextField("Therapeutin / Therapeut", text: $therapistName)
                                    .accessibilityIdentifier("onboarding.therapist")
                                    .textInputAutocapitalization(.words)
                                    .padding(13)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            PrimaryActionButton(
                                title: "Therapiebegleiter starten",
                                icon: "arrow.right.circle.fill"
                            ) {
                                store.data.profile.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.data.profile.therapistName = therapistName.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.data.profile.onboardingCompleted = true
                            }
                            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.secondary)
                        Text("Deine Therapiedaten bleiben standardmäßig lokal auf deinem iPhone. Kalender, Standort, Mikrofon, AlarmKit und Backup werden nur verwendet, wenn du es freigibst.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct TherapyLogoMark: View {
    var body: some View {
        Image("TherapyMark")
            .resizable()
            .scaledToFit()
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Main navigation

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Heute", systemImage: "sparkles") }

            TherapyCalendarView()
                .tabItem { Label("Kalender", systemImage: "calendar") }

            TasksView()
                .tabItem { Label("Aufgaben", systemImage: "checklist") }

            LibraryView()
                .tabItem { Label("Archiv", systemImage: "square.stack.3d.up.fill") }

            SettingsView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNote = false
    @State private var showEnergy = false
    @State private var showReflection = false

    private var currentTask: WeeklyTask? {
        let week = Date().therapyWeek
        let tasks = store.data.weeklyTasks.filter {
            $0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year
        }
        return tasks.first { !$0.completed } ?? tasks.first
    }

    private var nextTherapy: Date? {
        TherapyDateHelper.nextOccurrence(schedule: store.data.schedule)
    }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    hero
                    quickActions
                    WeekOverviewCard()
                    weeklyTaskCard
                    latestCard
                }
            }
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showNote) {
                AddNoteView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showEnergy) {
                AddEnergyView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showReflection) {
                AddReflectionView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var hero: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        Text(Date().formatted(date: .complete, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "brain.head.profile.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nächste Therapie")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let nextTherapy {
                            Text(nextTherapy.formatted(date: .abbreviated, time: .shortened))
                                .font(.title3.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            if !store.data.profile.therapistName.isEmpty {
                                Text("mit " + store.data.profile.therapistName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("Noch nicht geplant")
                                .font(.headline)
                        }
                    }

                    Spacer(minLength: 0)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        StatusPill(text: "KW \(Date().therapyWeek.week)", icon: "calendar")
                        StatusPill(
                            text: currentTask == nil ? "Keine Wochenaufgabe" : (currentTask?.completed == true ? "Aufgaben erledigt" : "Aufgabe offen"),
                            icon: currentTask?.completed == true ? "checkmark.circle.fill" : "circle.dashed"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill(text: "KW \(Date().therapyWeek.week)", icon: "calendar")
                        StatusPill(
                            text: currentTask == nil ? "Keine Wochenaufgabe" : (currentTask?.completed == true ? "Aufgaben erledigt" : "Aufgabe offen"),
                            icon: currentTask?.completed == true ? "checkmark.circle.fill" : "circle.dashed"
                        )
                    }
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<12: prefix = "Guten Morgen"
        case 12..<18: prefix = "Hallo"
        default: prefix = "Guten Abend"
        }

        let name = store.data.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? prefix : prefix + ", " + name
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schnell erfassen")
                .font(.headline)
                .padding(.horizontal, 2)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 12
            ) {
                QuickActionButton(title: "Notiz", subtitle: "Gedanken", icon: "square.and.pencil") {
                    showNote = true
                }
                QuickActionButton(title: "Energie", subtitle: "Check-in", icon: "bolt.heart.fill") {
                    showEnergy = true
                }
                QuickActionButton(title: "Rückblick", subtitle: "Therapie", icon: "clock.arrow.circlepath") {
                    showReflection = true
                }
            }
        }
    }

    private var weeklyTaskCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Wochenaufgabe",
                    icon: "checkmark.seal.fill",
                    subtitle: "Kalenderwoche \(Date().therapyWeek.week)"
                )

                if let task = currentTask {
                    Text(task.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    if !task.details.isEmpty {
                        Text(task.details)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        guard let index = store.data.weeklyTasks.firstIndex(where: { $0.id == task.id }) else { return }
                        store.data.weeklyTasks[index].completed.toggle()
                        store.data.weeklyTasks[index].completedAt = store.data.weeklyTasks[index].completed ? Date() : nil
                    } label: {
                        Label(
                            task.completed ? "Wieder öffnen" : "Als erledigt markieren",
                            systemImage: task.completed ? "arrow.uturn.backward.circle" : "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                } else {
                    Text("Für diese Woche ist noch keine Aufgabe eingetragen.")
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        TasksView()
                    } label: {
                        Label("Aufgabe anlegen", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }
        }
    }

    private var latestCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Zuletzt festgehalten",
                    icon: "clock.fill",
                    subtitle: "Deine neuesten Notizen"
                )

                if store.data.notes.isEmpty {
                    Text("Noch keine Notizen. Über „Schnell erfassen“ kannst du jederzeit etwas festhalten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.data.notes.prefix(3))) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if note.id != store.data.notes.prefix(3).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct QuickActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(TherapyPressStyle())
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Calendar

struct TherapyCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date()
    @State private var statusMessage: String?
    @State private var syncing = false

    private var therapyWeekdayMatch: Bool {
        Calendar.current.component(.weekday, from: selectedDate) == store.data.schedule.weekday
    }

    private var dayNotes: [TherapyNote] {
        store.data.notes.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }
    }

    private var dayMedia: [MediaItem] {
        store.data.media.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }
    }

    private var dayEnergy: [EnergyEntry] {
        store.data.energyEntries.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    calendarCard
                    selectedDayCard
                    syncCard
                }
            }
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            DatePicker(
                "Datum",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var selectedDayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Ausgewählter Tag",
                    icon: "calendar.day.timeline.left",
                    subtitle: selectedDate.formatted(date: .complete, time: .omitted)
                )

                if therapyWeekdayMatch {
                    HStack(spacing: 9) {
                        Image(systemName: "heart.circle.fill")
                        Text("Regulärer Therapietag · \(String(format: "%02d:%02d", store.data.schedule.hour, store.data.schedule.minute)) Uhr")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if dayNotes.isEmpty && dayMedia.isEmpty && dayEnergy.isEmpty && !therapyWeekdayMatch {
                    Text("Für diesen Tag gibt es noch keine Einträge.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
                        spacing: 10
                    ) {
                        if !dayNotes.isEmpty {
                            DayCountTile(title: "Notizen", count: dayNotes.count, icon: "note.text")
                        }
                        if !dayMedia.isEmpty {
                            DayCountTile(title: "Medien", count: dayMedia.count, icon: "photo.on.rectangle.angled")
                        }
                        if !dayEnergy.isEmpty {
                            DayCountTile(title: "Energie", count: dayEnergy.count, icon: "bolt.fill")
                        }
                    }
                }
            }
        }
    }

    private var syncCard: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "iPhone-Kalender & AlarmKit",
                    icon: "iphone.badge.radiowaves.left.and.right",
                    subtitle: "Einmal tippen, danach hält die App deine Einstellungen synchron."
                )

                Text("Erstellt bzw. aktualisiert deinen wöchentlichen Therapietermin im iPhone-Kalender und richtet die ausgewählten AlarmKit-Erinnerungen ein.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PrimaryActionButton(
                    title: syncing ? "Synchronisiere …" : "Jetzt synchronisieren",
                    icon: "arrow.triangle.2.circlepath",
                    isBusy: syncing
                ) {
                    syncEverything()
                }
                .disabled(syncing)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func syncEverything() {
        syncing = true
        statusMessage = nil

        Task {
            do {
                let eventID = try await CalendarSyncService.shared.sync(
                    schedule: store.data.schedule,
                    profile: store.data.profile
                )
                store.data.schedule.calendarEventIdentifier = eventID

                let ids = try await AlarmService.shared.replaceAll(schedule: store.data.schedule)
                store.data.schedule.alarmIDs = ids
                statusMessage = "Kalender und \(ids.count) Alarme wurden synchronisiert."
            } catch {
                statusMessage = error.localizedDescription
            }

            syncing = false
        }
    }
}

struct DayCountTile: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Tasks

struct TasksView: View {
    @State private var onlyOpen = false
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 14) {
                    Toggle("Nur offene Aufgaben", isOn: $onlyOpen)
                        .padding(.horizontal, 4)
                    if onlyOpen && !store.data.weeklyTasks.isEmpty && store.data.weeklyTasks.allSatisfy(\.completed) {
                        ContentUnavailableView("Alles erledigt", systemImage: "checkmark.seal",
                                               description: Text("Du hast alle eingetragenen Aufgaben abgeschlossen."))
                    }
                    if store.data.weeklyTasks.isEmpty {
                        GlassCard {
                            ContentUnavailableView(
                                "Noch keine Wochenaufgaben",
                                systemImage: "checklist",
                                description: Text("Lege die Aufgabe aus deiner Therapiesitzung für die aktuelle Kalenderwoche an.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                        }
                    } else {
                        ForEach($store.data.weeklyTasks) { $task in
                            if !onlyOpen || !task.completed {
                                taskCard(task: $task)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wochenaufgaben")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Wochenaufgabe")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTaskView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func taskCard(task: Binding<WeeklyTask>) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatusPill(
                        text: "KW \(task.wrappedValue.weekOfYear) / \(task.wrappedValue.yearForWeekOfYear)",
                        icon: "calendar"
                    )

                    Spacer(minLength: 4)

                    Button {
                        task.wrappedValue.completed.toggle()
                        task.wrappedValue.completedAt = task.wrappedValue.completed ? Date() : nil
                    } label: {
                        Image(systemName: task.wrappedValue.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.wrappedValue.completed ? "Als offen markieren" : "Als erledigt markieren")

                    Menu {
                        Button(role: .destructive) {
                            store.data.weeklyTasks.removeAll { $0.id == task.wrappedValue.id }
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }

                TextField("Aufgabe", text: task.title)
                    .font(.headline)

                TextField("Beschreibung", text: task.details, axis: .vertical)
                    .foregroundStyle(.secondary)
                    .lineLimit(2...6)
            }
        }
    }
}

// MARK: - Archive

private enum LibrarySection: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case media = "Medien"
    case notes = "Notizen"
    case energy = "Energie"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeline: "clock.arrow.circlepath"
        case .media: "photo.on.rectangle.angled"
        case .notes: "note.text"
        case .energy: "bolt.heart.fill"
        }
    }
}

struct LibraryView: View {
    @State private var searchText = ""
    @EnvironmentObject private var store: AppStore
    @State private var section: LibrarySection = .timeline
    @State private var showPhoto = false
    @State private var showAudio = false
    @State private var showNote = false
    @State private var showDocument = false

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 14) {
                    sectionSelector

                    Group {
                        switch section {
                        case .timeline:
                            TimelineView(searchText: searchText)
                        case .media:
                            mediaSection
                        case .notes:
                            notesSection
                        case .energy:
                            energySection
                        }
                    }
                }
            }
            .navigationTitle("Therapie-Archiv")
            .searchable(text: $searchText, prompt: "Notizen, Medien und Rückblicke suchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Foto hinzufügen", systemImage: "photo.badge.plus") {
                            showPhoto = true
                        }
                        Button("Sprachaufnahme", systemImage: "mic.fill") {
                            showAudio = true
                        }
                        Button("Dokument importieren", systemImage: "doc.badge.plus") {
                            showDocument = true
                        }
                        Button("Notiz", systemImage: "square.and.pencil") {
                            showNote = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showPhoto) {
                AddPhotoView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAudio) {
                AudioRecordingView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNote) {
                AddNoteView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDocument) {
                ImportDocumentView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var sectionSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LibrarySection.allCases) { item in
                    Button {
                        withAnimation(.snappy) {
                            section = item
                        }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                section == item ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.thinMaterial),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var mediaSection: some View {
        LazyVStack(spacing: 12) {
            if store.data.media.isEmpty {
                GlassCard {
                    ContentUnavailableView(
                        "Noch keine Medien",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Speichere Fotos deiner Pläne, Dokumente oder Sprachaufnahmen.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                }
            }

            ForEach(store.data.media.filter { matches([$0.title, $0.note] + $0.tags) }) { item in
                GlassCard {
                    HStack(alignment: .top, spacing: 13) {
                        MediaThumbnail(item: item)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)

                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !item.tags.isEmpty {
                                Text(item.tags.map { "#" + $0 }.joined(separator: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if let lat = item.latitude, let lon = item.longitude {
                                Label(
                                    String(format: "%.5f, %.5f", lat, lon),
                                    systemImage: "location.fill"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 4)

                        Menu {
                            Button(role: .destructive) {
                                store.deleteMedia(item)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        LazyVStack(spacing: 12) {
            if store.data.notes.isEmpty {
                GlassCard {
                    ContentUnavailableView("Noch keine Notizen", systemImage: "note.text")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
            }

            ForEach($store.data.notes) { $note in
                if matches([note.title, note.text] + note.tags) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("Titel", text: $note.title)
                            .font(.headline)

                        TextField("Notiz", text: $note.text, axis: .vertical)
                            .lineLimit(2...8)

                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#" + $0 }.joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                }
            }
        }
    }

    private var energySection: some View {
        LazyVStack(spacing: 12) {
            if store.data.energyEntries.isEmpty {
                GlassCard {
                    ContentUnavailableView("Noch keine Energie-Checks", systemImage: "bolt.heart.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
            }

            ForEach(store.data.energyEntries.filter { matches([$0.note, $0.givesEnergy, $0.takesEnergy, "Energie \($0.level)"]) }) { entry in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Energie \(entry.level)/5", systemImage: "bolt.heart.fill")
                                .font(.headline)
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !entry.givesEnergy.isEmpty {
                            InsightRow(title: "Gibt Energie", text: entry.givesEnergy, icon: "plus.circle.fill")
                        }
                        if !entry.takesEnergy.isEmpty {
                            InsightRow(title: "Nimmt Energie", text: entry.takesEnergy, icon: "minus.circle.fill")
                        }
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ values: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.contains { $0.localizedStandardContains(query) }
    }

    @ViewBuilder
    private func MediaThumbnail(item: MediaItem) -> some View {
        let url = store.fileURL(for: item)

        if item.kind == .photo, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: item.kind.symbol)
                .font(.title2)
                .frame(width: 66, height: 66)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct InsightRow: View {
    let title: String
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TimelineView: View {
    var searchText = ""
    @EnvironmentObject private var store: AppStore

    private struct Row: Identifiable {
        let id: String
        let date: Date
        let title: String
        let subtitle: String
        let icon: String
    }

    private var rows: [Row] {
        var values: [Row] = []

        values += store.data.notes.map {
            Row(id: "n-" + $0.id.uuidString, date: $0.createdAt, title: $0.title, subtitle: $0.text, icon: "note.text")
        }
        values += store.data.media.map {
            Row(id: "m-" + $0.id.uuidString, date: $0.createdAt, title: $0.title, subtitle: $0.kind.displayName, icon: $0.kind.symbol)
        }
        values += store.data.energyEntries.map {
            Row(id: "e-" + $0.id.uuidString, date: $0.createdAt, title: "Energie-Check \($0.level)/5", subtitle: $0.note, icon: "bolt.heart.fill")
        }
        values += store.data.reflections.map {
            Row(id: "r-" + $0.id.uuidString, date: $0.date, title: "Therapie-Rückblick", subtitle: $0.summary, icon: "clock.arrow.circlepath")
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.filter { query.isEmpty || ($0.title + " " + $0.subtitle).localizedStandardContains(query) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        LazyVStack(spacing: 12) {
            if rows.isEmpty {
                GlassCard {
                    ContentUnavailableView(
                        "Deine Timeline ist noch leer",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Notizen, Medien, Energie-Checks und Rückblicke erscheinen hier automatisch.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                }
            }

            ForEach(rows) { row in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)

                            if !row.subtitle.isEmpty {
                                Text(row.subtitle)
                                    .font(.subheadline)
                                    .lineLimit(4)
                                    .foregroundStyle(.secondary)
                            }

                            Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showFolderPicker = false
    @State private var statusMessage: String?
    @State private var deletePhrase = ""
    @State private var showDeleteDialog = false
    @State private var showRestoreDialog = false

    private let deleteConfirmation = "ALLE THERAPIEDATEN LÖSCHEN"

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    profileCard
                    AppearanceCard()
                    scheduleCard
                    reminderCard
                    backupCard
                    privacyCard
                    dangerCard
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    try BackupService.shared.selectFolder(url)
                    try store.backupNow()
                    statusMessage = "Backup-Ordner verbunden und erste Sicherung erstellt."
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            .alert("Backup wiederherstellen?", isPresented: $showRestoreDialog) {
                Button("Abbrechen", role: .cancel) {}
                Button("Wiederherstellen") {
                    do {
                        try store.restoreFromBackup()
                        statusMessage = "Backup wurde wiederhergestellt."
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
            } message: {
                Text("Die lokalen Therapiedaten werden durch den Stand aus dem ausgewählten Backup-Ordner ersetzt.")
            }
            .alert("Alle Daten löschen?", isPresented: $showDeleteDialog) {
                TextField(deleteConfirmation, text: $deletePhrase)
                Button("Abbrechen", role: .cancel) {
                    deletePhrase = ""
                }
                Button("Endgültig löschen", role: .destructive) {
                    guard deletePhrase == deleteConfirmation else { return }
                    CalendarSyncService.shared.removeSyncedEvent(identifier: store.data.schedule.calendarEventIdentifier)
                    AlarmService.shared.cancelAllOwnedAlarms()
                    store.resetAllData()
                    BackupService.shared.clearFolder()
                    deletePhrase = ""
                }
                .disabled(deletePhrase != deleteConfirmation)
            } message: {
                Text("Tippe exakt „\(deleteConfirmation)“. Fotos, Audios, Notizen, Aufgaben und Rückblicke werden danach lokal gelöscht.")
            }
        }
    }

    private var profileCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Personen",
                    icon: "person.2.fill",
                    subtitle: "Die Namen erscheinen nur innerhalb deiner App."
                )

                TextField("Dein Name", text: $store.data.profile.userName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                TextField("Therapeutin / Therapeut", text: $store.data.profile.therapistName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    private var scheduleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Fester Therapietag",
                    icon: "calendar.badge.clock",
                    subtitle: "Wird für Kalender und AlarmKit verwendet."
                )

                LabeledContent("Wochentag") {
                    Picker("Wochentag", selection: $store.data.schedule.weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(TherapyDateHelper.weekdayName(day)).tag(day)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                DatePicker(
                    "Uhrzeit",
                    selection: therapyTimeBinding,
                    displayedComponents: .hourAndMinute
                )

                Stepper(
                    "Dauer: \(store.data.schedule.durationMinutes) Minuten",
                    value: $store.data.schedule.durationMinutes,
                    in: 30...180,
                    step: 15
                )
            }
        }
    }

    private var therapyTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                from: DateComponents(
                    year: 2001,
                    month: 1,
                    day: 1,
                    hour: store.data.schedule.hour,
                    minute: store.data.schedule.minute
                )
            ) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            store.data.schedule.hour = components.hour ?? 0
            store.data.schedule.minute = components.minute ?? 0
        }
    }

    private var taskReminderTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                from: DateComponents(
                    year: 2001,
                    month: 1,
                    day: 1,
                    hour: store.data.schedule.taskReminderHour,
                    minute: store.data.schedule.taskReminderMinute
                )
            ) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            store.data.schedule.taskReminderHour = components.hour ?? 18
            store.data.schedule.taskReminderMinute = components.minute ?? 0
        }
    }

    private var reminderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Erinnerungen",
                    icon: "alarm.fill",
                    subtitle: "Du entscheidest selbst, wie früh du erinnert wirst."
                )

                reminderToggle("1 Tag vorher", minutes: 1440)
                reminderToggle("2 Stunden vorher", minutes: 120)
                reminderToggle("30 Minuten vorher", minutes: 30)
                reminderToggle("10 Minuten vorher", minutes: 10)

                Divider()

                Toggle("Wochenaufgaben-Impulse", isOn: $store.data.schedule.taskReminderEnabled)

                if store.data.schedule.taskReminderEnabled {
                    DatePicker(
                        "Uhrzeit der Impulse",
                        selection: taskReminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )

                    Text("Die Impulse werden beim nächsten Synchronisieren als AlarmKit-Alarme neu gesetzt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reminderToggle(_ title: String, minutes: Int) -> some View {
        let binding = Binding<Bool>(
            get: {
                store.data.schedule.reminderOffsetsMinutes.contains(minutes)
            },
            set: { enabled in
                if enabled {
                    if !store.data.schedule.reminderOffsetsMinutes.contains(minutes) {
                        store.data.schedule.reminderOffsetsMinutes.append(minutes)
                        store.data.schedule.reminderOffsetsMinutes.sort(by: >)
                    }
                } else {
                    store.data.schedule.reminderOffsetsMinutes.removeAll { $0 == minutes }
                }
            }
        )

        return Toggle(title, isOn: binding)
    }

    private var backupCard: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Backup",
                    icon: "icloud.and.arrow.up.fill",
                    subtitle: "iCloud Drive oder ein Ordner auf deinem iPhone"
                )

                if let folder = BackupService.shared.selectedFolderName() {
                    StatusPill(text: "Verbunden: " + folder, icon: "checkmark.circle.fill")
                } else {
                    Text("Noch kein Backup-Ordner ausgewählt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Bei Änderungen automatisch sichern",
                    isOn: $store.data.preferences.autoBackupToSelectedFolder
                )

                ResponsiveButtonRow {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Ordner wählen", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        do {
                            try store.backupNow()
                            statusMessage = "Backup wurde aktualisiert."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Jetzt sichern", systemImage: "arrow.clockwise.icloud")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    showRestoreDialog = true
                } label: {
                    Label("Backup wiederherstellen", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!BackupService.shared.hasSelectedFolder)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var privacyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Privatsphäre",
                    icon: "lock.shield.fill",
                    subtitle: "Keine eigenen Server, kein Tracking-SDK."
                )

                Toggle(
                    "Standort bei neuen Medien mitschreiben",
                    isOn: $store.data.preferences.includeLocationForNewMedia
                )

                Text("Standortdaten werden nur nach iOS-Freigabe gespeichert und bleiben Teil deiner lokalen bzw. selbst gewählten Backup-Daten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dangerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Datenverwaltung",
                    icon: "exclamationmark.triangle.fill",
                    subtitle: "Ein Komplett-Reset braucht einen exakten Sicherheitssatz."
                )

                Button("Alle Therapiedaten löschen", role: .destructive) {
                    showDeleteDialog = true
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Add / edit sheets

struct AddTaskView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Wochenaufgabe", text: $title)
                    TextField("Beschreibung", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Neue Aufgabe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addWeeklyTask(title: title, details: details)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddNoteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var tags = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Notiz") {
                    TextField("Titel", text: $title)
                    TextField("Notiz", text: $text, axis: .vertical)
                        .lineLimit(5...12)
                }
                Section("Tags") {
                    TextField("z. B. Energie, Arbeit, Therapie", text: $tags)
                }
            }
            .navigationTitle("Neue Notiz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addNote(
                            title: title.isEmpty ? "Notiz" : title,
                            text: text,
                            tags: parseTags(tags)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddEnergyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var level = 3
    @State private var gives = ""
    @State private var takes = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Energie heute") {
                    Stepper("Energie: \(level)/5", value: $level, in: 1...5)
                }
                Section("Was gibt mir Energie?") {
                    TextField("Menschen, Ruhe, Musik …", text: $gives, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Was nimmt mir Energie?") {
                    TextField("Lärm, Konflikte, Termine …", text: $takes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Notiz") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Energie-Check")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addEnergy(level: level, gives: gives, takes: takes, note: note)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddReflectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var helped = ""
    @State private var nextFocus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Was haben wir gemacht?") {
                    TextField("Zusammenfassung", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Was hat geholfen?") {
                    TextField("Hilfreiches festhalten", text: $helped, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Bis zur nächsten Therapie") {
                    TextField("Fokus / nächster Schritt", text: $nextFocus, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Therapie-Rückblick")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addReflection(summary: summary, helped: helped, nextFocus: nextFocus)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddPhotoView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationService()

    @State private var pickerItem: PhotosPickerItem?
    @State private var title = ""
    @State private var note = ""
    @State private var tags = ""
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Foto") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(
                            pickerItem == nil ? "Foto auswählen" : "Foto ausgewählt",
                            systemImage: pickerItem == nil ? "photo.badge.plus" : "checkmark.circle.fill"
                        )
                    }
                }

                Section("Beschreibung") {
                    TextField("Name des Fotos", text: $title)
                    TextField("Notiz", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Tags, durch Komma getrennt", text: $tags)
                }

                if store.data.preferences.includeLocationForNewMedia {
                    Section("Standort") {
                        Button("Aktuellen Standort erfassen") {
                            location.requestCurrentLocation()
                        }

                        if let current = location.lastLocation {
                            Text(String(format: "%.5f, %.5f", current.coordinate.latitude, current.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Foto hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Speichere …" : "Speichern") {
                        save()
                    }
                    .disabled(pickerItem == nil || saving)
                }
            }
        }
    }

    private func save() {
        guard let pickerItem else { return }
        saving = true

        Task {
            do {
                guard let bytes = try await pickerItem.loadTransferable(type: Data.self) else {
                    throw ServiceError.generic("Das Foto konnte nicht gelesen werden.")
                }

                let ext = pickerItem.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                try store.importPhoto(
                    bytes: bytes,
                    fileExtension: ext,
                    title: title,
                    note: note,
                    tags: parseTags(tags),
                    location: store.data.preferences.includeLocationForNewMedia ? location.lastLocation : nil
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            saving = false
        }
    }
}

struct ImportDocumentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var title = ""
    @State private var tags = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dokument") {
                    TextField("Titel (optional)", text: $title)
                    TextField("Tags, durch Komma getrennt", text: $tags)

                    Button("Datei auswählen", systemImage: "doc.badge.plus") {
                        showImporter = true
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Dokument importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .rtf, .data],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    try store.importDocument(from: url, title: title, tags: parseTags(tags))
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct AudioRecordingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorderService()

    @State private var currentURL: URL?
    @State private var title = ""
    @State private var tags = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 20)

                        Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 78))
                            .symbolRenderingMode(.hierarchical)

                        VStack(spacing: 5) {
                            Text(recorder.isRecording ? "Aufnahme läuft" : "Sprachaufzeichnung")
                                .font(.title2.bold())

                            Text(durationText(recorder.elapsed))
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        GlassCard {
                            VStack(spacing: 12) {
                                TextField("Titel", text: $title)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                                TextField("Tags, durch Komma getrennt", text: $tags)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                                PrimaryActionButton(
                                    title: recorder.isRecording ? "Aufnahme beenden" : "Aufnahme starten",
                                    icon: recorder.isRecording ? "stop.fill" : "record.circle"
                                ) {
                                    toggleRecording()
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        if recorder.isRecording {
                            _ = recorder.stop()
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            let duration = recorder.stop()
            if let currentURL {
                store.commitRecording(
                    url: currentURL,
                    duration: duration,
                    title: title,
                    tags: parseTags(tags)
                )
                dismiss()
            }
        } else {
            let url = store.newRecordingURL()
            currentURL = url

            Task {
                do {
                    try await recorder.start(url: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func durationText(_ value: TimeInterval) -> String {
        let total = Int(value)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private func parseTags(_ raw: String) -> [String] {
    raw
        .split(separator: ",")
        .map {
            $0
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
        }
        .filter { !$0.isEmpty }
}

