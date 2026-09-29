import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.data.profile.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .background(AppBackground())
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.indigo.opacity(0.24),
                Color.teal.opacity(0.18),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var userName = ""
    @State private var therapistName = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 56)

                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 62, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)

                    Text("Dein Therapiebegleiter")
                        .font(.largeTitle.bold())

                    Text("Privat, strukturiert und ohne Account. Plane Termine, Wochenaufgaben, Notizen, Fotos, Audio und Rückblicke an einem Ort.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    GlassCard {
                        VStack(spacing: 16) {
                            TextField("Dein Name", text: $userName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)

                            TextField("Name deiner Therapeutin / deines Therapeuten", text: $therapistName)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                store.data.profile.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.data.profile.therapistName = therapistName.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.data.profile.onboardingCompleted = true
                            } label: {
                                Label("Therapiebegleiter starten", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Text("Die Inhalte werden standardmäßig nur auf deinem Gerät gespeichert. Zugriffe auf Kalender, Standort, Mikrofon und AlarmKit fragst du gezielt an.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
            }
        }
    }
}

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

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNote = false
    @State private var showEnergy = false
    @State private var showReflection = false

    private var currentTask: WeeklyTask? {
        let w = Date().therapyWeek
        return store.data.weeklyTasks.first {
            $0.weekOfYear == w.week && $0.yearForWeekOfYear == w.year
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        nextTherapyCard
                        weekCard
                        quickActions
                        recentCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Therapie")
            .sheet(isPresented: $showNote) { AddNoteView() }
            .sheet(isPresented: $showEnergy) { AddEnergyView() }
            .sheet(isPresented: $showReflection) { AddReflectionView() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.bold())
                Text("KW \(Date().therapyWeek.week) · \(Date().formatted(date: .complete, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "brain.head.profile.fill")
                .font(.title)
        }
    }

    private var greeting: String {
        let name = store.data.profile.userName
        return name.isEmpty ? "Hallo" : "Hallo, " + name
    }

    private var nextTherapyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Nächste Therapie", systemImage: "calendar.badge.clock")
                    .font(.headline)
                if let next = TherapyDateHelper.nextOccurrence(schedule: store.data.schedule) {
                    Text(next.formatted(date: .abbreviated, time: .shortened))
                        .font(.title2.bold())
                    if !store.data.profile.therapistName.isEmpty {
                        Text("mit " + store.data.profile.therapistName)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Noch nicht geplant")
                }
            }
        }
    }

    private var weekCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Wochenaufgabe", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Spacer()
                    if let task = currentTask {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    }
                }

                if let task = currentTask {
                    Text(task.title).font(.title3.bold())
                    if !task.details.isEmpty {
                        Text(task.details).foregroundStyle(.secondary)
                    }
                    Button(task.completed ? "Als offen markieren" : "Erledigt") {
                        guard let index = store.data.weeklyTasks.firstIndex(where: { $0.id == task.id }) else { return }
                        store.data.weeklyTasks[index].completed.toggle()
                        store.data.weeklyTasks[index].completedAt = store.data.weeklyTasks[index].completed ? Date() : nil
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Für diese Kalenderwoche ist noch keine Aufgabe eingetragen.")
                        .foregroundStyle(.secondary)
                    NavigationLink("Aufgabe anlegen") {
                        TasksView()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schnell erfassen")
                .font(.headline)
                .padding(.horizontal, 4)
            HStack(spacing: 10) {
                QuickActionButton(title: "Notiz", icon: "square.and.pencil") { showNote = true }
                QuickActionButton(title: "Energie", icon: "bolt.heart.fill") { showEnergy = true }
                QuickActionButton(title: "Rückblick", icon: "clock.arrow.circlepath") { showReflection = true }
            }
        }
    }

    private var recentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Letzte Einträge", systemImage: "clock.fill")
                    .font(.headline)
                ForEach(Array(store.data.notes.prefix(3))) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).fontWeight(.semibold)
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.data.notes.isEmpty {
                    Text("Noch keine Notizen.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

struct TherapyCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date()
    @State private var statusMessage: String?
    @State private var syncing = false

    private var therapyWeekdayMatch: Bool {
        Calendar.current.component(.weekday, from: selectedDate) == store.data.schedule.weekday
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            DatePicker(
                                "Datum",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Ausgewählter Tag", systemImage: "calendar.day.timeline.left")
                                    .font(.headline)
                                Text(selectedDate.formatted(date: .complete, time: .omitted))
                                    .font(.title3.bold())

                                if therapyWeekdayMatch {
                                    Label(
                                        "Regulärer Therapietag · \(String(format: "%02d:%02d", store.data.schedule.hour, store.data.schedule.minute)) Uhr",
                                        systemImage: "heart.circle.fill"
                                    )
                                }

                                let notes = store.data.notes.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }
                                let media = store.data.media.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }
                                let energy = store.data.energyEntries.filter { $0.createdAt.isSameTherapyDay(as: selectedDate) }

                                if notes.isEmpty && media.isEmpty && energy.isEmpty && !therapyWeekdayMatch {
                                    Text("Für diesen Tag gibt es noch keine Einträge.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    if !notes.isEmpty { Label("\(notes.count) Notizen", systemImage: "note.text") }
                                    if !media.isEmpty { Label("\(media.count) Medien", systemImage: "photo.on.rectangle.angled") }
                                    if !energy.isEmpty { Label("\(energy.count) Energie-Checks", systemImage: "bolt.fill") }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("iPhone-Kalender & AlarmKit", systemImage: "iphone.badge.radiowaves.left.and.right")
                                    .font(.headline)
                                Text("Erstellt einen wöchentlichen Kalendereintrag und richtet deine ausgewählten AlarmKit-Erinnerungen neu ein.")
                                    .foregroundStyle(.secondary)

                                Button {
                                    syncEverything()
                                } label: {
                                    HStack {
                                        if syncing { ProgressView() }
                                        Text(syncing ? "Synchronisiere …" : "Jetzt synchronisieren")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(syncing)

                                if let statusMessage {
                                    Text(statusMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Kalender")
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

struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    Section("Aktuelle & frühere Wochen") {
                        if store.data.weeklyTasks.isEmpty {
                            ContentUnavailableView(
                                "Noch keine Wochenaufgaben",
                                systemImage: "checklist",
                                description: Text("Lege die Aufgabe aus deiner Therapiesitzung für die aktuelle Kalenderwoche an.")
                            )
                            .listRowBackground(Color.clear)
                        }

                        ForEach($store.data.weeklyTasks) { $task in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("KW \(task.weekOfYear) / \(task.yearForWeekOfYear)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        task.completed.toggle()
                                        task.completedAt = task.completed ? Date() : nil
                                    } label: {
                                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                }
                                TextField("Aufgabe", text: $task.title)
                                    .font(.headline)
                                TextField("Beschreibung", text: $task.details, axis: .vertical)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { indexes in
                            store.data.weeklyTasks.remove(atOffsets: indexes)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Wochenaufgaben")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddTaskView() }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section = 0
    @State private var showPhoto = false
    @State private var showAudio = false
    @State private var showNote = false
    @State private var showDocument = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Bereich", selection: $section) {
                            Text("Timeline").tag(0)
                            Text("Medien").tag(1)
                            Text("Notizen").tag(2)
                            Text("Energie").tag(3)
                        }
                        .pickerStyle(.segmented)

                        if section == 0 {
                            TimelineView()
                        } else if section == 1 {
                            mediaSection
                        } else if section == 2 {
                            notesSection
                        } else {
                            energySection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Therapie-Archiv")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Foto hinzufügen", systemImage: "photo.badge.plus") { showPhoto = true }
                        Button("Sprachaufnahme", systemImage: "mic.fill") { showAudio = true }
                        Button("Dokument importieren", systemImage: "doc.badge.plus") { showDocument = true }
                        Button("Notiz", systemImage: "square.and.pencil") { showNote = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showPhoto) { AddPhotoView() }
            .sheet(isPresented: $showAudio) { AudioRecordingView() }
            .sheet(isPresented: $showNote) { AddNoteView() }
            .sheet(isPresented: $showDocument) { ImportDocumentView() }
        }
    }

    private var mediaSection: some View {
        LazyVStack(spacing: 12) {
            if store.data.media.isEmpty {
                ContentUnavailableView(
                    "Noch keine Medien",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Speichere Fotos deiner Pläne, Dokumente oder Sprachaufnahmen.")
                )
                .padding(.top, 48)
            }

            ForEach(store.data.media) { item in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .font(.title2)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !item.tags.isEmpty {
                                Text(item.tags.map { "#" + $0 }.joined(separator: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let lat = item.latitude, let lon = item.longitude {
                                Label(
                                    String(format: "%.5f, %.5f", lat, lon),
                                    systemImage: "location.fill"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteMedia(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        LazyVStack(spacing: 12) {
            ForEach($store.data.notes) { $note in
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Titel", text: $note.title).font(.headline)
                        TextField("Notiz", text: $note.text, axis: .vertical)
                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#" + $0 }.joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if store.data.notes.isEmpty {
                ContentUnavailableView("Noch keine Notizen", systemImage: "note.text")
                    .padding(.top, 48)
            }
        }
    }

    private var energySection: some View {
        LazyVStack(spacing: 12) {
            ForEach(store.data.energyEntries) { entry in
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Energie \(entry.level)/5", systemImage: "bolt.heart.fill")
                                .font(.headline)
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.givesEnergy.isEmpty {
                            Text("Gibt Energie: " + entry.givesEnergy)
                        }
                        if !entry.takesEnergy.isEmpty {
                            Text("Nimmt Energie: " + entry.takesEnergy)
                        }
                        if !entry.note.isEmpty {
                            Text(entry.note).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct TimelineView: View {
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
        return values.sorted { $0.date > $1.date }
    }

    var body: some View {
        LazyVStack(spacing: 12) {
            if rows.isEmpty {
                ContentUnavailableView(
                    "Deine Timeline ist noch leer",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Einträge erscheinen hier automatisch chronologisch.")
                )
                .padding(.top, 48)
            }

            ForEach(rows) { row in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.title3)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            if !row.subtitle.isEmpty {
                                Text(row.subtitle)
                                    .lineLimit(3)
                                    .foregroundStyle(.secondary)
                            }
                            Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

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
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        scheduleCard
                        reminderCard
                        backupCard
                        privacyCard
                        dangerCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Profil & Einstellungen")
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
                Button("Abbrechen", role: .cancel) { deletePhrase = "" }
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
            VStack(alignment: .leading, spacing: 12) {
                Label("Personen", systemImage: "person.2.fill").font(.headline)
                TextField("Dein Name", text: $store.data.profile.userName)
                    .textFieldStyle(.roundedBorder)
                TextField("Therapeutin / Therapeut", text: $store.data.profile.therapistName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var scheduleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Fester Therapietag", systemImage: "calendar.badge.clock").font(.headline)

                Picker("Wochentag", selection: $store.data.schedule.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(TherapyDateHelper.weekdayName(day)).tag(day)
                    }
                }

                HStack {
                    Picker("Stunde", selection: $store.data.schedule.hour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    Picker("Minute", selection: $store.data.schedule.minute) {
                        ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) {
                            Text(String(format: "%02d", $0)).tag($0)
                        }
                    }
                }

                Stepper(
                    "Dauer: \(store.data.schedule.durationMinutes) Minuten",
                    value: $store.data.schedule.durationMinutes,
                    in: 30...180,
                    step: 15
                )
            }
        }
    }

    private var reminderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Erinnerungen", systemImage: "alarm.fill").font(.headline)
                Text("AlarmKit-Erinnerungen für den Therapietermin:")
                    .foregroundStyle(.secondary)

                reminderToggle("1 Tag vorher", minutes: 1440)
                reminderToggle("2 Stunden vorher", minutes: 120)
                reminderToggle("30 Minuten vorher", minutes: 30)
                reminderToggle("10 Minuten vorher", minutes: 10)

                Divider()

                Toggle("Wochenaufgaben-Impulse", isOn: $store.data.schedule.taskReminderEnabled)
                if store.data.schedule.taskReminderEnabled {
                    Text("Standardmäßig donnerstags und sonntags. Diese Impulse werden beim nächsten Synchronisieren als AlarmKit-Alarme gesetzt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reminderToggle(_ title: String, minutes: Int) -> some View {
        let binding = Binding<Bool>(
            get: { store.data.schedule.reminderOffsetsMinutes.contains(minutes) },
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
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("iCloud Drive / Dateien-Backup", systemImage: "icloud.and.arrow.up.fill").font(.headline)
                Text("Wähle einen Ordner in iCloud Drive oder „Auf meinem iPhone“. Die App erhält nur Zugriff auf diesen von dir ausgewählten Ordner.")
                    .foregroundStyle(.secondary)

                if let folder = BackupService.shared.selectedFolderName() {
                    Label("Verbunden: " + folder, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                }

                Toggle(
                    "Bei Änderungen automatisch sichern",
                    isOn: $store.data.preferences.autoBackupToSelectedFolder
                )

                HStack {
                    Button("Ordner wählen") { showFolderPicker = true }
                        .buttonStyle(.borderedProminent)
                    Button("Jetzt sichern") {
                        do {
                            try store.backupNow()
                            statusMessage = "Backup wurde aktualisiert."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button("Backup wiederherstellen") { showRestoreDialog = true }
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
            VStack(alignment: .leading, spacing: 10) {
                Label("Privatsphäre", systemImage: "lock.shield.fill").font(.headline)
                Toggle(
                    "Standort bei neuen Medien mitschreiben",
                    isOn: $store.data.preferences.includeLocationForNewMedia
                )
                Text("Standortdaten werden nur nach iOS-Freigabe erfasst. Die App nutzt keinen eigenen Server und kein Tracking-SDK.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dangerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Datenverwaltung", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text("Einzelne Medien können direkt im Archiv gelöscht werden. Für einen Komplett-Reset ist ein exakter Sicherheitssatz nötig.")
                    .foregroundStyle(.secondary)
                Button("Alle Therapiedaten löschen", role: .destructive) {
                    showDeleteDialog = true
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct AddTaskView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Wochenaufgabe", text: $title)
                TextField("Beschreibung", text: $details, axis: .vertical)
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
                TextField("Titel", text: $title)
                TextField("Notiz", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                TextField("Tags, durch Komma getrennt", text: $tags)
            }
            .navigationTitle("Neue Notiz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addNote(title: title.isEmpty ? "Notiz" : title, text: text, tags: parseTags(tags))
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
                }
                Section("Was nimmt mir Energie?") {
                    TextField("Lärm, Konflikte, Termine …", text: $takes, axis: .vertical)
                }
                Section("Notiz") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Energie-Check")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
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
                }
                Section("Was hat geholfen?") {
                    TextField("Hilfreiches festhalten", text: $helped, axis: .vertical)
                }
                Section("Bis zur nächsten Therapie") {
                    TextField("Fokus / nächster Schritt", text: $nextFocus, axis: .vertical)
                }
            }
            .navigationTitle("Therapie-Rückblick")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
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
                        Label(pickerItem == nil ? "Foto auswählen" : "Foto ausgewählt", systemImage: "photo.badge.plus")
                    }
                }
                Section("Beschreibung") {
                    TextField("Name des Fotos", text: $title)
                    TextField("Notiz", text: $note, axis: .vertical)
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
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Foto hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
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
                TextField("Titel (optional)", text: $title)
                TextField("Tags, durch Komma getrennt", text: $tags)
                Button("Datei auswählen", systemImage: "doc.badge.plus") {
                    showImporter = true
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Dokument importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
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
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 92))
                    .symbolRenderingMode(.hierarchical)

                Text(recorder.isRecording ? "Aufnahme läuft" : "Sprachaufzeichnung")
                    .font(.title.bold())

                Text(durationText(recorder.elapsed))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("Titel", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags, durch Komma getrennt", text: $tags)
                    .textFieldStyle(.roundedBorder)

                Button {
                    toggleRecording()
                } label: {
                    Label(
                        recorder.isRecording ? "Aufnahme beenden" : "Aufnahme starten",
                        systemImage: recorder.isRecording ? "stop.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(22)
            .background(AppBackground())
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        if recorder.isRecording { _ = recorder.stop() }
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
                store.commitRecording(url: currentURL, duration: duration, title: title, tags: parseTags(tags))
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
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "") }
        .filter { !$0.isEmpty }
}
