import SwiftUI

// MARK: - Therapie 5 navigation
//
// Four calm tabs (Heute, Therapie, Alltag, Verlauf) plus the system search tab. Every feature of the app is
// listed once in `TherapyFeature.catalog`, so the search tab, the hub grids and the AI share one directory and
// nothing is buried in settings. Profile & settings open from the avatar button on every tab.

/// Tab identities. 0–4 keep the meaning they had before Therapie 5, because deep links, widgets and
/// notification routes still select them.
enum TherapyTab {
    static let today = 0
    static let therapy = 2
    static let history = 3
    static let everyday = 6
    static let search = 7
}

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab("Heute", systemImage: "sun.max.fill", value: TherapyTab.today) {
                DashboardView()
                    .safeAreaInset(edge: .bottom) { UndoChangesButton() }
            }
            Tab("Therapie", systemImage: "leaf.fill", value: TherapyTab.therapy) {
                NavigationStack { TherapyHubView().therapyRootToolbar() }
                    .safeAreaInset(edge: .bottom) { UndoChangesButton() }
            }
            Tab("Alltag", systemImage: "figure.mind.and.body", value: TherapyTab.everyday) {
                NavigationStack { EverydayHubView().therapyRootToolbar() }
                    .safeAreaInset(edge: .bottom) { UndoChangesButton() }
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: TherapyTab.history) {
                NavigationStack { HistoryHubView().therapyRootToolbar() }
                    .safeAreaInset(edge: .bottom) { UndoChangesButton() }
            }
            Tab("Suche", systemImage: "magnifyingglass", value: TherapyTab.search, role: .search) {
                NavigationStack { TherapySearchView() }
                    .safeAreaInset(edge: .bottom) { UndoChangesButton() }
            }
        }
        .tabBarMinimizeBehavior(TherapyDesign.isUITesting ? .never : .onScrollDown)
        .tabViewBottomAccessory(isEnabled: store.data.currentSession != nil) { SessionMiniPlayer() }
        .onAppear { if ![TherapyTab.today, TherapyTab.therapy, TherapyTab.history, TherapyTab.everyday, TherapyTab.search].contains(store.selectedTab) { store.selectedTab = TherapyTab.today } }
    }
}

// MARK: - Profile access

extension View {
    /// Adds the avatar button that opens profile & settings on a tab's root page.
    func therapyRootToolbar() -> some View { modifier(TherapyRootToolbar()) }
}

private struct TherapyRootToolbar: ViewModifier {
    @State private var showProfile = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton { showProfile = true }
                }
            }
            .sheet(isPresented: $showProfile) { SettingsView(showsCloseButton: true) }
    }
}

struct ProfileAvatarButton: View {
    @EnvironmentObject private var store: AppStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(initials)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.gradient, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.8) }
        }
        .accessibilityLabel("Profil & Einstellungen")
        .accessibilityIdentifier("profile.open")
    }

    private var initials: String {
        let name = store.data.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
        return letters.isEmpty ? "ICH" : letters
    }
}

// MARK: - Running session mini player

/// Shown above the tab bar while a therapy session runs, like a music mini player. Tapping opens the session.
struct SessionMiniPlayer: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if let session = store.data.currentSession {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 10) {
                    Button { store.notificationSession = true } label: { summary(session, now: context.date) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Öffnet die laufende Therapiestunde")
                    Button { store.sessionController.pauseOrResume() } label: {
                        Image(systemName: session.pausedAt == nil ? "pause.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.pausedAt == nil ? "Pausieren" : "Fortsetzen")
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func summary(_ session: RunningTherapySession, now: Date) -> some View {
        let total = max(1, session.totalSeconds)
        let progress = min(1, session.elapsed(at: now) / total)
        let remaining = Int(session.remaining(at: now))
        let phase = session.phaseIndex(at: now).map { session.phases[$0].title } ?? session.title
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.teal.opacity(0.22), lineWidth: 3.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: session.pausedAt == nil ? "leaf.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.teal)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(phase).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(session.pausedAt == nil ? "Therapiestunde läuft" : "Pausiert").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feature directory

/// One entry per app area. Push destinations live in the current navigation stack; sheet destinations bring
/// their own stack (editors, wizards and settings that already had one).
struct TherapyFeature: Identifiable {
    enum Area: String, CaseIterable, Identifiable {
        case therapy, everyday, support, capture, history, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .therapy: "Therapie"
            case .everyday: "Alltag planen"
            case .support: "Wenn es schwer wird"
            case .capture: "Festhalten"
            case .history: "Rückblick"
            case .settings: "Profil & Daten"
            }
        }
        var icon: String {
            switch self {
            case .therapy: "leaf.fill"
            case .everyday: "calendar.day.timeline.left"
            case .support: "lifepreserver.fill"
            case .capture: "square.and.pencil"
            case .history: "clock.arrow.circlepath"
            case .settings: "person.crop.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .therapy: .green
            case .everyday: .orange
            case .support: .red
            case .capture: .blue
            case .history: .purple
            case .settings: .gray
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let area: Area
    var keywords = ""
    var opensAsSheet = false
    var requiresAI = false

    func matches(_ query: String) -> Bool {
        let text = [title, subtitle, keywords, area.title].joined(separator: " ")
        return query.split(separator: " ").allSatisfy { text.localizedStandardContains(String($0)) }
    }

    static func available(_ data: AppData) -> [TherapyFeature] {
        catalog.filter { !$0.requiresAI || data.aiSettings.enabled }
    }
    static func features(_ ids: [String], data: AppData) -> [TherapyFeature] {
        let available = available(data)
        return ids.compactMap { id in available.first { $0.id == id } }
    }

    static let catalog: [TherapyFeature] = [
        // Therapie
        TherapyFeature(id: "session", title: "Therapiestunde", subtitle: "Timer, Abschnitte, Notizen", icon: "timer", tint: .teal, area: .therapy, keywords: "stunde timer live aktivität dynamic island begleiten vorlage"),
        TherapyFeature(id: "appointments", title: "Termine", subtitle: "Rhythmus, Absagen, Urlaub", icon: "calendar.badge.clock", tint: .indigo, area: .therapy, keywords: "termin absage zusatztermin urlaub pause intervall", opensAsSheet: true),
        TherapyFeature(id: "calendar", title: "Kalender", subtitle: "Tage und Einträge", icon: "calendar", tint: .blue, area: .therapy, keywords: "monat tag datum"),
        TherapyFeature(id: "therapy", title: "Themen & Ziele", subtitle: "Ordner, Materialien", icon: "leaf.fill", tint: .green, area: .therapy, keywords: "thema ziel ordner material therapeutin wichtig"),
        TherapyFeature(id: "tasks", title: "Wochenaufgaben", subtitle: "Aufgaben dieser Woche", icon: "checklist", tint: .orange, area: .therapy, keywords: "aufgabe to-do hausaufgabe woche"),
        TherapyFeature(id: "timeline", title: "To-do-Timeline", subtitle: "Alles nach Datum", icon: "calendar.day.timeline.left", tint: .cyan, area: .therapy, keywords: "timeline aufgaben termine routinen"),
        TherapyFeature(id: "medicalpass", title: "Therapiepass", subtitle: "Medikamente, Kontakte", icon: "person.text.rectangle.fill", tint: .teal, area: .therapy, keywords: "pass medikament kontakt arzt körper"),
        TherapyFeature(id: "weeklyReport", title: "Wochenbericht", subtitle: "PDF für die Stunde", icon: "printer.fill", tint: .gray, area: .therapy, keywords: "pdf drucken bericht teilen", opensAsSheet: true),
        TherapyFeature(id: "sessionSettings", title: "Timer & Live-Aktivität", subtitle: "Dynamic Island, Hinweise", icon: "timer.circle.fill", tint: .mint, area: .therapy, keywords: "dynamic island sperrbildschirm live aktivität mitteilung timer"),
        // Alltag
        TherapyFeature(id: "routines", title: "Routinen", subtitle: "Abläufe & Erinnerungen", icon: "repeat", tint: .green, area: .everyday, keywords: "routine gewohnheit tablette medikament erinnerung"),
        TherapyFeature(id: "showers", title: "Duschtage", subtitle: "Ziel & Woche", icon: "shower.fill", tint: .cyan, area: .everyday, keywords: "duschen hygiene"),
        TherapyFeature(id: "alarms", title: "Wecker", subtitle: "Aufstehen & Aufgaben", icon: "alarm.fill", tint: .orange, area: .everyday, keywords: "wecker alarm aufstehen schlummern alarmkit"),
        TherapyFeature(id: "reminders", title: "Erinnerungen", subtitle: "Aufgaben & Energie", icon: "bell.badge.fill", tint: .red, area: .everyday, keywords: "erinnerung mitteilung benachrichtigung"),
        TherapyFeature(id: "routineHistory", title: "Routinen-Verlauf", subtitle: "Erledigt & korrigiert", icon: "clock.badge.checkmark", tint: .purple, area: .everyday, keywords: "verlauf korrektur erledigt ausgelassen", opensAsSheet: true),
        TherapyFeature(id: "checkins", title: "Check-in-Zeiten", subtitle: "Tagesfenster", icon: "sun.horizon.fill", tint: .yellow, area: .everyday, keywords: "check-in morgens mittags abends nachts fenster", opensAsSheet: true),
        // Wenn es schwer wird
        TherapyFeature(id: "emergency", title: "Notfallplan", subtitle: "Erste Schritte & Hilfe", icon: "lifepreserver.fill", tint: .red, area: .support, keywords: "notfall krise hilfe warnsignal unterstützung"),
        TherapyFeature(id: "grounding", title: "5-4-3-2-1", subtitle: "Angeleitete Erdung", icon: "hand.raised.fill", tint: .mint, area: .support, keywords: "erdung grounding übung beruhigen sinne"),
        TherapyFeature(id: "methods", title: "Methoden", subtitle: "Skills & Gedankenstopps", icon: "wand.and.stars", tint: .purple, area: .support, keywords: "methode skill gedankenstopp asmr beruhigen akku"),
        TherapyFeature(id: "groundingHistory", title: "Meine Übungen", subtitle: "Erdungen im Verlauf", icon: "list.bullet.clipboard.fill", tint: .teal, area: .support, keywords: "übung verlauf grounding"),
        TherapyFeature(id: "ai", title: "KI-Begleiter", subtitle: "Gemeinsam sortieren", icon: "sparkles", tint: .indigo, area: .support, keywords: "ki chat begleiter gespräch assistent", requiresAI: true),
        // Festhalten
        TherapyFeature(id: "note", title: "Notiz", subtitle: "Gedanken festhalten", icon: "square.and.pencil", tint: .orange, area: .capture, keywords: "notiz tagebuch gedanke schreiben", opensAsSheet: true),
        TherapyFeature(id: "mood", title: "Stimmung", subtitle: "Check-in & Akku", icon: "face.smiling.inverse", tint: .yellow, area: .capture, keywords: "stimmung gefühl akku energie befinden", opensAsSheet: true),
        TherapyFeature(id: "reflection", title: "Stunden-Rückblick", subtitle: "Nach der Therapie", icon: "text.bubble.fill", tint: .blue, area: .capture, keywords: "rückblick reflexion stunde", opensAsSheet: true),
        TherapyFeature(id: "photo", title: "Foto", subtitle: "Bild mit Notiz", icon: "camera.fill", tint: .pink, area: .capture, keywords: "foto bild kamera", opensAsSheet: true),
        TherapyFeature(id: "audio", title: "Sprachnotiz", subtitle: "Aufnehmen", icon: "mic.fill", tint: .red, area: .capture, keywords: "audio sprache aufnahme mikrofon", opensAsSheet: true),
        TherapyFeature(id: "document", title: "Dokument", subtitle: "PDF oder Text", icon: "doc.badge.plus", tint: .gray, area: .capture, keywords: "dokument pdf datei import", opensAsSheet: true),
        TherapyFeature(id: "weekReview", title: "Wochenrückblick", subtitle: "Woche abschließen", icon: "calendar.badge.checkmark", tint: .indigo, area: .capture, keywords: "woche rückblick", opensAsSheet: true),
        TherapyFeature(id: "weeklyEnergy", title: "Wochenenergie", subtitle: "Akku der Woche", icon: "bolt.heart.fill", tint: .green, area: .capture, keywords: "energie akku woche", opensAsSheet: true),
        TherapyFeature(id: "capture", title: "Alle Eintragsarten", subtitle: "Check-ins & mehr", icon: "plus.square.on.square", tint: .teal, area: .capture, keywords: "neu eintrag erfassen check-in", opensAsSheet: true),
        // Rückblick
        TherapyFeature(id: "archive", title: "Archiv", subtitle: "Notizen & Medien", icon: "archivebox.fill", tint: .brown, area: .history, keywords: "archiv suchen notizen medien fotos audio"),
        TherapyFeature(id: "insights", title: "Auswertung", subtitle: "Stimmung & Akku-Trends", icon: "chart.xyaxis.line", tint: .pink, area: .history, keywords: "insights statistik trend diagramm"),
        TherapyFeature(id: "wellnessEntries", title: "Stimmungseinträge", subtitle: "Alle Check-ins", icon: "list.bullet.rectangle.fill", tint: .orange, area: .history, keywords: "stimmung einträge liste akku punkte", opensAsSheet: true),
        TherapyFeature(id: "entryMap", title: "Eintragskarte", subtitle: "Orte deiner Einträge", icon: "map.fill", tint: .green, area: .history, keywords: "karte standort ort"),
        TherapyFeature(id: "drafts", title: "Entwürfe", subtitle: "Gespeicherte Entwürfe", icon: "doc.on.clipboard.fill", tint: .gray, area: .history, keywords: "entwurf draft"),
        // Profil & Daten
        TherapyFeature(id: "settings", title: "Profil & Einstellungen", subtitle: "Alles an einem Ort", icon: "person.crop.circle.fill", tint: .indigo, area: .settings, keywords: "profil einstellungen name therapeut", opensAsSheet: true),
        TherapyFeature(id: "profile", title: "Akku & Befinden", subtitle: "Mein Befinden", icon: "heart.text.clipboard.fill", tint: .pink, area: .settings, keywords: "befinden akku profil"),
        TherapyFeature(id: "appearance", title: "Darstellung", subtitle: "Farbe, Hell/Dunkel", icon: "paintpalette.fill", tint: .purple, area: .settings, keywords: "design farbe dunkel hell haptik konfetti"),
        TherapyFeature(id: "dashboard", title: "Heute gestalten", subtitle: "Karten & Reihenfolge", icon: "slider.horizontal.3", tint: .teal, area: .settings, keywords: "startseite karten anpassen", opensAsSheet: true),
        TherapyFeature(id: "widgets", title: "Widgets", subtitle: "Einrichten & Diagnose", icon: "square.grid.2x2.fill", tint: .blue, area: .settings, keywords: "widget home bildschirm", opensAsSheet: true),
        TherapyFeature(id: "wellness", title: "Stimmungsziele", subtitle: "Ziele & Freigaben", icon: "target", tint: .yellow, area: .settings, keywords: "ziel stimmung freigabe"),
        TherapyFeature(id: "apple", title: "Apple & Siri", subtitle: "Erinnerungen, Home, Kurzbefehle", icon: "apple.logo", tint: .gray, area: .settings, keywords: "apple siri kurzbefehle home erinnerungen"),
        TherapyFeature(id: "backup", title: "Sicherung", subtitle: "Export & Import", icon: "lock.doc.fill", tint: .blue, area: .settings, keywords: "backup sicherung export import zip passwort", opensAsSheet: true),
        TherapyFeature(id: "aiSettings", title: "KI-Einstellungen", subtitle: "Schlüssel, Modell, Denktiefe", icon: "key.fill", tint: .indigo, area: .settings, keywords: "ki openai schlüssel modell api", opensAsSheet: true)
    ]
}

/// The view behind each directory entry.
struct TherapyFeatureDestination: View {
    @EnvironmentObject private var store: AppStore
    let id: String

    var body: some View {
        switch id {
        case "session": SessionConductorView()
        case "appointments": TherapyAppointmentsView()
        case "calendar": TherapyCalendarView()
        case "therapy": TherapyHubView()
        case "tasks": TasksView()
        case "timeline": TodoTimelineView()
        case "medicalpass": MedicalPassView()
        case "weeklyReport": WeeklyPDFReportView()
        case "sessionSettings": SessionPreferencesView(controller: store.sessionController)
        case "routines": RoutineHubView()
        case "showers": ShowerDaysView()
        case "alarms": WakeAlarmHubView()
        case "reminders": ReminderCenterView()
        case "routineHistory": RoutineHistoryView()
        case "checkins": DayCheckInSettingsView(slots: DayCheckInPolicy.slots(store.data.companionSettings))
        case "emergency": EmergencyPlanView()
        case "grounding": GroundingExerciseView()
        case "methods": MethodsHubView()
        case "groundingHistory": GroundingHistoryView()
        case "ai": AIBuddyView()
        case "note": AddNoteView()
        case "mood": MoodEditorView()
        case "reflection": AddReflectionView()
        case "photo": AddPhotoView()
        case "audio": AudioRecordingView()
        case "document": ImportDocumentView()
        case "weekReview": WeekReviewEditorView(review: currentWeekReview)
        case "weeklyEnergy": WeeklyEnergyEditorView()
        case "capture": EntryHubView()
        case "archive": LibraryView()
        case "insights": InsightsHubView()
        case "wellnessEntries": WellnessHubView()
        case "entryMap": EntryMapView()
        case "drafts": EditorDraftListView()
        case "settings": SettingsView(showsCloseButton: true)
        case "profile": BuddyWellbeingProfileView()
        case "appearance": TherapySettingsPage(title: "Darstellung") { AppearanceCard() }
        case "dashboard": DashboardCustomizationView(preferences: store.data.dashboard)
        case "widgets": WidgetSetupHelpView()
        case "wellness": WellnessSettingsView()
        case "apple": AppleIntegrationView()
        case "backup": BackupCenterView()
        case "aiSettings": AIBuddySettingsView()
        default: ContentUnavailableView("Bereich nicht gefunden", systemImage: "questionmark.circle")
        }
    }

    private var currentWeekReview: WeekReview {
        store.data.weekReviews.first { Calendar.therapyCalendar.isDate($0.weekStart, equalTo: Date(), toGranularity: .weekOfYear) } ?? WeekReview(weekStart: Date().therapyWeekStart)
    }
}

/// A tile for one feature. Push features navigate, sheet features call `presentSheet`.
struct FeatureTile: View {
    let feature: TherapyFeature
    var compact = false
    let presentSheet: (TherapyFeature) -> Void

    var body: some View {
        if feature.opensAsSheet {
            Button { TherapyEffects.shared.light(); presentSheet(feature) } label: { label }
                .buttonStyle(TherapyPressStyle())
                .therapyGlass(in: shape, interactive: true)
                .accessibilityIdentifier("feature." + feature.id)
        } else {
            NavigationLink { TherapyFeatureDestination(id: feature.id) } label: { label }
                .buttonStyle(TherapyPressStyle())
                .therapyGlass(in: shape, interactive: true)
                .accessibilityIdentifier("feature." + feature.id)
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TherapyDesign.tileRadius, style: .continuous) }

    @ViewBuilder private var label: some View {
        if compact {
            VStack(spacing: 8) {
                TherapyIconTile(icon: feature.icon, size: 40, tint: feature.tint)
                Text(feature.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(shape)
        } else {
            HStack(spacing: 12) {
                TherapyIconTile(icon: feature.icon, size: 38, tint: feature.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(feature.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(12)
            .contentShape(shape)
        }
    }
}

/// A titled grid of feature tiles.
struct FeatureGridSection: View {
    let title: String
    let icon: String
    var tint: Color = .accentColor
    let features: [TherapyFeature]
    var compact = false
    let presentSheet: (TherapyFeature) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.system(.headline, design: .rounded))
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 96 : 150), spacing: 10)], spacing: 10) {
                ForEach(features) { feature in
                    FeatureTile(feature: feature, compact: compact, presentSheet: presentSheet)
                }
            }
        }
    }
}

// MARK: - Search tab

struct TherapySearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var sheet: TherapyFeature?
    @State private var editing: ArchiveRecord?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var features: [TherapyFeature] {
        let all = TherapyFeature.available(store.data)
        return trimmed.isEmpty ? all : all.filter { $0.matches(trimmed) }
    }
    private var records: [ArchiveRecord] {
        guard trimmed.count >= 2 else { return [] }
        let words = trimmed.split(separator: " ").map(String.init)
        let found = ArchiveRecord.all(in: store.data).filter { record in
            let text = record.title + " " + record.subtitle
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
        return Array(found.sorted { $0.date > $1.date }.prefix(40))
    }

    var body: some View {
        let visibleFeatures = features
        let foundRecords = records
        TherapyScreen {
            VStack(alignment: .leading, spacing: 22) {
                if trimmed.isEmpty {
                    GlassCard(emphasized: true) {
                        SectionHeader(title: "Alles an einem Ort", icon: "square.grid.3x3.fill", subtitle: "Jede Funktion der App – und Suche über Notizen, Aufgaben, Check-ins, Themen und mehr.")
                    }
                }
                ForEach(TherapyFeature.Area.allCases) { area in
                    let items = visibleFeatures.filter { $0.area == area }
                    if !items.isEmpty {
                        FeatureGridSection(title: area.title, icon: area.icon, tint: area.tint, features: items) { sheet = $0 }
                    }
                }
                if !foundRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Einträge", systemImage: "doc.text.magnifyingglass")
                            .font(.system(.headline, design: .rounded))
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(foundRecords) { record in
                                Button { editing = record } label: { recordRow(record) }
                                    .buttonStyle(TherapyRowPressStyle())
                                if record.id != foundRecords.last?.id { Divider().padding(.leading, 58) }
                            }
                        }
                        .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 4, style: .continuous))
                    }
                }
                if !trimmed.isEmpty && visibleFeatures.isEmpty && foundRecords.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
        }
        .navigationTitle("Suche")
        .searchable(text: $query, prompt: "Funktionen und Einträge")
        .sheet(item: $sheet) { feature in TherapyFeatureDestination(id: feature.id) }
        .sheet(item: $editing) { ArchiveRecordEditor(record: $0) }
    }

    private func recordRow(_ record: ArchiveRecord) -> some View {
        HStack(spacing: 12) {
            TherapyIconTile(icon: record.symbol, size: 32, tint: .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(record.date.formatted(date: .abbreviated, time: .shortened) + (record.subtitle.isEmpty ? "" : " · " + record.subtitle))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Alltag tab

struct EverydayHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sheet: TherapyFeature?
    @State private var routineToComplete: RoutineOccurrence?
    @State private var confirmRoutineCompletion = false

    var body: some View {
        TherapyScreen {
            VStack(spacing: 20) {
                EverydayStatusCard()
                TodayRoutinesCard { occurrence in routineToComplete = occurrence; confirmRoutineCompletion = true }
                FeatureGridSection(title: "Planen & erinnern", icon: "calendar.day.timeline.left", tint: .orange,
                                   features: TherapyFeature.features(["routines", "tasks", "reminders", "alarms", "showers", "timeline", "checkins", "routineHistory"], data: store.data),
                                   compact: true) { sheet = $0 }
                FeatureGridSection(title: "Wenn es schwer wird", icon: "lifepreserver.fill", tint: .red,
                                   features: TherapyFeature.features(["emergency", "grounding", "methods", "ai", "groundingHistory"], data: store.data),
                                   compact: true) { sheet = $0 }
                FeatureGridSection(title: "Befinden festhalten", icon: "heart.fill", tint: .pink,
                                   features: TherapyFeature.features(["mood", "note", "weeklyEnergy", "weekReview", "photo", "audio"], data: store.data),
                                   compact: true) { sheet = $0 }
                ShowerTodayCard()
            }
        }
        .navigationTitle("Alltag")
        .sheet(item: $sheet) { feature in TherapyFeatureDestination(id: feature.id) }
        .alert("Routine wirklich erledigt?", isPresented: $confirmRoutineCompletion, presenting: routineToComplete) { occurrence in
            Button("Abbrechen", role: .cancel) { routineToComplete = nil }
            Button("Ja, ich habe sie erledigt") { store.resolveRoutine(occurrence, outcome: .done); routineToComplete = nil }
        } message: { occurrence in
            Text("Bestätige nur, wenn du „\(store.data.routines.first { $0.id == occurrence.routineID }?.title ?? "diese Routine")“ wirklich abgeschlossen hast.")
        }
    }
}

/// Today's everyday numbers as glass chips.
struct EverydayStatusCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let data = store.data
            let open = RoutinePlanner.occurrences(data: data, now: Calendar.current.startOfDay(for: context.date), days: 1)
                .filter { !RoutinePlanner.resolved($0, completions: data.routineCompletions) }.count
            let tasks = data.weeklyTasks.filter { !$0.completed }.count
            let showers = ShowerPlanner.weekCount(data, at: context.date)
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Dein Alltag heute", icon: "figure.mind.and.body", subtitle: context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { chips(open: open, tasks: tasks, showers: showers, goal: data.showerPreferences.weeklyGoal) }
                        VStack(alignment: .leading, spacing: 8) { chips(open: open, tasks: tasks, showers: showers, goal: data.showerPreferences.weeklyGoal) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func chips(open: Int, tasks: Int, showers: Int, goal: Int) -> some View {
        TherapyChip(text: open == 0 ? "Routinen erledigt" : "\(open) Routinen offen", icon: open == 0 ? "checkmark.circle.fill" : "repeat", tint: .green)
        TherapyChip(text: "\(tasks) Aufgaben", icon: "checklist", tint: .orange)
        TherapyChip(text: "Duschen \(showers)/\(goal)", icon: "shower.fill", tint: .cyan)
    }
}

// MARK: - Verlauf tab

/// Archive and evaluation in one place, switched in the navigation bar.
struct HistoryHubView: View {
    @SceneStorage("therapy.history.section") private var section = 0

    var body: some View {
        Group {
            if section == 0 { LibraryView() } else { InsightsHubView() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Bereich", selection: $section) {
                    Text("Einträge").tag(0)
                    Text("Auswertung").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .accessibilityIdentifier("history.section")
            }
        }
    }
}
