import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private let therapyContentMaxWidth: CGFloat = 720

private enum RootModal: Identifiable {
    case ai, permissions, session, checkIn(GuidedCheckIn), task(WeeklyTask), routine(UUID), showers, widgetSetup, routines, reminders, therapy, mood, energy
    var id: String {
        switch self {
        case .ai: "ai"; case .permissions: "permissions"; case .session: "session"
        case .checkIn(let entry): "check-in-" + entry.id.uuidString
        case .task(let task): "task-" + task.id.uuidString
        case .routine(let id): "routine-" + id.uuidString
        case .showers: "showers"; case .widgetSetup: "widget-setup"; case .routines: "routines"; case .reminders: "reminders"; case .therapy: "therapy"; case .mood: "mood"; case .energy: "energy"
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modal: RootModal?
    @State private var lastReminderRefresh = Date()
    @AppStorage("therapy.permissions3000") private var permissionSetupDone = false
    @State private var showPermissions = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.waitingForProtectedData {
                VStack(spacing: 16) {
                    ProgressView("Deine Daten werden geöffnet …")
                    Text("Nach dem Entsperren geht es automatisch weiter.").font(.subheadline).foregroundStyle(.secondary)
                }.padding()
            } else if store.loadError != nil {
                SettingsView()
            } else if store.data.profile.onboardingCompleted {
                if ProcessInfo.processInfo.arguments.contains("--show-routines") { NavigationStack { RoutineHubView() }.safeAreaInset(edge: .bottom) { UndoChangesButton() } } else { MainTabView() }
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Color.accentColor)
        .accessibilityIdentifier("therapy.root")
        .sheet(item: $modal, onDismiss: presentRequested) { modalContent($0) }
        .onOpenURL { url in
            guard url.scheme == "therapie" else { return }
            switch url.host {
            case "showers": store.notificationShowers = true
            case "widgetsetup": store.notificationWidgetSetup = true
            case "session": store.notificationSession = true
            case "today": store.selectedTab = 0
            case "archive": store.selectedTab = 3
            case "appointments": store.notificationTherapy = true
            case "routines": store.notificationRoutines = true
            case "reminders": store.notificationReminders = true
            case "routine": if let id = UUID(uuidString: url.lastPathComponent), store.data.routines.contains(where: { $0.id == id }) { store.notificationRoutineID = id } else { store.notificationRoutines = true }
            case "task": if let id = UUID(uuidString: url.lastPathComponent), store.data.weeklyTasks.contains(where: { $0.id == id }) { store.notificationTaskID = id } else { store.notificationReminders = true }
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.resumeProtectedStorage(); if store.storageReady { store.sessionController.synchronize(); store.consumeRoutineAlarmRoute(); store.refreshTherapyCalendar(force: false); TaskNotificationCoordinator.shared.refresh(store); TherapyWidgetBridge.refresh(store, force: true); presentRequested() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in store.resumeProtectedStorage(); presentRequested() }
        .onChange(of: store.waitingForProtectedData) { _, waiting in if !waiting { presentRequested() } }
        .onChange(of: presentationRequestKey) { _, _ in presentRequested() }
        .onAppear { presentRequested() }
        .task {
            store.resumeProtectedStorage()
            if store.storageReady { store.sessionController.synchronize(); store.refreshTherapyCalendar(force: false); store.consumeRoutineAlarmRoute() }
            if store.storageReady && modal == nil { await store.aiController.refreshWeeklyReview(); await store.aiController.refreshSuggestion() }
            while !Task.isCancelled {
                store.resumeProtectedStorage()
                if store.storageReady && scenePhase == .active { store.sessionController.reconcile(); store.consumeRoutineAlarmRoute(); presentRequested() }
                if Date().timeIntervalSince(lastReminderRefresh) >= 300 && store.storageReady && store.lastSaveError == nil {
                    lastReminderRefresh = Date()
                    store.pruneUndo()
                    TaskNotificationCoordinator.shared.refresh(store)
                    TherapyWidgetBridge.refresh(store)
                    if modal == nil { await store.aiController.refreshWeeklyReview(); await store.aiController.refreshSuggestion() }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .overlay { TherapyCelebrationOverlay() }
        .transaction { if reduceMotion { $0.animation = nil } }
        .task {
            if !permissionSetupDone && !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                showPermissions = true
            }
        }
        .safeAreaInset(edge: .top) {
            if let error = store.lastSaveError {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Daten nicht gespeichert", systemImage: "exclamationmark.triangle.fill").bold()
                    Text(error).font(.caption)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.18))
            }
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility2 : dynamicTypeSize)
        .overlay {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                GeometryReader { geometry in
                    Text("\(Int(geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing))x\(Int(geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom))")
                        .font(.system(size: 1))
                        .accessibilityIdentifier("therapy.viewport")
                        .allowsHitTesting(false)
                        .onChange(of: geometry.size, initial: true) { _, _ in
                            recordViewport(width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                                           height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                        }
                }
            }
        }
    }

    private func modalContent(_ route: RootModal) -> AnyView {
        switch route {
        case .ai: return AnyView(NavigationStack { AIBuddyView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { modal = nil }.disabled(!store.visibleAIComposerIDs.isEmpty || !store.activeBuddyVoiceIDs.isEmpty) } } }.interactiveDismissDisabled(!store.visibleAIComposerIDs.isEmpty || !store.activeBuddyVoiceIDs.isEmpty))
        case .permissions: return AnyView(PermissionSetupView())
        case .session: return AnyView(NavigationStack {
            SessionConductorView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { modal = nil }.disabled(!store.activeBuddyVoiceIDs.isEmpty) } }.interactiveDismissDisabled(!store.activeBuddyVoiceIDs.isEmpty)
                .sheet(item: $store.pendingGuidedCheckIn) { GuidedCheckInDestination(entry: $0) }
        })
        case .checkIn(let entry): return AnyView(GuidedCheckInDestination(entry: entry))
        case .task(let task): return AnyView(WeeklyTaskEditorView(task: task))
        case .routine(let id): return AnyView(RoutineDetailView(routineID: id))
        case .showers: return AnyView(NavigationStack { ShowerDaysView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { modal = nil } } } })
        case .widgetSetup: return AnyView(WidgetSetupHelpView())
        case .routines: return AnyView(NavigationStack { RoutineHubView() })
        case .reminders: return AnyView(NavigationStack { ReminderCenterView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { modal = nil } } } })
        case .therapy: return AnyView(TherapyAppointmentsView())
        case .mood: return AnyView(MoodEditorView())
        case .energy: return AnyView(WeeklyEnergyEditorView())
        }
    }
    private var presentationRequestKey: String {
        let flags = [showPermissions, store.notificationSession, store.notificationAIHub, store.notificationShowers, store.notificationWidgetSetup, store.notificationRoutines, store.notificationReminders, store.notificationTherapy, store.notificationMood, store.openEnergyReview]
        return flags.map { $0 ? "1" : "0" }.joined() + (store.pendingGuidedCheckIn?.id.uuidString ?? "") + (store.notificationTaskID?.uuidString ?? "") + (store.notificationRoutineID?.uuidString ?? "")
    }

    private func presentRequested() {
        // One stable presentation owner. Other requests wait for this sheet to close.
        guard modal == nil, store.storageReady, scenePhase == .active else { return }
        if showPermissions { showPermissions = false; modal = .permissions }
        else if store.notificationSession { store.notificationSession = false; modal = .session }
        else if let entry = store.pendingGuidedCheckIn { store.pendingGuidedCheckIn = nil; modal = .checkIn(entry) }
        else if store.notificationAIHub { store.notificationAIHub = false; modal = .ai }
        else if let id = store.notificationTaskID { store.notificationTaskID = nil; if let task = store.data.weeklyTasks.first(where: { $0.id == id }) { modal = .task(task) } }
        else if let id = store.notificationRoutineID { store.notificationRoutineID = nil; modal = .routine(id) }
        else if store.notificationShowers { store.notificationShowers = false; modal = .showers }
        else if store.notificationWidgetSetup { store.notificationWidgetSetup = false; modal = .widgetSetup }
        else if store.notificationRoutines { store.notificationRoutines = false; modal = .routines }
        else if store.notificationReminders { store.notificationReminders = false; modal = .reminders }
        else if store.notificationTherapy { store.notificationTherapy = false; modal = .therapy }
        else if store.notificationMood { store.notificationMood = false; modal = .mood }
        else if store.openEnergyReview { store.openEnergyReview = false; modal = .energy }
    }

    private func recordViewport(width: CGFloat, height: CGFloat) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
                .first(where: { $0.isKeyWindow }) else { return }
            let report: [String: Double] = [
                "viewportWidth": Double(width), "viewportHeight": Double(height),
                "windowWidth": Double(window.bounds.width), "windowHeight": Double(window.bounds.height),
                "nativeWidth": Double(window.screen.nativeBounds.width),
                "nativeHeight": Double(window.screen.nativeBounds.height),
                "nativeScale": Double(window.screen.nativeScale)
            ]
            if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                try? bytes.write(to: store.rootURL.appendingPathComponent("ui-viewport.json"), options: .atomic)
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
                LinearGradient(colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.05), .clear],
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
                            .strokeBorder(emphasized ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
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
    @State private var showBackup = false

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
                    Button("Vorhandene Sicherung importieren", systemImage: "square.and.arrow.down") { showBackup = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showBackup) { BackupCenterView() }
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
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            DashboardView()
                .safeAreaInset(edge: .bottom) { UndoChangesButton() }
                .tabItem { Label("Heute", systemImage: "sparkles") }
                .tag(0)

            InsightsHubView()
                .safeAreaInset(edge: .bottom) { UndoChangesButton() }
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                .tag(1)

            TherapyHubView()
                .safeAreaInset(edge: .bottom) { UndoChangesButton() }
                .tabItem { Label("Therapie", systemImage: "leaf") }
                .tag(2)

            LibraryView()
                .safeAreaInset(edge: .bottom) { UndoChangesButton() }
                .tabItem { Label("Archiv", systemImage: "square.stack.3d.up.fill") }
                .tag(3)

            SettingsView()
                .safeAreaInset(edge: .bottom) { UndoChangesButton() }
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNote = false
    @State private var showAI = false
    @State private var openedNoteFixture = false
    @State private var showEnergy = false
    @State private var showReflection = false
    @State private var customize = false
    @State private var routineToComplete: RoutineOccurrence?
    @State private var confirmRoutineCompletion = false

    private var currentTask: WeeklyTask? {
        let week = Date().therapyWeek
        let tasks = store.data.weeklyTasks.filter {
            $0.weekOfYear == week.week && $0.yearForWeekOfYear == week.year
        }
        return tasks.first { !$0.completed } ?? tasks.first
    }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                LazyVStack(spacing: store.data.dashboard.compactCards ? 10 : 18) {
                    if store.data.dashboard.welcomeFirst && store.data.dashboard.visibleCards.contains(.welcome) { PersonalWelcomeCard() }
                    if store.data.dashboard.showFeatureLinks { FeatureHubLinks() }
                    if store.data.dashboard.showAIImpulse && store.data.aiSettings.enabled && store.data.suggestionsEnabled != false { BuddySuggestionsCard(controller: store.aiController) }
                    ForEach(store.data.dashboard.visibleCards.filter { !(store.data.dashboard.welcomeFirst && $0 == .welcome) }) { card in
                        dashboardCard(card)
                            .contextMenu {
                                Button(store.data.dashboard.pinnedCards.contains(card.rawValue) ? "Karte lösen" : "Karte oben anpinnen", systemImage: "pin") {
                                    var preferences = store.data.dashboard
                                    if preferences.pinnedCards.contains(card.rawValue) { preferences.pinnedCards.removeAll { $0 == card.rawValue } }
                                    else { preferences.pinnedCards.append(card.rawValue) }
                                    store.data.dashboard = preferences
                                }
                                Button("Karte ausblenden", systemImage: "eye.slash") { store.data.dashboard.hiddenCards.append(card.rawValue) }
                                Button("Heute gestalten", systemImage: "slider.horizontal.3") { customize = true }
                            }
                    }
                    if store.data.dashboard.visibleCards.isEmpty {
                        ContentUnavailableView("Deine Heute-Seite", systemImage: "slider.horizontal.3", description: Text("Wähle deine Karten über „Heute gestalten“."))
                        Button("Heute gestalten") { customize = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $customize) { DashboardCustomizationView(preferences: store.data.dashboard) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavigationLink { EmergencyPlanView() } label: { Label("Notfallplan", systemImage: "lifepreserver.fill") } }
                ToolbarItem(placement: .topBarLeading) { Button("Heute gestalten", systemImage: "slider.horizontal.3") { customize = true }.accessibilityIdentifier("today.customize") }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.data.aiSettings.enabled { NavigationLink { AIBuddyView() } label: { Label("KI-Begleiter", systemImage: "sparkles") }.accessibilityIdentifier("today.ai") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { TasksView() } label: { Label("Aufgaben", systemImage: "checklist") }
                }
            }
            .onAppear { if !openedNoteFixture && ProcessInfo.processInfo.arguments.contains("--show-note") { openedNoteFixture = true; showNote = true } }
            .sheet(isPresented: $showAI) { AIBuddyEntryView() }
            .sheet(isPresented: $showNote) {
                AddNoteView()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showEnergy) {
                MoodEditorView()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showReflection) {
                AddReflectionView()
                    .presentationDetents([.medium, .large])
            }
            .alert("Routine wirklich erledigt?", isPresented: $confirmRoutineCompletion, presenting: routineToComplete) { occurrence in
                Button("Abbrechen", role: .cancel) { routineToComplete = nil }
                Button("Ja, ich habe sie erledigt") { store.resolveRoutine(occurrence, outcome: .done); routineToComplete = nil }
            } message: { occurrence in
                Text("Bestätige nur, wenn du „\(store.data.routines.first { $0.id == occurrence.routineID }?.title ?? "diese Routine")“ wirklich abgeschlossen hast.")
            }
        }
    }

    @ViewBuilder private func dashboardCard(_ card: HomeCard) -> some View {
        switch card {
        case .showers: ShowerTodayCard()
        case .methods: MethodsHomeCard()
        case .appointment: TherapyAppointmentCard()
        case .discussion: TherapyDiscussionCard()
        case .checkIns: CompanionTodayCard()
        case .routines: TodayRoutinesCard { occurrence in routineToComplete = occurrence; confirmRoutineCompletion = true }
        case .overview: TodayOverviewCard()
        case .quickActions: quickActions
        case .session: TodaySessionCard()
        case .pinned: PinnedArchiveCard()
        case .wellness: WellnessProgressCard()
        case .therapy: TherapyTodayCard()
        case .week: WeekOverviewCard()
        case .task: WeeklyTasksHomeCard()
        case .latest: latestCard
        case .reminders: TodayRemindersCard()
        case .goals: TodayGoalsCard()
        case .welcome: PersonalWelcomeCard()
        }
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
                if store.data.aiSettings.enabled { QuickActionButton(title: "Mit KI", subtitle: "Gemeinsam festhalten", icon: "sparkles") { showAI = true } }
                QuickActionButton(title: "Notiz", subtitle: "Gedanken", icon: "square.and.pencil") {
                    showNote = true
                }
                QuickActionButton(title: "Stimmung", subtitle: "Check-in", icon: "face.smiling") {
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
                        store.toggleTask(store.data.weeklyTasks[index].id)
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
                    ForEach(Array(store.data.notes.sorted { $0.createdAt > $1.createdAt }.prefix(3))) { note in
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
                .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
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
        !TherapyDateHelper.appointments(on: selectedDate, schedule: store.data.schedule, includeExcluded: true).isEmpty
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
    private var dayMoods: [MoodCheckIn] {
        store.data.moodCheckIns.filter { $0.date.isSameTherapyDay(as: selectedDate) }
    }
    private var dayPoints: [BatteryPoint] {
        store.data.batteryPoints.filter { $0.date.isSameTherapyDay(as: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    TherapyAppointmentCard()
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
                        Text(therapyDayLabel)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if dayNotes.isEmpty && dayMedia.isEmpty && dayEnergy.isEmpty && dayMoods.isEmpty && dayPoints.isEmpty && !therapyWeekdayMatch {
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
                        if !dayMoods.isEmpty { DayCountTile(title: "Check-ins", count: dayMoods.count, icon: "face.smiling") }
                        if !dayPoints.isEmpty { DayCountTile(title: "Akku-Punkte", count: dayPoints.count, icon: "battery.100percent") }
                    }
                }
                ForEach(dayMoods.sorted { $0.date > $1.date }) { entry in
                    Text("\(entry.face) \(entry.moodTitle) · Akku \(entry.battery)/5").font(.subheadline)
                }
                ForEach(dayPoints.sorted { $0.date > $1.date }) { point in
                    Label(point.title, systemImage: point.direction.symbol).font(.subheadline).foregroundStyle(point.direction == .gives ? .teal : .orange)
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

    private var therapyDayLabel: String {
        let dates = TherapyDateHelper.appointments(on: selectedDate, schedule: store.data.schedule, includeExcluded: true)
        let labels = dates.map { date -> String in
            let time = date.formatted(date: .omitted, time: .shortened)
            if TherapyDateHelper.cancellation(schedule: store.data.schedule, on: date) != nil { return time + " · abgesagt" }
            if TherapyDateHelper.vacation(schedule: store.data.schedule, at: date) != nil { return time + " · Pause" }
            return time
        }
        return "Therapietag · " + labels.joined(separator: ", ")
    }
    private func syncEverything() {
        syncing = true; statusMessage = nil
        Task { @MainActor in
            do {
                let id = try await CalendarSyncService.shared.sync(schedule: store.data.schedule, profile: store.data.profile)
                store.data.schedule.calendarEventIdentifier = id
                statusMessage = "Kalender synchronisiert · 26 kommende Termine."
            } catch { statusMessage = "Kalender: " + error.localizedDescription }
            store.data.schedule.therapyAlarmsEnabled = true
            await RoutineAlarmCoordinator.shared.requestAccess(store)
            statusMessage = (statusMessage ?? "") + "\n" + store.routineAlarmStatus
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
    @State private var taskDraft: WeeklyTask?
    @State private var taskToDelete: UUID?
    @State private var confirmDelete = false
    @State private var onlyOpen = false
    @State private var taskLimit = 40
    @State private var weekScope = "current"
    private var filteredTasks: [WeeklyTask] {
        let current = Date().therapyWeek
        return store.data.weeklyTasks.filter { task in
            (!onlyOpen || !task.completed) && (weekScope == "all" || (weekScope == "current" ? task.weekOfYear == current.week && task.yearForWeekOfYear == current.year : task.weekOfYear != current.week || task.yearForWeekOfYear != current.year))
        }.sorted { ($0.dueDate ?? $0.createdAt) < ($1.dueDate ?? $1.createdAt) }
    }
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink { ReminderCenterView() } label: { Label("Aufgabenerinnerungen einstellen", systemImage: "bell.badge") }
                            if !store.taskReminderStatus.isEmpty { Text(store.taskReminderStatus).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    NavigationLink { TodoTimelineView() } label: { Label("Gemeinsame To-do-Timeline", systemImage: "calendar.day.timeline.left") }
                    Picker("Wochen", selection: $weekScope) { Text("Diese Woche").tag("current"); Text("Andere Wochen").tag("other"); Text("Alle").tag("all") }.pickerStyle(.segmented)
                    Text("\(filteredTasks.count) Aufgaben · mehrere Aufgaben pro Woche möglich").font(.caption).foregroundStyle(.secondary)
                    Toggle("Nur offene Aufgaben", isOn: $onlyOpen)
                        .padding(.horizontal, 4)
                    if filteredTasks.isEmpty && !store.data.weeklyTasks.isEmpty { Text("Keine Aufgaben im gewählten Filter. Unter Alle findest du auch andere Wochen.").font(.subheadline).foregroundStyle(.secondary) }
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
                        ForEach(Array(filteredTasks.prefix(taskLimit))) { task in
                            if !onlyOpen || !task.completed {
                                taskCard(task: identifiedEditorBinding($store.data.weeklyTasks, to: task))
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if filteredTasks.count > taskLimit { Button("Weitere 40 Aufgaben") { taskLimit += 40 }.buttonStyle(.bordered).padding(8).background(.regularMaterial) } }
            .onChange(of: weekScope) { _, _ in taskLimit = 40 }
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
            .sheet(item: $taskDraft) { WeeklyTaskEditorView(task: $0) }
            .alert("Wochenaufgabe löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) { store.data.weeklyTasks.removeAll { $0.id == taskToDelete } }
            } message: { Text("Diese Aufgabe wird endgültig gelöscht.") }
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
                        store.toggleTask(task.wrappedValue.id)
                    } label: {
                        Image(systemName: task.wrappedValue.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.wrappedValue.completed ? "Als offen markieren" : "Als erledigt markieren")

                    Menu {
                        Button("Aufgabe bearbeiten", systemImage: "pencil") { taskDraft = task.wrappedValue }
                        Button(task.wrappedValue.completed ? "Wieder aufnehmen" : "Als erledigt markieren", systemImage: "checkmark.circle") { store.toggleTask(task.wrappedValue.id) }
                        if !task.wrappedValue.completed {
                            Button("Eine Stunde später erinnern", systemImage: "clock") { store.postponeTask(task.wrappedValue.id, minutes: 60) }
                            Button("Morgen erinnern", systemImage: "sunrise") { store.postponeTask(task.wrappedValue.id, minutes: 1440) }
                        }
                        Button(role: .destructive) {
                            taskToDelete = task.wrappedValue.id
                            confirmDelete = true
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
                if let step = task.wrappedValue.smallStep, !step.isEmpty { Label(step, systemImage: "figure.walk").font(.subheadline) }
                if let progress = task.wrappedValue.progress { ProgressView(value: Double(progress), total: 100) { Text("\(progress) % geschafft").font(.caption) } }
                if let due = task.wrappedValue.dueDate { Label("Ziel: " + due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                if let shifted = task.wrappedValue.reminderShiftedAt { Text("Verschoben: " + shifted.formatted(date: .abbreviated, time: .shortened) + ". Die regelmäßige Uhrzeit wurde angepasst.").font(.caption).foregroundStyle(.secondary) }
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
    @State private var mediaToDelete: MediaItem?
    @State private var noteToDelete: UUID?
    @State private var energyToDelete: UUID?
    @State private var confirmDelete = false
    @State private var searchText = ""
    @EnvironmentObject private var store: AppStore
    @State private var section: LibrarySection = .timeline
    @State private var showPhoto = false
    @State private var showAudio = false
    @State private var showNote = false
    @State private var showDocument = false
    @State private var viewingMedia: MediaItem?

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
            .alert("Eintrag endgültig löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) { mediaToDelete = nil; noteToDelete = nil; energyToDelete = nil }
                Button("Löschen", role: .destructive) {
                    if let item = mediaToDelete { store.deleteMedia(item) }
                    if let id = noteToDelete { store.data.notes.removeAll { $0.id == id } }
                    if let id = energyToDelete { store.data.energyEntries.removeAll { $0.id == id } }
                    mediaToDelete = nil; noteToDelete = nil; energyToDelete = nil
                }
            } message: { Text("Der Eintrag und gegebenenfalls seine lokale Datei werden gelöscht. Das kann nicht rückgängig gemacht werden.") }
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
            .sheet(item: $viewingMedia) { TherapyMediaDetailView(itemID: $0.id) }
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
                    .presentationDetents([.large])
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
                        Button { viewingMedia = item } label: { MediaAttachmentThumbnail(item: item) }.buttonStyle(.plain).accessibilityLabel(item.title + " öffnen")

                        VStack(alignment: .leading, spacing: 5) {
                            Button(item.title) { viewingMedia = item }.font(.headline).multilineTextAlignment(.leading)
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
                                mediaToDelete = item
                                confirmDelete = true
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
        TherapyNotesCollectionView(searchText: searchText)
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
                            Label(entry.percent.map { "Akku \($0) %" } ?? "Energie \(entry.level)/5", systemImage: "bolt.heart.fill")
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
                        Button("Energie-Check löschen", systemImage: "trash", role: .destructive) { energyToDelete = entry.id; confirmDelete = true }
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func matches(_ values: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.contains { $0.localizedStandardContains(query) }
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
    var body: some View { TherapyEditableTimeline(searchText: searchText) }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showFolderPicker = false
    @State private var statusMessage: String?
    @State private var deletePhrase = ""
    @State private var showDeleteDialog = false
    @State private var showRestoreDialog = false
    @State private var showBackupCenter = false

    private let deleteConfirmation = "ALLE THERAPIEDATEN LÖSCHEN"

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    profileCard
                    GlassCard { NavigationLink { BuddyWellbeingProfileView() } label: { Label("Mein aktueller Akku & Befinden", systemImage: "heart.text.clipboard") } }
                    AppearanceCard()
                    HomeAndWidgetSettingsCard()
                    AIBuddySettingsCard()
                    NavigationLink { EditorDraftListView() } label: { Label("Meine Entwürfe (\(store.data.editorDrafts.count))", systemImage: "square.and.pencil") }
                    GlassCard {
                        NavigationLink { WellnessSettingsView() } label: {
                            Label("Stimmung: Ziele, Erinnerungen & Freigaben", systemImage: "heart.text.clipboard")
                        }
                    }
                    scheduleCard
                    reminderCard
                    GlassCard { NavigationLink { ReminderCenterView() } label: { Label("Aufgaben- & Wochenenergie-Erinnerungen", systemImage: "bell.badge") } }
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Vollständige Datensicherung", icon: "lock.doc.fill", subtitle: "Passwortsicherung oder lesbares ZIP – mit oder ohne Bilder.")
                            Text("Alle Einträge und Einstellungen exportieren, in Dateien sichern und später auf diesem oder einem anderen iPhone wiederherstellen.").font(.subheadline).foregroundStyle(.secondary)
                            Button { showBackupCenter = true } label: { Label("Export & Import öffnen", systemImage: "externaldrive").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        }
                    }
                    backupCard
                    privacyCard
                    dangerCard
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showBackupCenter) { BackupCenterView() }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    try BackupService.shared.selectFolder(url)
                    if store.loadError == nil {
                        try store.backupNow()
                        statusMessage = "Backup-Ordner verbunden und erste Sicherung erstellt."
                    } else {
                        statusMessage = "Backup-Ordner verbunden. Bitte stelle deine Daten mit Wiederherstellen wieder her; das vorhandene Backup wurde nicht überschrieben."
                    }
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
                    TherapySessionController.endAll()
                    WeeklyReminderService.cancel()
                    BackupService.shared.clearFolder()
                    store.resetAllData()
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
                TextField("Ort / Praxis", text: Binding(get: { store.data.schedule.location ?? "" }, set: { store.data.schedule.location = $0 }))
                TextField("Vorbereitung / mitbringen", text: Binding(get: { store.data.schedule.preparation ?? "" }, set: { store.data.schedule.preparation = $0 }), axis: .vertical).lineLimit(2...6)
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

                    WeekdaySelection(days: $store.data.schedule.taskReminderWeekdays)
                    Text("Für ältere Aufgaben ohne eigene Einstellung. Neue Aufgaben können eigene Tage und Zeiten erhalten.")
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
                    title: "Automatische Ordnersicherung",
                    icon: "icloud.and.arrow.up.fill",
                    subtitle: "Zusätzliche Sicherung ohne Passwortverschlüsselung."
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
    var body: some View { WeeklyTaskEditorView() }
}

struct AddNoteView: View {
    @State private var draft = TherapyNote(title: "", text: "", tags: [])
    var body: some View { TherapyNoteEditorView(note: draft) }
}

struct AddEnergyView: View {
    @State private var draft = EnergyEntry(level: 3, givesEnergy: "", takesEnergy: "", note: "")
    var body: some View { LegacyEnergyEditorView(entry: draft) }
}

struct AddReflectionView: View {
    var body: some View { TherapyReflectionEditorView() }
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

    var onSaved: ((UUID) -> Void)? = nil
    @State private var currentURL: URL?
    @State private var starting = false
    @State private var startTask: Task<Void, Never>?
    @State private var saved = false
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
                                }.disabled(starting).accessibilityIdentifier("audio.record.toggle")
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
            .accessibilityIdentifier("audio.recorder")
            .interactiveDismissDisabled(recorder.isRecording || starting)
            .onDisappear { startTask?.cancel(); if recorder.isRecording { _ = recorder.stop() }; if !saved, let currentURL, !store.data.media.contains(where: { $0.relativePath == "Recordings/" + currentURL.lastPathComponent }) { try? FileManager.default.removeItem(at: currentURL) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        if recorder.isRecording {
                            _ = recorder.stop()
                        }
                        dismiss()
                    }.disabled(starting).accessibilityIdentifier("audio.record.close")
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
                if let failure = store.lastSaveError { errorMessage = failure; return }
                if let item = store.data.media.first(where: { $0.relativePath == "Recordings/" + currentURL.lastPathComponent }) { saved = true; onSaved?(item.id); dismiss() }
                else { errorMessage = "Die Aufnahme konnte nicht gespeichert werden." }
            }
        } else {
            let url = store.newRecordingURL()
            currentURL = url

            starting = true
            startTask = Task { @MainActor in
                defer { starting = false }
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
