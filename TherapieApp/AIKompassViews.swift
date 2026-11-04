import SwiftUI

// MARK: - Interactive AI action cards (Kompass 6)

extension AIBuddyActionKind {
    var tint: Color {
        switch self {
        case .bewoAppointment, .bewoTopic, .bewoAgreement, .bewoGoal, .bewoSummary, .discussBewoTopic: .brown
        case .quietStart, .quietEnd: .indigo
        case .deleteTask, .deleteRoutine, .deleteNote, .deleteTopic, .deleteGoal, .deleteMethod: .red
        case .task, .completeTask, .reopenTask, .postponeTask, .updateTask: .blue
        case .routine, .completeRoutine, .skipRoutine, .postponeRoutine, .updateRoutine, .shower: .green
        case .mood, .checkIn, .guidedCheckIn: .yellow
        case .energy, .battery: .orange
        case .appointment, .startSession, .reflection, .topic, .discussTopic, .updateTopic: .teal
        case .note, .updateNote, .editEntry: .orange
        case .goal, .updateGoal, .goalProgress: .green
        case .method, .thoughtStop, .updateMethod, .emergencyPlan: .purple
        case .setting, .openScreen: .gray
        }
    }
    var showsDateBadge: Bool { [.bewoAppointment, .appointment, .task, .routine, .postponeTask, .postponeRoutine].contains(self) }
}

/// All proposals of one reply: a card each, plus "Alle übernehmen" for the ones a tap may save.
struct AIActionDeck: View {
    @EnvironmentObject private var store: AppStore
    let message: AIBuddyMessage
    let actions: [AIBuddyAction]
    let open: (AIBuddyAction) -> Void
    let apply: (AIBuddyAction) -> Void
    let applyAll: ([AIBuddyAction]) -> Void

    var body: some View {
        let pending = actions.filter { !message.appliedActionIDs.contains($0.id) }
        let quick = pending.filter { KompassAI.quickApply.contains($0.kind) }
        VStack(alignment: .leading, spacing: 10) {
            if actions.count > 1 {
                HStack {
                    Label(pending.isEmpty ? "Alles übernommen" : "\(pending.count) Vorschläge", systemImage: pending.isEmpty ? "checkmark.seal.fill" : "wand.and.stars")
                        .font(.caption.weight(.bold)).foregroundStyle(pending.isEmpty ? Color.green : Color.secondary)
                    Spacer()
                    if quick.count > 1 {
                        Button("Alle \(quick.count) übernehmen", systemImage: "checkmark.circle.fill") { applyAll(quick) }
                            .buttonStyle(.glassProminent).font(.caption.weight(.bold))
                            .accessibilityIdentifier("ai.action.applyAll")
                    }
                }
            }
            ForEach(actions) { action in
                AIActionCard(action: action, applied: message.appliedActionIDs.contains(action.id), open: { open(action) }, apply: { apply(action) })
            }
        }
    }
}

struct AIActionCard: View {
    @EnvironmentObject private var store: AppStore
    let action: AIBuddyAction
    let applied: Bool
    let open: () -> Void
    let apply: () -> Void

    private var direct: Bool { [.openScreen, .guidedCheckIn, .editEntry].contains(action.kind) }
    private var quick: Bool { KompassAI.quickApply.contains(action.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.kind.label).font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(action.kind.tint)
                    if !action.title.isEmpty { Text(AIBuddyText.plain(action.title)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
                    let detail = KompassAI.detail(action, data: store.data)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    if !action.text.isEmpty && !direct { Text(AIBuddyText.plain(action.text)).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }
                Spacer(minLength: 0)
            }
            if applied {
                HStack {
                    Label("Gespeichert", systemImage: "checkmark.circle.fill").font(.caption.weight(.bold)).foregroundStyle(.green)
                    Spacer()
                    if let destination { Button("Ansehen", systemImage: "arrow.up.right") { show(destination) }.font(.caption.weight(.semibold)) }
                }
            } else if direct {
                Button(action: open) { Label(action.kind == .openScreen ? "Öffnen" : action.kind == .guidedCheckIn ? "Check-in starten" : "Im Editor öffnen", systemImage: action.kind.symbol).frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
            } else if quick {
                HStack(spacing: 8) {
                    Button(action: apply) { Label("Übernehmen", systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("ai.action.apply." + action.kind.rawValue)
                    Button(action: open) { Label("Anpassen", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.glass)
                }
            } else {
                Button(action: open) { Label(reviewTitle, systemImage: "checkmark.shield").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(14)
        .background(action.kind.tint.opacity(applied ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(action.kind.tint.opacity(applied ? 0.15 : 0.3), lineWidth: 1) }
        .opacity(applied ? 0.8 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.action." + action.kind.rawValue)
    }

    private var reviewTitle: String {
        if [.deleteTask, .deleteRoutine, .deleteNote, .deleteTopic, .deleteGoal, .deleteMethod].contains(action.kind) { return "Prüfen & entfernen" }
        if [.completeTask, .completeRoutine, .shower].contains(action.kind) { return "Prüfen & abhaken" }
        return "Prüfen & speichern"
    }

    @ViewBuilder private var badge: some View {
        if action.kind.showsDateBadge, let date = action.date {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 2).background(action.kind.tint)
                Text(date.formatted(.dateTime.day())).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 44, height: 46)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(action.kind.tint.opacity(0.4), lineWidth: 1) }
            .accessibilityHidden(true)
        } else {
            TherapyIconTile(icon: action.kind.symbol, size: 40, tint: action.kind.tint)
        }
    }

    private enum Destination { case bewo, quiet, therapy, today }
    private var destination: Destination? {
        switch action.kind {
        case .bewoAppointment, .bewoTopic, .bewoAgreement, .bewoGoal, .bewoSummary, .discussBewoTopic: .bewo
        case .quietStart, .quietEnd: .quiet
        case .topic, .appointment, .goal, .discussTopic: .therapy
        case .task, .routine, .note: .today
        default: nil
        }
    }
    private func show(_ destination: Destination) {
        switch destination {
        case .bewo: store.selectedTab = TherapyTab.assistedLiving
        case .quiet: store.notificationQuietCenter = true
        case .therapy: store.selectedTab = TherapyTab.therapy
        case .today: store.selectedTab = TherapyTab.today
        }
    }
}

// MARK: - AI entry points across the app

/// Opens a fresh companion chat that immediately asks the given question. Hidden when the AI is not set up, so
/// the app stays complete without it.
struct AIAskButton: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    let question: String
    var icon = "sparkles"
    var prominent = false
    @State private var presented = false

    var body: some View {
        if store.data.aiSettings.enabled {
            Group {
                if prominent {
                    Button { presented = true } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
                } else {
                    Button { presented = true } label: { Label(title, systemImage: icon) }.buttonStyle(.glass)
                }
            }
            .tint(.indigo)
            .sheet(isPresented: $presented) { AIBuddyEntryView(initialQuestion: question) }
        }
    }
}

/// A compact card offering a few AI shortcuts for one area.
struct AIShortcutStrip: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    let prompts: [(title: String, icon: String, question: String)]

    var body: some View {
        if store.data.aiSettings.enabled {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "sparkles").font(.system(.headline, design: .rounded)).foregroundStyle(.indigo)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(prompts.indices, id: \.self) { index in
                            AIAskButton(title: prompts[index].title, question: prompts[index].question, icon: prompts[index].icon)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(16)
            .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.cardRadius, style: .continuous), tint: Color.indigo.opacity(0.08))
        }
    }
}

/// Suggestions when the quick capture text contains a date ("Dienstag um 10 kommt meine Betreuerin").
struct DetectedDateSuggestions: View {
    @EnvironmentObject private var store: AppStore
    let text: String
    let detected: DetectedDate
    let saved: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Termin erkannt: " + detected.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) + (detected.hasTime ? " · " + detected.date.formatted(date: .omitted, time: .shortened) : " · Uhrzeit prüfen"),
                  systemImage: "calendar.badge.plus")
                .font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("BeWo-Termin", icon: "house.fill", tint: .brown, first: detected.hint == .assistedLiving) { addAssistedLiving() }
                    chip("Therapie-Termin", icon: "leaf.fill", tint: .teal, first: detected.hint == .therapy) { addTherapy() }
                    chip("Aufgabe mit Termin", icon: "checklist", tint: .blue, first: false) { addTask() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .therapyInsetSurface()
    }

    private func chip(_ title: String, icon: String, tint: Color, first: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(first ? Color.white : Color.primary)
                .background(first ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var cleanTitle: String {
        String((text.components(separatedBy: .newlines).first ?? text).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private func addAssistedLiving() {
        let settings = store.data.assistedLivingSettings
        store.saveAssistedLivingAppointment(AssistedLivingAppointment(date: detected.date, durationMinutes: settings.defaultDurationMinutes, title: "BeWo-Termin", caregiver: settings.caregiverName, location: settings.defaultLocation, preparation: text,
                                                                      topicIDs: store.data.assistedLivingTopics.filter { $0.status == .next }.map(\.id)))
        saved("BeWo-Termin eingetragen")
    }
    private func addTherapy() {
        var appointments = store.data.schedule.extraAppointments ?? []
        guard !appointments.contains(where: { abs($0.date.timeIntervalSince(detected.date)) < 60 }) else { saved("Dieser Therapietermin existiert schon"); return }
        appointments.append(TherapyExtraAppointment(date: detected.date, title: cleanTitle.isEmpty ? "Zusatztermin" : cleanTitle))
        store.data.schedule.extraAppointments = appointments
        saved("Therapie-Zusatztermin eingetragen")
    }
    private func addTask() {
        let week = detected.date.therapyWeek
        let clock = Calendar.current.dateComponents([.hour, .minute, .weekday], from: detected.date)
        let reminder = TaskReminder(enabled: true, weekdays: [clock.weekday ?? 1], hour: clock.hour ?? 9, minute: clock.minute ?? 0)
        store.data.weeklyTasks.insert(WeeklyTask(weekOfYear: week.week, yearForWeekOfYear: week.year, title: cleanTitle, details: "", reminder: reminder, dueDate: detected.date), at: 0)
        saved("Aufgabe mit Termin eingetragen")
    }
}
