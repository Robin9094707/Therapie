import SwiftUI
import UIKit

private let phaseColors: [Color] = [.indigo, .teal, .orange, .purple, .blue, .pink, .mint, .brown]

struct SessionConductorView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { SessionConductorContent(controller: store.sessionController) }
}

struct SessionConductorContent: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: TherapySessionController
    @State private var templateDraft: TherapySessionTemplate?
    @State private var noteDraft: TherapyNote?
    @State private var historyDraft: RunningTherapySession?
    @State private var deletingTemplate: TherapySessionTemplate?
    @State private var deletingHistory: RunningTherapySession?
    @State private var showDelete = false
    @State private var finish = false
    @State private var showPreferences = false
    @State private var showAI = false
    @State private var voiceActive = false

    var body: some View {
        TherapyScreen {
            VStack(spacing: 16) {
                if let session = store.data.currentSession {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in activeCard(session, now: context.date) }
                    TherapyDiscussionCard(alwaysVisible: true)
                    if store.data.aiSettings.enabled { Button { showAI = true } label: { Label("KI-Begleiter für diese Stunde", systemImage: "sparkles") }.buttonStyle(.glass) }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Während der Stunde", systemImage: "square.and.pencil").font(.headline)
                            Button("Schnelle Notiz festhalten", systemImage: "plus.circle") {
                                let phase = session.phaseIndex().map { session.phases[$0].title } ?? "Rückblick"
                                noteDraft = TherapyNote(title: phase, text: "", tags: ["Therapiestunde"], topicID: store.data.therapyTopics.first(where: \.isCurrent)?.id, sessionID: session.id)
                            }
                            if store.data.aiSettings.enabled { HStack { BuddyInlineMicrophone(onStateChange: { voiceActive = $0 }) { transcript in var snapshot = store.data; snapshot.notes.insert(TherapyNote(title: "Gedanke aus der Stunde", text: transcript, tags: ["Therapiestunde", "Sprachnotiz"], sessionID: session.id), at: 0); store.data = snapshot }; Text("Gedanken einsprechen · direkt als Notiz speichern").font(.caption).foregroundStyle(.secondary) } }
                            ForEach(store.data.therapyTopics.filter(\.isCurrent)) { topic in
                                Label(topic.title, systemImage: topic.category.symbol).font(.subheadline)
                            }
                        }
                    }
                    TherapyNotesCollectionView(sessionID: session.id)
                } else {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Zeit für deine Therapiestunde", icon: "timer", subtitle: "Einmal starten. Der Timer bleibt auch nach dem Verlassen der App erhalten.")
                            Text("Wähle eine Vorlage oder passe deine Phasen an. Der farbige Zeitkreis zeigt die Abschnitte und den aktuellen Fortschritt.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.data.currentSession == nil { TherapyDiscussionCard(alwaysVisible: true) }
                templates
                history
            }
        }
        .navigationTitle("Therapiezeit").interactiveDismissDisabled(voiceActive)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showPreferences = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Timer-Einstellungen") }
        }
        .sheet(item: $templateDraft) { SessionTemplateEditorView(template: $0) }
        .sheet(item: $noteDraft) { TherapyNoteEditorView(note: $0) }
        .sheet(item: $historyDraft) { SessionHistoryEditorView(session: $0) }
        .sheet(isPresented: $showAI) { AIBuddyEntryView() }
        .sheet(isPresented: $showPreferences) { NavigationStack { SessionPreferencesView(controller: controller) } }
        .alert("Stunde vorzeitig beenden?", isPresented: $finish) {
            Button("Weiterlaufen lassen", role: .cancel) {}
            Button("Beenden") { controller.finish(early: true) }
        } message: { Text("Die Stunde wird in deinem Verlauf gespeichert. Deine Notizen bleiben erhalten.") }
        .alert("Eintrag löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let item = deletingTemplate { store.data.sessionTemplates.removeAll { $0.id == item.id } }
                if let item = deletingHistory {
                    var snapshot = store.data
                    snapshot.sessionHistory.removeAll { $0.id == item.id }
                    for i in snapshot.notes.indices where snapshot.notes[i].sessionID == item.id { snapshot.notes[i].sessionID = nil }
                    store.data = snapshot
                }
                deletingTemplate = nil; deletingHistory = nil
            }
        } message: { Text(deletingTemplate != nil ? "Die Vorlage wird gelöscht. Eine laufende Stunde und frühere Sitzungen bleiben erhalten." : "Die Sitzung wird aus dem Verlauf gelöscht. Ihre Notizen bleiben ohne Sitzungszuordnung erhalten.") }
        .task {
            controller.synchronize()
            while !Task.isCancelled {
                controller.reconcile()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.synchronize() } }
    }
    private func activeCard(_ session: RunningTherapySession, now: Date) -> some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(session.title).font(.title2.bold())
                    Spacer()
                    if session.pausedAt != nil { Label("Pause", systemImage: "pause.circle").font(.caption.bold()) }
                }
                SessionClockFace(session: session, now: now).frame(maxWidth: 320).frame(maxWidth: .infinity)
                if let index = session.phaseIndex(at: now) {
                    let phase = session.phases[index]
                    Label("Jetzt: " + phase.title, systemImage: "arrow.right.circle.fill").font(.headline)
                    if index + 1 < session.phases.count { Text("Danach: " + session.phases[index + 1].title).font(.subheadline).foregroundStyle(.secondary) }
                }
                ForEach(Array(session.phases.enumerated()), id: \.element.id) { index, phase in
                    HStack(alignment: .top) {
                        Circle().fill(phaseColors[abs(phase.colorIndex) % phaseColors.count]).frame(width: 10, height: 10).padding(.top, 4).accessibilityHidden(true)
                        Text(phase.title).font(.subheadline)
                        Spacer()
                        Text("\(phase.minutes) Min.").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if index == session.phaseIndex(at: now) { Image(systemName: "arrow.left").font(.caption).accessibilityLabel("Aktueller Abschnitt") }
                    }
                }
                ResponsiveButtonRow {
                    Button(session.pausedAt == nil ? "Pausieren" : "Fortsetzen", systemImage: session.pausedAt == nil ? "pause.fill" : "play.fill") { controller.pauseOrResume() }.buttonStyle(.glassProminent)
                    Button("Beenden", systemImage: "stop") { finish = true }.buttonStyle(.glass).disabled(voiceActive)
                }
                LiveActivityStatusRow(controller: controller, enabled: store.data.sessionPreferences.liveActivityEnabled)
                Text(store.data.sessionPreferences.usesPrivateLiveActivity ? "Die Live-Aktivität zeigt neutrale Abschnittsnamen. Echte Namen kannst du in den Timer-Einstellungen einschalten." : "Die Live-Aktivität zeigt deine Abschnittsnamen. Notizen bleiben in der App; neutrale Namen sind in den Timer-Einstellungen wählbar.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var templates: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Deine Stundenpläne").font(.headline)
                Spacer()
                Button { templateDraft = TherapySessionTemplate(title: "Neuer Stundenplan") } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Stundenplan erstellen")
            }
            if store.data.sessionTemplates.isEmpty { GlassCard { Text("Lege einen Stundenplan an. Jede Phase und Dauer lässt sich anpassen.").font(.subheadline) } }
            ForEach(store.data.sessionTemplates) { template in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title).font(.headline)
                                Text("\(template.totalMinutes) Minuten · \(template.phases.count) Phasen").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { templateDraft = template }
                                Button("Duplizieren", systemImage: "doc.on.doc") { var copy = template; copy.id = UUID(); copy.title += " – Kopie"; templateDraft = copy }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deletingTemplate = template; deletingHistory = nil; showDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Text(template.phases.map { "\($0.title) (\($0.minutes) Min.)" }.joined(separator: " → ")).font(.subheadline).foregroundStyle(.secondary)
                        Button("Stunde starten", systemImage: "play.circle.fill") { controller.start(template) }
                            .buttonStyle(.glassProminent).disabled(store.data.currentSession != nil || !template.isValid)
                    }
                }
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bisherige Stunden").font(.headline)
            ForEach(store.data.sessionHistory.sorted { $0.startedAt > $1.startedAt }) { session in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).font(.headline)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Rückblick bearbeiten", systemImage: "pencil") { historyDraft = session }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deletingHistory = session; deletingTemplate = nil; showDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Label(session.endedEarly ? "Vorzeitig beendet" : "Geplante Zeit beendet", systemImage: session.endedEarly ? "stop.circle" : "checkmark.circle").font(.caption)
                        Text("\(Int(session.elapsed() / 60)) Minuten begleitet").font(.caption).foregroundStyle(.secondary)
                        if !session.summary.isEmpty { Text(session.summary).font(.subheadline).lineLimit(3) }
                        Button("Notizen & Rückblick öffnen") { historyDraft = session }.font(.subheadline.bold())
                    }
                }
            }
        }
    }
}

struct SessionClockFace: View {
    let session: RunningTherapySession
    let now: Date
    private var progress: Double { session.totalSeconds > 0 ? session.elapsed(at: now) / session.totalSeconds : 0 }
    var body: some View {
        ZStack {
            Canvas { context, size in
                // Ring of phases: the planned part is a soft track, the elapsed part fills in full colour.
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let lineWidth = max(14, min(size.width, size.height) * 0.075)
                let radius = min(size.width, size.height) / 2 - lineWidth / 2 - 6
                let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                let elapsedAngle = -90 + min(1, max(0, progress)) * 360
                var offset = -90.0
                for phase in session.phases {
                    let angle = session.totalSeconds > 0 ? Double(max(1, phase.minutes) * 60) / session.totalSeconds * 360 : 0
                    // Round caps reach half the line width past each end; keep a visible gap between phases.
                    let capDegrees = Double(lineWidth / 2 / max(1, radius)) * 180 / .pi
                    let gap: Double = session.phases.count > 1 ? min(capDegrees + 1.5, angle * 0.45) : 0
                    let color = phaseColors[abs(phase.colorIndex) % phaseColors.count]
                    let start = offset + gap, end = offset + angle - gap
                    if end > start {
                        var track = Path()
                        track.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                        context.stroke(track, with: .color(color.opacity(0.22)), style: style)
                        let filled = min(end, elapsedAngle)
                        if filled > start {
                            var done = Path()
                            done.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(filled), clockwise: false)
                            context.stroke(done, with: .color(color), style: style)
                        }
                    }
                    offset += angle
                }
                let radians = elapsedAngle * .pi / 180
                let knob = CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
                let knobRect = CGRect(x: knob.x - lineWidth * 0.62, y: knob.y - lineWidth * 0.62, width: lineWidth * 1.24, height: lineWidth * 1.24)
                context.fill(Path(ellipseIn: knobRect), with: .color(.white))
                context.stroke(Path(ellipseIn: knobRect), with: .color(.black.opacity(0.18)), lineWidth: 1)
            }
            VStack(spacing: 4) {
                Text(session.pausedAt == nil ? "Restzeit" : "Pausiert").font(.caption).foregroundStyle(.secondary)
                Text(Self.format(session.remaining(at: now))).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText(countsDown: true))
                Text("\(Int(progress * 100)) % vergangen").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 160)
        }.aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Therapiezeit, \(Int(ceil(session.remaining(at: now) / 60))) Minuten verbleibend, \(Int(progress * 100)) Prozent vergangen")
    }
    static func format(_ seconds: TimeInterval) -> String {
        let remaining = max(0, Int(ceil(seconds)))
        return remaining >= 3600 ? String(format: "%d:%02d:%02d", remaining / 3600, remaining / 60 % 60, remaining % 60) : String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}

struct SessionTemplateEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var template: TherapySessionTemplate
    @State private var deletingPhase: UUID?
    @State private var confirmDelete = false
    private let initial: TherapySessionTemplate
    init(template: TherapySessionTemplate) { initial = template; _template = State(initialValue: template) }
    var body: some View {
        TherapyEditorSheet(title: "Stundenplan bearbeiten", dirty: template != initial, canSave: template.isValid, draftID: template.id, saveDraft: { store.saveEditorDraft(template, id: template.id, kind: "sessionTemplate", title: template.title) }, save: { store.saveSessionTemplate(template) }) {
            Section {
                TextField("Name des Stundenplans", text: $template.title)
                Text("Gesamt: \(template.totalMinutes) Minuten").font(.headline)
                TextField("Hinweis für mich", text: $template.note, axis: .vertical).lineLimit(2...5)
            } footer: { Text("1 bis 12 Phasen, insgesamt bis zu 4 Stunden. Änderungen gelten für die nächste Stunde; ein laufender Timer behält seinen Plan.") }
            Section("Phasen · mit den Pfeilen sortieren") {
                ForEach(template.phases) { value in
                    let phase = identifiedEditorBinding($template.phases, to: value)
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("Phasenname", text: phase.title)
                        Stepper("\(phase.wrappedValue.minutes) Minuten", value: phase.minutes, in: 1...180)
                        HStack {
                            Picker("Farbe", selection: phase.colorIndex) { ForEach(0..<phaseColors.count, id: \.self) { Text("Farbe \($0 + 1)").tag($0) } }.labelsHidden()
                            Spacer()
                            Button { move(value.id, by: -1) } label: { Image(systemName: "arrow.up").frame(width: 36, height: 36) }.buttonStyle(.borderless).accessibilityLabel("Phase nach oben")
                            Button { move(value.id, by: 1) } label: { Image(systemName: "arrow.down").frame(width: 36, height: 36) }.buttonStyle(.borderless).accessibilityLabel("Phase nach unten")
                            Button(role: .destructive) { deletingPhase = value.id; confirmDelete = true } label: { Image(systemName: "trash").frame(width: 36, height: 36) }.buttonStyle(.borderless).disabled(template.phases.count <= 1)
                        }
                    }.padding(.vertical, 4)
                }
                Button("Phase ergänzen", systemImage: "plus.circle") { template.phases.append(SessionPhase(title: "Neuer Abschnitt", minutes: 5, colorIndex: template.phases.count % phaseColors.count)) }.disabled(template.phases.count >= 12)
            }
            if !template.isValid { Section { Text("Bitte benenne alle Phasen und halte die Gesamtdauer zwischen 1 und 240 Minuten.").font(.caption).foregroundStyle(.secondary) } }
        }
        .alert("Phase entfernen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) { template.phases.removeAll { $0.id == deletingPhase } }
        }
    }
    private func move(_ id: UUID, by distance: Int) {
        guard let index = template.phases.firstIndex(where: { $0.id == id }), template.phases.indices.contains(index + distance) else { return }
        template.phases.swapAt(index, index + distance); TherapyEffects.shared.light()
    }
}

struct SessionHistoryEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var session: RunningTherapySession
    private let initial: RunningTherapySession
    init(session: RunningTherapySession) { initial = session; _session = State(initialValue: session) }
    var body: some View {
        TherapyEditorSheet(title: "Sitzungsrückblick", dirty: session != initial, canSave: !session.title.isEmpty, save: {
            if let index = store.data.sessionHistory.firstIndex(where: { $0.id == session.id }) { store.data.sessionHistory[index] = session }
        }) {
            Section("Rückblick") {
                TextField("Titel", text: $session.title)
                Text(session.startedAt.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                TextField("Was möchte ich aus dieser Stunde behalten?", text: $session.summary, axis: .vertical).lineLimit(3...10)
                TextField("Mein nächster Schritt", text: $session.nextStep, axis: .vertical).lineLimit(2...6)
            }
            Section("Notizen zu dieser Stunde") { TherapyNotesCollectionView(sessionID: session.id) }
        }
    }
}

struct SessionPreferencesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: TherapySessionController
    var body: some View {
        Form {
            Section("Live-Aktivität") {
                Toggle("Sperrbildschirm & Dynamic Island", isOn: $store.data.sessionPreferences.liveActivityEnabled)
                Toggle("Echte Abschnittsnamen anzeigen", isOn: Binding(get: { !store.data.sessionPreferences.usesPrivateLiveActivity }, set: { store.data.sessionPreferences.showLiveActivityNames($0); controller.synchronize() }))
                Text("Restzeit, Ring und Abschnittsbalken laufen auch ohne geöffnete App weiter. An jeder Abschnittsgrenze zeichnet iOS den Abschnittsnamen neu, am Ende erscheint „Geschafft“. Fehlt die Anzeige einmal, hilft „Dynamic Island neu verbinden“ in der laufenden Stunde.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Mitteilungen") {
                Toggle("Am Ende der Stunde erinnern", isOn: $store.data.sessionPreferences.notifyAtEnd)
                Toggle("Bei jedem Phasenwechsel erinnern", isOn: $store.data.sessionPreferences.notifyAtPhases)
                Toggle("Wecker am Ende der Stunde", isOn: Binding(get: { store.data.companionSettings.sessionAlarmsEnabled ?? false }, set: { store.data.companionSettings.sessionAlarmsEnabled = $0 }))
                Toggle("Wecker nach jedem Abschnitt", isOn: Binding(get: { store.data.companionSettings.sessionPhaseAlarmsEnabled ?? (store.data.companionSettings.sessionAlarmsEnabled == true && store.data.sessionPreferences.notifyAtPhases) }, set: { store.data.companionSettings.sessionPhaseAlarmsEnabled = $0 }))
                Text("Abschnittswecker nennen den abgeschlossenen und den nächsten Abschnitt. Pause, Fortsetzen und Beenden aktualisieren die geplanten Wecker. Sie funktionieren unabhängig von Mitteilungen.").font(.caption).foregroundStyle(.secondary)
                Button("AlarmKit-Wecker freigeben", systemImage: "alarm") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store) } }
                Text(store.routineAlarmStatus).font(.caption).foregroundStyle(.secondary)
                Text("Mitteilungen benötigen deine Freigabe. Es werden keine Notiz- oder Themeninhalte angezeigt.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Einstellungen für laufende Stunde übernehmen") { controller.synchronize() }.disabled(controller.busy)
            if !controller.liveStatus.isEmpty { Text(controller.liveStatus).font(.caption) }
            Link("iPhone-Einstellungen öffnen", destination: URL(string: UIApplication.openSettingsURLString)!)
        }.therapyFormStyle()
        .navigationTitle("Timer-Einstellungen")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { controller.synchronize(); dismiss() } } }
    }
}

/// Shows whether the Lock Screen / Dynamic Island activity is running and offers a manual reconnect.
private struct LiveActivityStatusRow: View {
    @ObservedObject var controller: TherapySessionController
    let enabled: Bool

    var body: some View {
        let active = controller.liveStatus.hasPrefix("Live-Aktivität aktiv") || controller.liveStatus.hasPrefix("Live-Aktivität neu verbunden")
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(controller.liveStatus.isEmpty ? "Live-Aktivität wird vorbereitet …" : controller.liveStatus)
            } icon: {
                Image(systemName: active ? "checkmark.circle.fill" : enabled ? "exclamationmark.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(active ? Color.green : enabled ? Color.orange : Color.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if enabled {
                Button("Dynamic Island neu verbinden", systemImage: "arrow.triangle.2.circlepath") { controller.reconnectLiveActivity() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
                    .accessibilityHint("Startet die Live-Aktivität dieser Stunde neu, falls sie im Sperrbildschirm oder in der Dynamic Island fehlt.")
            }
        }
    }
}
