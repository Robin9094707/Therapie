import SwiftUI
import UIKit

// MARK: - Betreutes Wohnen (Kompass 6)

private enum BeWoSheet: Identifiable {
    case appointment(AssistedLivingAppointment)
    case conversation(UUID)
    case topic(AssistedLivingTopic)
    case goal(AssistedLivingGoal)
    case settings
    var id: String {
        switch self {
        case .appointment(let value): "appointment-" + value.id.uuidString
        case .conversation(let id): "conversation-" + id.uuidString
        case .topic(let value): "topic-" + value.id.uuidString
        case .goal(let value): "goal-" + value.id.uuidString
        case .settings: "settings"
        }
    }
}

enum BeWoMood {
    static let faces = ["😣", "🙁", "😐", "🙂", "😄"]
    static let titles = ["Sehr schwer", "Eher schwer", "Mittel", "Eher gut", "Gut"]
    static func face(_ value: Int?) -> String { value.map { faces[max(0, min(4, $0 - 1))] } ?? "–" }
}

struct AssistedLivingHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sheet: BeWoSheet?
    @State private var quickTopic = ""
    @FocusState private var topicFocused: Bool

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let upcoming = AssistedLivingPlanner.upcoming(store.data, now: context.date, days: 60)
            TherapyScreen {
                VStack(spacing: 16) {
                    nextCard(upcoming.first, now: context.date)
                    quickActions(next: upcoming.first)
                    topicsCard
                    agreementsCard
                    AIShortcutStrip(title: "Mit KI begleiten", prompts: [
                        ("Termin vorbereiten", "list.bullet.clipboard", "Hilf mir, meinen nächsten BeWo-Termin vorzubereiten: Sortiere meine offenen BeWo-Themen nach Wichtigkeit, formuliere zu jedem eine konkrete Frage und sag mir, welche Unterlagen ich bereitlegen sollte. Schlage passende bewoTopic-Aktionen nur für neue Themen vor."),
                        ("Nach dem Termin", "doc.text", "Ich hatte gerade meinen BeWo-Termin. Frag mich kurz, was besprochen wurde, und hilf mir danach mit einer Zusammenfassung, besprochenen Themen und Absprachen als Aktionen."),
                        ("Termin eintragen", "calendar.badge.plus", "Ich möchte einen BeWo-Termin eintragen. Frag mich nach Tag, Uhrzeit und Art und schlage ihn dann als bewoAppointment vor."),
                        ("Absprachen prüfen", "checklist", "Welche BeWo-Absprachen sind noch offen? Hilf mir mit einem kleinen nächsten Schritt für die wichtigste.")
                    ])
                    if upcoming.count > 1 { upcomingCard(Array(upcoming.dropFirst().prefix(5)), now: context.date) }
                    goalsCard
                    contactCard
                    TherapySettingsSection(title: "Mehr") {
                        TherapySettingsLink(title: "Vergangene Termine", icon: "clock.arrow.circlepath", tint: .purple, value: "\(store.data.assistedLivingAppointments.filter { $0.status != .planned || $0.end <= context.date }.count)") { AssistedLivingHistoryView() }
                        TherapySettingsLink(title: "Alle Themen", icon: "tray.full.fill", tint: .orange, value: "\(store.data.assistedLivingTopics.count)") { AssistedLivingTopicsView() }
                        TherapySettingsLink(title: "BeWo-Einstellungen", icon: "gearshape.fill", subtitle: "Betreuung, regelmäßige Termine, Erinnerungen", tint: .gray) { AssistedLivingSettingsView() }
                    }
                }
            }
        }
        .navigationTitle("Betreutes Wohnen")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Neuer Termin", systemImage: "calendar.badge.plus") { sheet = .appointment(newAppointment()) }
                    Button("Neues Thema", systemImage: "text.bubble") { sheet = .topic(AssistedLivingTopic()) }
                    Button("Neues Ziel", systemImage: "flag") { sheet = .goal(AssistedLivingGoal()) }
                } label: { Label("Hinzufügen", systemImage: "plus") }
                .accessibilityIdentifier("bewo.add")
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .appointment(let value): AssistedLivingAppointmentEditor(appointment: value)
            case .conversation(let id): AssistedLivingConversationView(appointmentID: id)
            case .topic(let value): AssistedLivingTopicEditor(topic: value)
            case .goal(let value): AssistedLivingGoalEditor(goal: value)
            case .settings: NavigationStack { AssistedLivingSettingsView() }
            }
        }
        .onAppear { store.notificationAssistedLiving = false }
    }

    private func newAppointment() -> AssistedLivingAppointment {
        let settings = store.data.assistedLivingSettings
        let start = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
        return AssistedLivingAppointment(date: start, durationMinutes: settings.defaultDurationMinutes, caregiver: settings.caregiverName, location: settings.defaultLocation,
                                         topicIDs: store.data.assistedLivingTopics.filter { $0.status == .next }.map(\.id))
    }

    // MARK: Next visit

    private func nextCard(_ next: AssistedLivingOccurrence?, now: Date) -> some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let next {
                    let stored = next.appointmentID.flatMap { id in store.data.assistedLivingAppointments.first { $0.id == id } }
                    HStack(alignment: .top, spacing: 14) {
                        TherapyIconTile(icon: next.kind.symbol, size: 52, tint: .brown)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nächster BeWo-Termin").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Color.accentColor)
                            Text(AssistedLivingPlanner.countdown(to: next.date, now: now)).font(.system(.title2, design: .rounded, weight: .bold))
                            Text(next.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()) + " · \(next.durationMinutes) Min.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { chips(next, stored: stored) }
                        VStack(alignment: .leading, spacing: 8) { chips(next, stored: stored) }
                    }
                    if let stored, !stored.preparation.isEmpty {
                        Text(stored.preparation).font(.subheadline).lineLimit(3).padding(12).frame(maxWidth: .infinity, alignment: .leading).therapyInsetSurface()
                    }
                    ResponsiveButtonRow {
                        Button {
                            sheet = .appointment(store.materialize(next))
                        } label: { Label("Vorbereiten", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        Button {
                            let appointment = store.materialize(next)
                            sheet = .conversation(appointment.id)
                        } label: { Label("Gespräch begleiten", systemImage: "bubble.left.and.text.bubble.right.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("bewo.conversation")
                    }
                    .controlSize(.large)
                    if next.appointmentID == nil && next.regularVisitID != nil {
                        Button("Dieser Termin fällt aus", systemImage: "calendar.badge.minus") { store.skipRegularVisit(next) }
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                } else {
                    SectionHeader(title: "Betreutes Wohnen", icon: "house.fill", subtitle: "Ambulant bei dir zu Hause – Termine, Themen und Absprachen an einem Ort.")
                    Text("Trag deinen nächsten Termin ein oder richte einen regelmäßigen Besuch ein. Themen kannst du jederzeit sammeln.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ResponsiveButtonRow {
                        Button { sheet = .appointment(newAppointment()) } label: { Label("Termin eintragen", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                        NavigationLink { AssistedLivingSettingsView() } label: { Label("Regelmäßig einrichten", systemImage: "repeat").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    @ViewBuilder private func chips(_ next: AssistedLivingOccurrence, stored: AssistedLivingAppointment?) -> some View {
        let settings = store.data.assistedLivingSettings
        TherapyChip(text: next.kind.title, icon: next.kind.symbol, tint: .brown)
        let caregiver = stored?.caregiver.isEmpty == false ? stored!.caregiver : settings.caregiverName
        if !caregiver.isEmpty { TherapyChip(text: caregiver, icon: "person.fill", tint: .teal) }
        let topics = stored?.topicIDs.count ?? store.data.assistedLivingTopics.filter { $0.status == .next }.count
        TherapyChip(text: topics == 1 ? "1 Thema" : "\(topics) Themen", icon: "text.bubble.fill", tint: .orange)
    }

    // MARK: Quick actions

    /// Kompass 7: one calm row of small buttons instead of four large tiles.
    private func quickActions(next: AssistedLivingOccurrence?) -> some View {
        HStack(spacing: 8) {
            quickTile("Termin", icon: "calendar.badge.plus", tint: .brown) { sheet = .appointment(newAppointment()) }
            quickTile("Thema", icon: "text.bubble.fill", tint: .orange) { sheet = .topic(AssistedLivingTopic()) }
            quickTile("Ziel", icon: "flag.fill", tint: .green) { sheet = .goal(AssistedLivingGoal()) }
            quickTile("Anrufen", icon: "phone.fill", tint: .teal) {
                let digits = store.data.assistedLivingSettings.caregiverPhone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:" + digits), !digits.isEmpty { UIApplication.shared.open(url) } else { sheet = .settings }
            }
        }
    }

    private func quickTile(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button { TherapyEffects.shared.light(); action() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(tint)
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(TherapyPressStyle())
        .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius, style: .continuous), interactive: true)
    }

    // MARK: Topics

    private var topicsCard: some View {
        let open = AssistedLivingPlanner.openTopics(store.data)
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Gesprächsthemen", icon: "text.bubble.fill", subtitle: "Was du beim nächsten Termin ansprechen möchtest.")
                    Spacer()
                }
                HStack(spacing: 8) {
                    TextField("Neues Thema, z. B. Brief vom Jobcenter", text: $quickTopic)
                        .focused($topicFocused)
                        .submitLabel(.done)
                        .onSubmit(addQuickTopic)
                        .padding(12)
                        .therapyInsetSurface()
                        .accessibilityIdentifier("bewo.quickTopic")
                    Button(action: addQuickTopic) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(quickTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Thema hinzufügen")
                }
                if open.isEmpty {
                    Text("Noch keine offenen Themen. Alles, was dir zwischen den Terminen einfällt, kannst du hier sofort festhalten.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(open.prefix(8)) { topic in topicRow(topic) }
                    if open.count > 8 {
                        NavigationLink("Alle \(open.count) offenen Themen") { AssistedLivingTopicsView() }.font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func addQuickTopic() {
        let title = quickTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.saveAssistedLivingTopic(AssistedLivingTopic(title: title))
        quickTopic = ""
        TherapyEffects.shared.light()
    }

    private func topicRow(_ topic: AssistedLivingTopic) -> some View {
        HStack(spacing: 12) {
            Button {
                store.setTopicStatus(topic.id, topic.status == .next ? .open : .next)
            } label: {
                Image(systemName: topic.status == .next ? "star.fill" : "star").foregroundStyle(topic.status == .next ? Color.orange : Color.secondary).font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(topic.status == .next ? "Nicht mehr für den nächsten Termin vormerken" : "Für den nächsten Termin vormerken")
            Button { sheet = .topic(topic) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                        Label(topic.category.title, systemImage: topic.category.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if topic.priority == 3 { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Wichtig") }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Als besprochen markieren", systemImage: "checkmark.bubble.fill") { store.setTopicStatus(topic.id, .discussed) }
            Button("Erledigt", systemImage: "checkmark.circle.fill") { store.setTopicStatus(topic.id, .done) }
            Button("Löschen", systemImage: "trash", role: .destructive) { store.deleteAssistedLivingTopic(topic.id) }
        }
    }

    // MARK: Agreements

    @ViewBuilder private var agreementsCard: some View {
        let open = AssistedLivingPlanner.openAgreements(store.data)
        if !open.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Absprachen bis zum nächsten Mal", icon: "checklist", subtitle: "\(open.count) offen")
                    ForEach(open.prefix(8)) { entry in
                        Button { store.toggleAgreement(entry.agreement.id, in: entry.appointment.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle").font(.title3).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.agreement.title).font(.subheadline).foregroundStyle(.primary)
                                    Text(entry.agreement.owner.title + (entry.agreement.dueDate.map { " · bis " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "") + " · vom " + entry.appointment.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Upcoming

    private func upcomingCard(_ items: [AssistedLivingOccurrence], now: Date) -> some View {
        TherapySettingsSection(title: "Danach") {
            ForEach(items) { occurrence in
                Button { sheet = .appointment(store.materialize(occurrence)) } label: {
                    TherapySettingsRow(title: occurrence.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()), icon: occurrence.kind.symbol,
                                       subtitle: occurrence.kind.title + (occurrence.appointmentID == nil ? " · regelmäßig" : ""), tint: .brown)
                }
                .buttonStyle(TherapyRowPressStyle())
                .contextMenu {
                    if occurrence.appointmentID == nil && occurrence.regularVisitID != nil {
                        Button("Fällt aus", systemImage: "calendar.badge.minus") { store.skipRegularVisit(occurrence) }
                    }
                }
            }
        }
    }

    // MARK: Goals

    private var goalsCard: some View {
        let goals = store.data.assistedLivingGoals.filter { $0.completedAt == nil }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Meine Ziele im BeWo", icon: "flag.fill", subtitle: goals.isEmpty ? "Kleine Schritte, die du mit deiner Betreuung angehst." : "\(goals.count) aktiv")
                if goals.isEmpty {
                    Button("Ziel anlegen", systemImage: "plus") { sheet = .goal(AssistedLivingGoal()) }.buttonStyle(.glass)
                }
                ForEach(goals) { goal in
                    Button { sheet = .goal(goal) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(goal.title, systemImage: goal.category.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int(goal.progress * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ProgressView(value: goal.progress).tint(.green)
                            if let step = goal.steps.first(where: { !$0.done }) {
                                Text("Nächster Schritt: " + step.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Contact

    @ViewBuilder private var contactCard: some View {
        let settings = store.data.assistedLivingSettings
        if !settings.caregiverName.isEmpty || !settings.providerName.isEmpty || !settings.caregiverPhone.isEmpty || !settings.officePhone.isEmpty {
            TherapySettingsSection(title: "Meine Betreuung") {
                if !settings.caregiverName.isEmpty || !settings.providerName.isEmpty {
                    TherapySettingsRow(title: settings.caregiverName.isEmpty ? settings.providerName : settings.caregiverName, icon: "person.crop.circle.fill",
                                       subtitle: settings.caregiverName.isEmpty ? nil : (settings.providerName.isEmpty ? nil : settings.providerName), tint: .teal, showsChevron: false)
                }
                if let url = phoneURL(settings.caregiverPhone) {
                    Link(destination: url) { TherapySettingsRow(title: "Betreuung anrufen", icon: "phone.fill", tint: .green, value: settings.caregiverPhone) }
                        .buttonStyle(TherapyRowPressStyle())
                }
                if let url = phoneURL(settings.officePhone) {
                    Link(destination: url) { TherapySettingsRow(title: "Büro anrufen", icon: "building.2.fill", tint: .blue, value: settings.officePhone) }
                        .buttonStyle(TherapyRowPressStyle())
                }
            }
        }
    }

    private func phoneURL(_ value: String) -> URL? {
        let digits = value.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:" + digits)
    }
}

// MARK: - Appointment editor

struct AssistedLivingAppointmentEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var appointment: AssistedLivingAppointment
    @State private var newAgreement = ""
    @State private var newAgreementOwner = AssistedLivingOwner.me
    @State private var newTopic = ""
    @State private var confirmDelete = false
    @State private var conversation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    DatePicker("Beginn", selection: $appointment.date)
                    Stepper("Dauer: \(appointment.durationMinutes) Min.", value: $appointment.durationMinutes, in: 15...480, step: 15)
                    Picker("Art", selection: $appointment.kind) {
                        ForEach(AssistedLivingVisitKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Titel", text: $appointment.title)
                    TextField("Betreuer:in", text: $appointment.caregiver)
                    TextField("Ort", text: $appointment.location)
                    Picker("Stand", selection: $appointment.status) {
                        ForEach(AssistedLivingStatus.allCases) { Text($0.title).tag($0) }
                    }
                    if appointment.status == .cancelled { TextField("Grund der Absage", text: $appointment.cancelReason) }
                }
                Section {
                    TextField("Was möchte ich sagen oder fragen?", text: $appointment.preparation, axis: .vertical)
                        .lineLimit(3...10)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(store.data.assistedLivingSettings.preparationPrompts, id: \.self) { prompt in
                                Button(prompt) { appointment.preparation += (appointment.preparation.isEmpty ? "" : "\n") + prompt + " " }
                                    .buttonStyle(.glass).font(.caption)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                } header: { Text("Vorbereitung") } footer: { Text("Tippe auf eine Frage, um sie als Anfang einzufügen.") }
                Section("Themen für diesen Termin") {
                    let topics = store.data.assistedLivingTopics.filter { $0.status.isOpen || appointment.topicIDs.contains($0.id) }
                    ForEach(topics) { topic in
                        Toggle(isOn: Binding(get: { appointment.topicIDs.contains(topic.id) }, set: { on in
                            appointment.topicIDs.removeAll { $0 == topic.id }; if on { appointment.topicIDs.append(topic.id) }
                        })) {
                            Label { VStack(alignment: .leading) { Text(topic.title); if topic.status == .discussed { Text("Besprochen").font(.caption).foregroundStyle(.green) } } } icon: { Image(systemName: topic.category.symbol) }
                        }
                    }
                    HStack {
                        TextField("Neues Thema", text: $newTopic)
                        Button("Hinzufügen") {
                            let topic = AssistedLivingTopic(title: newTopic)
                            store.saveAssistedLivingTopic(topic)
                            appointment.topicIDs.append(topic.id)
                            newTopic = ""
                        }
                        .disabled(newTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Wie geht es mir?") {
                    moodRow("Vorher", value: $appointment.moodBefore)
                    moodRow("Nachher", value: $appointment.moodAfter)
                }
                Section("Nach dem Termin") {
                    TextField("Was haben wir besprochen?", text: $appointment.summary, axis: .vertical).lineLimit(3...12)
                    TextField("Was hat gutgetan?", text: $appointment.wentWell, axis: .vertical).lineLimit(2...8)
                }
                Section("Absprachen") {
                    ForEach($appointment.agreements) { $agreement in
                        HStack {
                            Button { agreement.done.toggle(); agreement.doneAt = agreement.done ? Date() : nil } label: {
                                Image(systemName: agreement.done ? "checkmark.circle.fill" : "circle").foregroundStyle(agreement.done ? Color.green : Color.accentColor)
                            }.buttonStyle(.plain)
                            TextField("Absprache", text: $agreement.title)
                            Menu {
                                Picker("Wer", selection: $agreement.owner) { ForEach(AssistedLivingOwner.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                                Button(agreement.dueDate == nil ? "Frist setzen (1 Woche)" : "Frist entfernen", systemImage: "calendar") {
                                    agreement.dueDate = agreement.dueDate == nil ? Calendar.current.date(byAdding: .day, value: 7, to: appointment.date) : nil
                                }
                            } label: { Image(systemName: agreement.owner.symbol) }
                        }
                        if let due = agreement.dueDate {
                            DatePicker("Frist", selection: Binding(get: { due }, set: { agreement.dueDate = $0 }), displayedComponents: .date).font(.caption)
                        }
                    }
                    .onDelete { appointment.agreements.remove(atOffsets: $0) }
                    HStack {
                        TextField("Neue Absprache", text: $newAgreement)
                        Picker("Wer", selection: $newAgreementOwner) { ForEach(AssistedLivingOwner.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                        Button { appointment.agreements.append(AssistedLivingAgreement(title: newAgreement, owner: newAgreementOwner)); newAgreement = "" } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newAgreement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    Button("Gesprächsbegleitung öffnen", systemImage: "bubble.left.and.text.bubble.right.fill") { store.saveAssistedLivingAppointment(appointment); conversation = true }
                    if store.data.assistedLivingAppointments.contains(where: { $0.id == appointment.id }) {
                        Button("Termin löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .therapyFormStyle()
            .navigationTitle(appointment.status == .planned ? "BeWo-Termin" : appointment.status.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { store.saveAssistedLivingAppointment(appointment); dismiss() }.accessibilityIdentifier("bewo.save") }
            }
            .alert("Termin löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) { store.deleteAssistedLivingAppointment(appointment.id); dismiss() }
            } message: { Text("Themen bleiben erhalten. Rückgängig machen geht über „Änderung zurücknehmen“.") }
            .sheet(isPresented: $conversation, onDismiss: {
                if let saved = store.data.assistedLivingAppointments.first(where: { $0.id == appointment.id }) { appointment = saved }
            }) { AssistedLivingConversationView(appointmentID: appointment.id) }
        }
    }

    private func moodRow(_ title: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ForEach(1...5, id: \.self) { level in
                Button { value.wrappedValue = value.wrappedValue == level ? nil : level } label: {
                    Text(BeWoMood.faces[level - 1]).font(.title3).opacity(value.wrappedValue == nil || value.wrappedValue == level ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BeWoMood.titles[level - 1])
                .accessibilityAddTraits(value.wrappedValue == level ? .isSelected : [])
            }
        }
    }
}

// MARK: - Conversation companion

/// Guides through a visit: how am I, topic by topic, agreements, how do I feel afterwards.
struct AssistedLivingConversationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let appointmentID: UUID
    @State private var outcomes: [UUID: String] = [:]
    @State private var agreement = ""
    @State private var owner = AssistedLivingOwner.me
    @State private var notes = ""
    @State private var loaded = false

    private var appointment: AssistedLivingAppointment? { store.data.assistedLivingAppointments.first { $0.id == appointmentID } }

    var body: some View {
        NavigationStack {
            TherapyScreen {
                if let appointment {
                    VStack(spacing: 18) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Wie geht es dir gerade?", icon: "heart.fill", subtitle: appointment.date.formatted(date: .complete, time: .shortened))
                                moodPicker(appointment.moodBefore) { level in update { $0.moodBefore = level } }
                                if !appointment.preparation.isEmpty {
                                    Text(appointment.preparation).font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading).therapyInsetSurface()
                                }
                            }
                        }
                        topicsCard(appointment)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Absprachen", icon: "checklist", subtitle: "Wer macht was bis zum nächsten Mal?")
                                ForEach(appointment.agreements) { item in
                                    Button { store.toggleAgreement(item.id, in: appointment.id) } label: {
                                        Label(item.title + " · " + item.owner.title, systemImage: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(.primary)
                                    }.buttonStyle(.plain)
                                }
                                HStack(spacing: 8) {
                                    TextField("z. B. Antrag zusammen ausfüllen", text: $agreement).padding(10).therapyInsetSurface()
                                    Picker("Wer", selection: $owner) { ForEach(AssistedLivingOwner.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                                    Button {
                                        let text = agreement.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !text.isEmpty else { return }
                                        update { $0.agreements.append(AssistedLivingAgreement(title: text, owner: owner, dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()))) }
                                        agreement = ""
                                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                                }
                            }
                        }
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Notizen", icon: "note.text", subtitle: "Stichworte reichen.")
                                TextField("Was war wichtig?", text: $notes, axis: .vertical).lineLimit(4...12).padding(12).therapyInsetSurface()
                                Text("Und jetzt – wie geht es dir?").font(.subheadline.weight(.semibold))
                                moodPicker(appointment.moodAfter) { level in update { $0.moodAfter = level } }
                            }
                        }
                        AIAskButton(title: "Mit KI zusammenfassen", question: summaryQuestion(appointment), icon: "sparkles", prominent: false)
                        PrimaryActionButton(title: "Termin abschließen", icon: "checkmark.seal.fill") { finish() }
                            .accessibilityIdentifier("bewo.finish")
                    }
                } else {
                    ContentUnavailableView("Termin nicht gefunden", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("Gesprächsbegleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Später") { saveNotes(); dismiss() } }
            }
            .onAppear {
                guard !loaded, let appointment else { return }
                loaded = true
                notes = appointment.summary
                for topic in store.data.assistedLivingTopics where appointment.topicIDs.contains(topic.id) { outcomes[topic.id] = topic.outcome }
            }
        }
    }

    private func topicsCard(_ appointment: AssistedLivingAppointment) -> some View {
        let topics = store.data.assistedLivingTopics.filter { appointment.topicIDs.contains($0.id) || $0.status == .next }
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Themen", icon: "text.bubble.fill", subtitle: "\(topics.filter { $0.status == .discussed || $0.status == .done }.count) von \(topics.count) besprochen")
                if topics.isEmpty { Text("Keine Themen vorgemerkt. Du kannst einfach frei sprechen.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if topic.status == .discussed || topic.status == .done { store.setTopicStatus(topic.id, .next) }
                            else { store.setTopicStatus(topic.id, .discussed, appointmentID: appointment.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: topic.status == .discussed || topic.status == .done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(topic.status == .discussed || topic.status == .done ? Color.green : Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(topic.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    if !topic.details.isEmpty { Text(topic.details).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        TextField("Ergebnis (optional)", text: Binding(get: { outcomes[topic.id] ?? "" }, set: { outcomes[topic.id] = $0 }), axis: .vertical)
                            .font(.footnote).lineLimit(1...4).padding(10).therapyInsetSurface()
                    }
                }
            }
        }
    }

    private func moodPicker(_ value: Int?, set: @escaping (Int?) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { level in
                Button { set(value == level ? nil : level) } label: {
                    VStack(spacing: 2) {
                        Text(BeWoMood.faces[level - 1]).font(.system(size: 30))
                        Text(BeWoMood.titles[level - 1]).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .therapyInsetSurface(selected: value == level)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BeWoMood.titles[level - 1])
                .accessibilityAddTraits(value == level ? .isSelected : [])
            }
        }
    }

    private func summaryQuestion(_ appointment: AssistedLivingAppointment) -> String {
        let topics = store.data.assistedLivingTopics.filter { appointment.topicIDs.contains($0.id) || $0.status == .next }
        let topicLines = topics.map { "- " + $0.title + " (Thema-ID " + $0.id.uuidString + ", " + $0.status.title + ")" + ((outcomes[$0.id] ?? "").isEmpty ? "" : ": " + (outcomes[$0.id] ?? "")) }.joined(separator: "\n")
        return "Fasse meinen BeWo-Termin (Termin-ID " + appointment.id.uuidString + ", " + appointment.date.formatted(date: .abbreviated, time: .shortened) + ") zusammen.\nMeine Notizen: " + (notes.isEmpty ? "(keine)" : notes) + "\nThemen:\n" + (topicLines.isEmpty ? "(keine)" : topicLines) + "\nSchlage eine bewoSummary für diesen Termin, discussBewoTopic für besprochene Themen und bewoAgreement für erkennbare Absprachen vor."
    }

    private func update(_ change: (inout AssistedLivingAppointment) -> Void) {
        guard var value = appointment else { return }
        change(&value)
        store.saveAssistedLivingAppointment(value)
    }

    private func saveNotes() {
        update { $0.summary = notes }
        var snapshot = store.data
        for (id, text) in outcomes {
            if let index = snapshot.assistedLivingTopics.firstIndex(where: { $0.id == id }), snapshot.assistedLivingTopics[index].outcome != text {
                snapshot.assistedLivingTopics[index].outcome = text
                snapshot.assistedLivingTopics[index].updatedAt = Date()
            }
        }
        if snapshot != store.data { store.data = snapshot }
    }

    private func finish() {
        saveNotes()
        update { $0.status = .done }
        TherapyEffects.shared.light()
        dismiss()
    }
}

// MARK: - Topic editor

struct AssistedLivingTopicEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var topic: AssistedLivingTopic

    var body: some View {
        NavigationStack {
            Form {
                Section("Thema") {
                    TextField("Worum geht es?", text: $topic.title)
                    TextField("Details, Fragen, Fristen", text: $topic.details, axis: .vertical).lineLimit(2...8)
                }
                Section("Einordnung") {
                    Picker("Bereich", selection: $topic.category) { ForEach(AssistedLivingTopicCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                    Picker("Wichtigkeit", selection: $topic.priority) { Text("Kann warten").tag(1); Text("Normal").tag(2); Text("Wichtig").tag(3) }.pickerStyle(.segmented)
                    Picker("Stand", selection: $topic.status) { ForEach(AssistedLivingTopicStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                }
                if topic.status == .discussed || topic.status == .done || !topic.outcome.isEmpty {
                    Section("Ergebnis") { TextField("Was ist dabei herausgekommen?", text: $topic.outcome, axis: .vertical).lineLimit(2...8) }
                }
                if store.data.assistedLivingTopics.contains(where: { $0.id == topic.id }) {
                    Section { Button("Thema löschen", systemImage: "trash", role: .destructive) { store.deleteAssistedLivingTopic(topic.id); dismiss() } }
                }
            }
            .therapyFormStyle()
            .navigationTitle("Gesprächsthema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { store.saveAssistedLivingTopic(topic); dismiss() }
                        .disabled(topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Goal editor

struct AssistedLivingGoalEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var goal: AssistedLivingGoal
    @State private var newStep = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ziel") {
                    TextField("z. B. Post jede Woche öffnen", text: $goal.title)
                    TextField("Warum ist mir das wichtig?", text: $goal.details, axis: .vertical).lineLimit(2...6)
                    Picker("Bereich", selection: $goal.category) { ForEach(AssistedLivingTopicCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                }
                Section {
                    ForEach($goal.steps) { $step in
                        HStack {
                            Button { step.done.toggle(); step.doneAt = step.done ? Date() : nil } label: {
                                Image(systemName: step.done ? "checkmark.circle.fill" : "circle").foregroundStyle(step.done ? Color.green : Color.accentColor)
                            }.buttonStyle(.plain)
                            TextField("Schritt", text: $step.title)
                        }
                    }
                    .onDelete { goal.steps.remove(atOffsets: $0) }
                    .onMove { goal.steps.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Kleiner nächster Schritt", text: $newStep)
                        Button { goal.steps.append(AssistedLivingStep(title: newStep)); newStep = "" } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: { Text("Schritte") } footer: { Text("Kleine, konkrete Schritte machen Fortschritt sichtbar.") }
                if store.data.assistedLivingGoals.contains(where: { $0.id == goal.id }) {
                    Section { Button("Ziel löschen", systemImage: "trash", role: .destructive) { store.deleteAssistedLivingGoal(goal.id); dismiss() } }
                }
            }
            .therapyFormStyle()
            .navigationTitle("BeWo-Ziel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { store.saveAssistedLivingGoal(goal); dismiss() }
                        .disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Lists

struct AssistedLivingTopicsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: AssistedLivingTopic?
    @State private var status: AssistedLivingTopicStatus?

    var body: some View {
        List {
            Section {
                Picker("Stand", selection: $status) {
                    Text("Alle").tag(AssistedLivingTopicStatus?.none)
                    ForEach(AssistedLivingTopicStatus.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            ForEach(AssistedLivingTopicCategory.allCases) { category in
                let topics = store.data.assistedLivingTopics.filter { $0.category == category && (status == nil || $0.status == status) }
                if !topics.isEmpty {
                    Section(category.title) {
                        ForEach(topics) { topic in
                            Button { editing = topic } label: {
                                HStack {
                                    Image(systemName: topic.status.symbol).foregroundStyle(topic.status.isOpen ? Color.orange : Color.green)
                                    VStack(alignment: .leading) {
                                        Text(topic.title).foregroundStyle(.primary)
                                        if !topic.outcome.isEmpty { Text(topic.outcome).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Löschen", role: .destructive) { store.deleteAssistedLivingTopic(topic.id) }
                                if topic.status.isOpen { Button("Erledigt") { store.setTopicStatus(topic.id, .done) }.tint(.green) }
                            }
                        }
                    }
                }
            }
            if store.data.assistedLivingTopics.isEmpty {
                ContentUnavailableView("Noch keine Themen", systemImage: "text.bubble", description: Text("Sammle hier, was du mit deiner Betreuung besprechen möchtest."))
            }
        }
        .therapyFormStyle()
        .navigationTitle("Themen")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Neu", systemImage: "plus") { editing = AssistedLivingTopic() } } }
        .sheet(item: $editing) { AssistedLivingTopicEditor(topic: $0) }
    }
}

struct AssistedLivingHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: AssistedLivingAppointment?

    var body: some View {
        let past = store.data.assistedLivingAppointments.filter { $0.status != .planned || $0.end <= Date() }.sorted { $0.date > $1.date }
        List {
            if past.isEmpty {
                ContentUnavailableView("Noch keine vergangenen Termine", systemImage: "clock.arrow.circlepath")
            }
            ForEach(past) { appointment in
                Button { editing = appointment } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(appointment.date.formatted(date: .abbreviated, time: .shortened), systemImage: appointment.kind.symbol).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(appointment.status == .cancelled ? "Abgesagt" : BeWoMood.face(appointment.moodBefore) + " → " + BeWoMood.face(appointment.moodAfter)).font(.caption)
                        }
                        .foregroundStyle(.primary)
                        if !appointment.summary.isEmpty { Text(appointment.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        let done = appointment.agreements.filter(\.done).count
                        if !appointment.agreements.isEmpty { Text("Absprachen: \(done)/\(appointment.agreements.count) erledigt").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            .onDelete { offsets in for index in offsets { store.deleteAssistedLivingAppointment(past[index].id) } }
        }
        .therapyFormStyle()
        .navigationTitle("Vergangene Termine")
        .sheet(item: $editing) { AssistedLivingAppointmentEditor(appointment: $0) }
    }
}

// MARK: - Settings

struct AssistedLivingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingVisit: AssistedLivingRegularVisit?
    @State private var newPrompt = ""

    var body: some View {
        Form {
            Section("Meine Betreuung") {
                TextField("Träger / Dienst", text: $store.data.assistedLivingSettings.providerName)
                TextField("Name der Betreuer:in", text: $store.data.assistedLivingSettings.caregiverName)
                TextField("Telefon Betreuer:in", text: $store.data.assistedLivingSettings.caregiverPhone).keyboardType(.phonePad)
                TextField("Telefon Büro", text: $store.data.assistedLivingSettings.officePhone).keyboardType(.phonePad)
                TextField("Üblicher Ort", text: $store.data.assistedLivingSettings.defaultLocation)
                Stepper("Übliche Dauer: \(store.data.assistedLivingSettings.defaultDurationMinutes) Min.", value: $store.data.assistedLivingSettings.defaultDurationMinutes, in: 15...480, step: 15)
                Stepper("Bewilligte Stunden pro Woche: " + hoursLabel, value: Binding(get: { store.data.assistedLivingSettings.hoursPerWeek ?? 0 }, set: { store.data.assistedLivingSettings.hoursPerWeek = $0 <= 0 ? nil : $0 }), in: 0...40, step: 0.5)
            }
            Section {
                ForEach(store.data.assistedLivingSettings.regularVisits) { visit in
                    Button { editingVisit = visit } label: {
                        HStack {
                            Label(visit.label, systemImage: visit.kind.symbol).foregroundStyle(visit.enabled ? Color.primary : Color.secondary)
                            Spacer()
                            Text("\(visit.durationMinutes) Min.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { store.data.assistedLivingSettings.regularVisits.remove(atOffsets: $0) }
                Button("Regelmäßigen Termin hinzufügen", systemImage: "plus.circle.fill") {
                    editingVisit = AssistedLivingRegularVisit(durationMinutes: store.data.assistedLivingSettings.defaultDurationMinutes)
                }
            } header: { Text("Regelmäßige Termine") } footer: { Text("Regelmäßige Termine erscheinen automatisch. Einzelne kannst du ausfallen lassen oder öffnen, um Themen und Notizen anzuhängen.") }
            Section {
                Toggle("Erinnerungen", isOn: $store.data.assistedLivingSettings.remindersEnabled)
                if store.data.assistedLivingSettings.remindersEnabled {
                    ForEach([2880, 1440, 180, 60, 30, 0], id: \.self) { offset in
                        Toggle(offsetTitle(offset), isOn: Binding(get: { store.data.assistedLivingSettings.reminderOffsetsMinutes.contains(offset) }, set: { on in
                            var values = Set(store.data.assistedLivingSettings.reminderOffsetsMinutes); if on { values.insert(offset) } else { values.remove(offset) }
                            store.data.assistedLivingSettings.reminderOffsetsMinutes = values.sorted(by: >)
                        }))
                    }
                    Toggle("Zusätzlich als Wecker (AlarmKit)", isOn: $store.data.assistedLivingSettings.alarmEnabled)
                }
                Toggle("Neutrale Texte auf dem Sperrbildschirm", isOn: $store.data.assistedLivingSettings.privateTitles)
                Button("Ruhe & alle Erinnerungen verwalten", systemImage: "moon.zzz.fill") { store.notificationQuietCenter = true }
            } header: { Text("Erinnerungen") }
            Section {
                ForEach(store.data.assistedLivingSettings.preparationPrompts, id: \.self) { prompt in Text(prompt) }
                    .onDelete { store.data.assistedLivingSettings.preparationPrompts.remove(atOffsets: $0) }
                HStack {
                    TextField("Eigene Vorbereitungsfrage", text: $newPrompt)
                    Button { store.data.assistedLivingSettings.preparationPrompts.append(newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)); newPrompt = "" } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: { Text("Vorbereitungsfragen") }
            Section("Notizen zur Betreuung") {
                TextField("Hilfeplan, Ziele aus dem Gesamtplan, Ansprechpartner …", text: $store.data.assistedLivingSettings.notes, axis: .vertical).lineLimit(3...10)
            }
        }
        .therapyFormStyle()
        .navigationTitle("BeWo-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingVisit) { visit in AssistedLivingRegularVisitEditor(visit: visit) }
    }

    private var hoursLabel: String {
        guard let hours = store.data.assistedLivingSettings.hoursPerWeek else { return "–" }
        return hours.formatted(.number.precision(.fractionLength(0...1))) + " Std."
    }

    private func offsetTitle(_ offset: Int) -> String {
        switch offset {
        case 0: "Zum Beginn"
        case 1440: "Am Tag davor"
        case 2880: "Zwei Tage vorher"
        default: offset >= 60 ? "\(offset / 60) Std. vorher" : "\(offset) Min. vorher"
        }
    }
}

struct AssistedLivingRegularVisitEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var visit: AssistedLivingRegularVisit

    var body: some View {
        NavigationStack {
            Form {
                Picker("Wochentag", selection: $visit.weekday) { ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(TherapyDateHelper.weekdayName($0)).tag($0) } }
                DatePicker("Uhrzeit", selection: Binding(get: { Calendar.current.date(bySettingHour: visit.hour, minute: visit.minute, second: 0, of: Date()) ?? Date() }, set: {
                    visit.hour = Calendar.current.component(.hour, from: $0); visit.minute = Calendar.current.component(.minute, from: $0)
                }), displayedComponents: .hourAndMinute)
                Stepper(visit.everyWeeks == 1 ? "Jede Woche" : "Alle \(visit.everyWeeks) Wochen", value: $visit.everyWeeks, in: 1...8)
                DatePicker("Ab", selection: $visit.anchor, displayedComponents: .date)
                Stepper("Dauer: \(visit.durationMinutes) Min.", value: $visit.durationMinutes, in: 15...480, step: 15)
                Picker("Art", selection: $visit.kind) { ForEach(AssistedLivingVisitKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                Toggle("Aktiv", isOn: $visit.enabled)
            }
            .therapyFormStyle()
            .navigationTitle("Regelmäßiger Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var settings = store.data.assistedLivingSettings
                        settings.regularVisits.removeAll { $0.id == visit.id }
                        settings.regularVisits.append(visit)
                        store.data.assistedLivingSettings = settings
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Home card

struct AssistedLivingHomeCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = AssistedLivingPlanner.next(store.data, now: context.date)
            let topics = AssistedLivingPlanner.openTopics(store.data)
            Button { store.selectedTab = TherapyTab.assistedLiving } label: {
                HStack(spacing: 14) {
                    TherapyIconTile(icon: next?.kind.symbol ?? "house.fill", size: 46, tint: .brown)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Betreutes Wohnen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(next.map { AssistedLivingPlanner.countdown(to: $0.date, now: context.date) } ?? "Kein Termin geplant").font(.headline).foregroundStyle(.primary)
                        Text(topics.isEmpty ? "Themen sammeln" : (topics.count == 1 ? "1 offenes Thema" : "\(topics.count) offene Themen")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(TherapyPressStyle())
            .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.cardRadius, style: .continuous), interactive: true)
            .accessibilityIdentifier("today.bewo")
        }
    }
}
