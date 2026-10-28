import SwiftUI
import PhotosUI
import UIKit

struct EmergencyPlanView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var editing = false
    @State private var showAI = false
    private var plan: PersonalEmergencyPlan { store.data.emergencyPlan }
    private var panels: [EmergencyPanel] { (plan.panels ?? []).filter(\.enabled) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), alignment: .top), count: textSize.isAccessibilitySize || plan.compactLayout == false ? 1 : 2) }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(plan.title, systemImage: "lifepreserver.fill").font(.headline); Spacer(); Button("Anpassen", systemImage: "slider.horizontal.3") { editing = true }.labelStyle(.iconOnly) }
                if !plan.hasContent {
                    GlassCard { VStack(alignment: .leading, spacing: 12) { Text("Deine Hilfe auf einen Blick").font(.title3.bold()); Text("Lege Gedankenstopps, kleine Schritte und Unterstützung als eigene Karten an."); Button("Plan gestalten", systemImage: "plus") { editing = true }.buttonStyle(.glassProminent) } }
                }
                if !plan.firstStep.isEmpty { helpCard("Jetzt zuerst", text: plan.firstStep, symbol: "arrow.right.circle.fill") }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(panels) { panel in
                        if let method = store.data.copingMethods.first(where: { $0.id == panel.methodID }) {
                            methodCard(method, title: panel.title.isEmpty ? method.title : panel.title, extraText: panel.text)
                        } else { helpCard(panel.title, text: panel.text, symbol: panel.symbol) }
                    }
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in helpCard("Schritt \(index + 1)", text: step, symbol: "checkmark.circle") }
                    ForEach(store.data.copingMethods.filter { method in plan.methodIDs.contains(method.id) && !panels.contains(where: { $0.methodID == method.id }) }) { method in methodCard(method, title: method.title) }
                    if !plan.warningSigns.isEmpty { helpCard("Meine Warnzeichen", text: plan.warningSigns, symbol: "bell") }
                    if !plan.support.isEmpty { helpCard("Meine Unterstützung", text: plan.support, symbol: "person.2.fill") }
                }
                if let id = plan.imageID, let item = store.data.media.first(where: { $0.id == id }) { EmergencyPlanImage(item: item).frame(maxHeight: 220) }
                NavigationLink { GroundingExerciseView() } label: { Label("5-4-3-2-1 starten", systemImage: "hand.raised.fingers.spread.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.glassProminent)
                Button("KI-Entwurf prüfen", systemImage: "sparkles") { showAI = true }.font(.footnote)
            }
        }.navigationTitle("Notfallplan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") } } }
            .sheet(isPresented: $editing) { EmergencyPlanEditorView(plan: plan) }
            .sheet(isPresented: $showAI) { SupportAIProposalView(purpose: .emergency) }
    }
    private var shareText: String { ([plan.title, plan.firstStep] + panels.map { $0.title + "\n" + $0.text } + plan.steps + [plan.warningSigns, plan.support] + store.data.copingMethods.filter { method in plan.methodIDs.contains(method.id) || panels.contains(where: { $0.methodID == method.id }) }.map { $0.title + "\n" + ([$0.details] + $0.steps).joined(separator: "\n") }).filter { !$0.isEmpty }.joined(separator: "\n\n") }
    private func helpCard(_ title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: symbol).font(.subheadline.bold()).foregroundStyle(Color.accentColor); Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
    private func methodCard(_ method: CopingMethod, title: String, extraText: String = "") -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: method.kind == .thoughtStop ? "hand.raised.fill" : "sparkles").font(.subheadline.bold()).foregroundStyle(Color.accentColor)
            if !extraText.isEmpty { Text(extraText).font(.body) }
            if !method.details.isEmpty { Text(method.details).font(.body).textSelection(.enabled) }
            ForEach(Array(method.steps.enumerated()), id: \.offset) { index, step in Text("\(index + 1). " + step).font(.body) }
            NavigationLink("Methode öffnen") { MethodDetailView(methodID: method.id) }.font(.caption)
        }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}
private struct EmergencyPlanImage: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel(item.title) }
            else { Label(item.attachmentOmitted == true ? "Bild war nicht im Backup enthalten" : "Bild nicht verfügbar", systemImage: "photo").font(.subheadline).foregroundStyle(.secondary) }
        }.task(id: item.relativePath) { if item.attachmentOmitted != true { image = UIImage(contentsOfFile: store.fileURL(for: item).path) } }
    }
}
struct EmergencyPlanEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var plan: PersonalEmergencyPlan
    @State private var stepsText = ""
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?
    @State private var initial: PersonalEmergencyPlan?
    @State private var confirmExit = false
    @State private var archive = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Hilfe-Fläche") {
                    Toggle("Kompakte Karten nebeneinander", isOn: Binding(get: { plan.compactLayout ?? true }, set: { plan.compactLayout = $0 }))
                    ForEach(plan.panels ?? []) { panel in
                        NavigationLink { EmergencyPanelEditor(panel: panel) { updated in
                            if let index = plan.panels?.firstIndex(where: { $0.id == updated.id }) { plan.panels?[index] = updated }
                        } } label: { Label(panel.title.isEmpty ? "Hilfekarte" : panel.title, systemImage: panel.symbol) }
                    }.onDelete { offsets in plan.panels?.remove(atOffsets: offsets) }.onMove { source, target in plan.panels?.move(fromOffsets: source, toOffset: target) }
                    Button("Eigene Hilfekarte", systemImage: "plus") { if plan.panels == nil { plan.panels = [] }; plan.panels?.append(EmergencyPanel(title: "Mein Gedankenstopp", symbol: "hand.raised.fill")) }
                    Text("Karten öffnen, Texte anpassen, über Bearbeiten sortieren oder löschen. Verknüpfte Methoden werden sofort mit ihren Schritten angezeigt.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Mein Plan") {
                    TextField("Titel", text: $plan.title)
                    TextField("Mein erster kleiner Schritt", text: $plan.firstStep, axis: .vertical).lineLimit(3...8)
                    TextField("Woran merke ich Überforderung?", text: $plan.warningSigns, axis: .vertical).lineLimit(2...6)
                    TextField("Wer / was hilft mir? Kontaktdaten bei Bedarf", text: $plan.support, axis: .vertical).lineLimit(3...8)
                }
                Section("Weitere Schritte · eine Zeile pro Schritt") { TextEditor(text: $stepsText).frame(minHeight: 130) }
                Section("Bild") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Bild auswählen", systemImage: "photo.badge.plus") }.disabled(importing)
                    Button("Bild aus dem Archiv", systemImage: "paperclip") { archive = true }
                    if let id = plan.imageID, let item = store.data.media.first(where: { $0.id == id }) { EmergencyPlanImage(item: item); Button("Bild vom Plan lösen", role: .destructive) { plan.imageID = nil } }
                    if importing { ProgressView("Bild wird gespeichert …") }
                    Text("Das Bild bleibt auch beim Lösen im Archiv und wird mit deinen Fotos gesichert.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Meine hilfreichen Methoden") {
                    ForEach(store.data.copingMethods) { method in
                        Toggle(method.title, isOn: Binding(get: { plan.methodIDs.contains(method.id) }, set: { selected in plan.methodIDs.removeAll { $0 == method.id }; if selected { plan.methodIDs.append(method.id) } }))
                    }
                }
                Section("Beispiel") { Button("ASMR als ersten Schritt einsetzen") { plan.firstStep = "Wenn es mir hilft: Reize reduzieren und vertrautes ASMR leise hören." } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let error = store.lastSaveError { Section { Text(error).foregroundStyle(.red) } }
            }.therapyFormStyle().navigationTitle("Notfallplan gestalten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if changed { confirmExit = true } else { dismiss() } }.disabled(importing) }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        var clean = plan; clean.steps = SupportText.steps(stepsText); clean.updatedAt = Date(); clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines); if clean.title.isEmpty { clean.title = "Mein Notfallplan" }
                        store.data.emergencyPlan = clean; if store.lastSaveError == nil { dismiss() }
                    }.disabled(importing) }
                }
        }.onAppear { if initial == nil { initial = plan; stepsText = plan.steps.joined(separator: "\n") } }
            .interactiveDismissDisabled(changed || importing)
            .onChange(of: photo) { _, item in
                guard let item else { return }; importing = true
                Task { @MainActor in
                    defer { importing = false; photo = nil }
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes) else { throw AIBuddyAPIError(message: "Das Bild konnte nicht geöffnet werden.") }
                        let size = image.size, scale = min(1, 1600 / max(size.width, size.height))
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
                        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
                        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw AIBuddyAPIError(message: "Das Bild konnte nicht gespeichert werden.") }
                        try store.importPhoto(bytes: jpeg, fileExtension: "jpg", title: "Bild für meinen Notfallplan", note: "", tags: ["Notfallplan"], location: nil)
                        guard store.lastSaveError == nil, let id = store.data.media.first?.id else { throw AIBuddyAPIError(message: store.lastSaveError ?? "Foto fehlt") }
                        plan.imageID = id; error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
            .sheet(isPresented: $archive) { EmergencyPhotoPicker { plan.imageID = $0 } }
            .alert("Änderungen verwerfen?", isPresented: $confirmExit) { Button("Weiter bearbeiten", role: .cancel) {}; Button("Verwerfen", role: .destructive) { dismiss() } }
    }
    private var changed: Bool { initial != nil && (plan != initial || SupportText.steps(stepsText) != initial?.steps) }
}
private struct EmergencyPhotoPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let choose: (UUID) -> Void
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.media.filter { $0.kind == .photo }) { item in Button { choose(item.id); dismiss() } label: { Label(item.title, systemImage: "photo") } }
            }.therapyFormStyle().navigationTitle("Bild auswählen").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }
}

struct GroundingExerciseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var answers = Array(repeating: Array(repeating: "", count: 5), count: 5)
    @State private var note = ""
    @State private var saved = false
    @State private var exit = false
    @State private var recordID = UUID()
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 20) {
                ProgressView(value: Double(step), total: 5).tint(Color.accentColor).accessibilityLabel("Übungsfortschritt")
                if step < 5 {
                    let answerStep = step
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Schritt \(step + 1) von 5").font(.headline).foregroundStyle(Color.accentColor)
                            Label(GroundingGuide.titles[step], systemImage: GroundingGuide.symbols[step]).font(.largeTitle.bold())
                            Text(GroundingGuide.hints[step]).font(.title3).foregroundStyle(.secondary)
                            ForEach(0..<GroundingGuide.counts[step], id: \.self) { index in
                                TextField("\(index + 1). Wahrnehmung · optional", text: Binding(get: { answers[answerStep][index] }, set: { answers[answerStep][index] = $0 }), axis: .vertical).font(.title3).padding(12).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)).id("\(answerStep)-\(index)")
                            }
                        }
                    }
                    Text("Du kannst Dinge laut benennen oder nur daran denken. Eingaben sind freiwillig. Jeder Schritt darf übersprungen werden.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Weiter", systemImage: "arrow.right") { step += 1 }.buttonStyle(.glassProminent).controlSize(.large)
                    Button("Diesen Sinn überspringen") { step += 1 }.buttonStyle(.glass)
                    if step > 0 { Button("Zurück") { step -= 1 } }
                } else {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Du bist angekommen", systemImage: "leaf.fill").font(.largeTitle.bold()).foregroundStyle(Color.accentColor)
                            Text("Nimm dir einen Moment. Was wäre jetzt ein angenehmer kleiner Schritt?").font(.title3)
                            TextField("Meine Notiz · optional", text: $note, axis: .vertical).lineLimit(2...6)
                            Button(saved ? "Übung gespeichert" : "Übung in meinem Verlauf speichern", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down") {
                                let values = (0..<5).map { row in Array(answers[row].prefix(GroundingGuide.counts[row])).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                                var snapshot = store.data; snapshot.groundingPractices.removeAll { $0.id == recordID }; snapshot.groundingPractices.insert(GroundingPractice(id: recordID, answers: values, note: note), at: 0); store.data = snapshot; saved = store.lastSaveError == nil
                            }.buttonStyle(.glassProminent).disabled(saved)
                            Button("Ohne Speichern schließen") { dismiss() }.disabled(saved)
                            Button("Noch einmal starten") { step = 0; answers = Array(repeating: Array(repeating: "", count: 5), count: 5); note = ""; saved = false; recordID = UUID() }
                            if saved { Button("Fertig") { dismiss() } }
                        }
                    }
                }
                if let error = store.lastSaveError { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("5-4-3-2-1").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Beenden") { if saved || (step == 0 && answers.allSatisfy { $0.allSatisfy(\.isEmpty) }) { dismiss() } else { exit = true } } } }
            .alert("Übung beenden?", isPresented: $exit) { Button("Weiter üben", role: .cancel) {}; Button("Ohne Speichern beenden", role: .destructive) { dismiss() } }
    }
}

struct ShowerTodayCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var entry: ShowerEntry?
    var showDetailsLink = true
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let count = ShowerPlanner.weekCount(store.data, at: context.date)
            let goal = max(2, min(7, store.data.showerPreferences.weeklyGoal))
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        SectionHeader(title: "Mein Duschtag", icon: "shower.fill", subtitle: count >= goal ? "Wochenziel erreicht – stark!" : "Noch \(goal - count) bis zu deinem Wochenziel")
                        Spacer(minLength: 8)
                        ShowerGoalRing(count: count, goal: goal)
                    }
                    ShowerWeekStrip(now: context.date)
                    ShowerDayActions(now: context.date)
                    HStack(spacing: 10) {
                        Button("Außer der Reihe geduscht", systemImage: "plus") { entry = ShowerEntry() }
                            .buttonStyle(.glass)
                        Spacer(minLength: 0)
                        if showDetailsLink {
                            NavigationLink { ShowerDaysView() } label: { Label("Verlauf", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
        }.sheet(item: $entry) { ShowerEntryEditor(entry: $0) }
    }
}

struct ShowerGoalRing: View {
    let count: Int
    let goal: Int
    var body: some View {
        let progress = Double(min(count, goal)) / Double(max(1, goal))
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 6)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(count)/\(goal)").font(.system(.caption, design: .rounded, weight: .bold)).monospacedDigit()
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diese Woche \(count) von \(goal) Duschtagen")
    }
}

/// Monday to Sunday at a glance: showered, planned, skipped or free.
struct ShowerWeekStrip: View {
    @EnvironmentObject private var store: AppStore
    var now: Date
    var body: some View {
        let calendar = Calendar.therapyCalendar
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                if let day = calendar.date(byAdding: .day, value: offset, to: start) { dayView(day) }
            }
        }
    }
    private func dayView(_ day: Date) -> some View {
        let showered = ShowerPlanner.showered(on: day, data: store.data)
        let planned = !ShowerPlanner.today(store.data, at: day).isEmpty
        let skipped = store.data.routineCompletions.contains { $0.outcome == .skipped && ShowerPlanner.isShower($0, data: store.data) && Calendar.current.isDate($0.scheduledAt, inSameDayAs: day) }
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
        return VStack(spacing: 6) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.caption2.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            ZStack {
                if showered {
                    Circle().fill(Color.accentColor.gradient)
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else if skipped {
                    Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                    Image(systemName: "minus").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                } else if planned {
                    Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    Image(systemName: "drop.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                } else {
                    Circle().fill(Color.primary.opacity(0.06))
                }
            }
            .frame(width: 30, height: 30)
            .overlay { if isToday { Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2).padding(-4) } }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)) + ": " + (showered ? "geduscht" : skipped ? "ausgelassen" : planned ? "geplant" : "frei"))
    }
}
struct ShowerDayActions: View {
    @EnvironmentObject private var store: AppStore
    var now: Date
    @State private var confirming: RoutineOccurrence?
    @State private var pendingSkip: RoutineOccurrence?
    @State private var error: String?
    private var today: [RoutineOccurrence] { ShowerPlanner.today(store.data, at: now) }
    private var done: Bool { ShowerPlanner.dates(store.data).contains { Calendar.current.isDate($0, inSameDayAs: now) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(done ? "Heute geduscht ✓" : today.isEmpty ? "Heute kein geplanter Duschtag" : "Heute ist Duschtag", systemImage: done ? "checkmark.seal.fill" : "shower.fill").font(.title3.bold()).foregroundStyle(Color.accentColor)
            ForEach(today) { occurrence in
                if let log = store.data.routineCompletions.first(where: { $0.routineID == occurrence.routineID && $0.timeID == occurrence.timeID && $0.scheduledAt == occurrence.scheduledAt }) {
                    Text(log.outcome == .done ? "Geplanter Duschtag erledigt" : "Heute ausgelassen · nächster regulärer Tag bleibt bestehen").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text((occurrence.originalDue == nil ? "Geplant: " : "Verschoben auf: ") + occurrence.due.formatted(date: .omitted, time: .shortened)).font(.subheadline)
                    ViewThatFits(in: .horizontal) {
                        HStack { doneButton(occurrence); postponeMenu(occurrence) }
                        VStack(alignment: .leading) { doneButton(occurrence); postponeMenu(occurrence) }
                    }
                }
            }
            if !done, today.isEmpty, let next = RoutinePlanner.occurrences(data: store.data, now: now, days: 14).first(where: { value in !RoutinePlanner.resolved(value, completions: store.data.routineCompletions) && store.data.routines.first { $0.id == value.routineID }.map(ShowerPlanner.isShower) == true && value.due > now }) {
                Text("Nächster Duschtag: " + next.due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .alert("Wirklich geduscht?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Abbrechen", role: .cancel) { confirming = nil }
            Button("Ja, erledigt") { if let confirming { resolve(confirming, outcome: .done) }; confirming = nil }
        }
        .alert("Duschtag auslassen?", isPresented: Binding(get: { pendingSkip != nil }, set: { if !$0 { pendingSkip = nil } })) {
            Button("Abbrechen", role: .cancel) { pendingSkip = nil }
            Button("Auslassen") { if let pendingSkip { resolve(pendingSkip, outcome: .skipped) }; pendingSkip = nil }
        } message: { Text("Heute wird als ausgelassen gespeichert. Der nächste reguläre Duschtag bleibt bestehen.") }
    }
    private func doneButton(_ occurrence: RoutineOccurrence) -> some View {
        Button("Geduscht", systemImage: "checkmark.circle.fill") { confirming = occurrence }.buttonStyle(.glassProminent)
    }
    private func postponeMenu(_ occurrence: RoutineOccurrence) -> some View {
        Menu {
            Button("Um einen Tag verschieben", systemImage: "calendar.badge.clock") {
                guard let date = Calendar.current.date(byAdding: .day, value: 1, to: occurrence.due) else { return }
                var snapshot = store.data
                if RoutineDayMutation.postpone(occurrence, until: date, in: &snapshot) { store.data = snapshot; error = store.lastSaveError } else { error = "Der Plan hat sich geändert. Bitte prüfe ihn erneut." }
            }
            Button("Bis zum nächsten regulären Duschtag", systemImage: "calendar") { pendingSkip = occurrence }
            Button("Heute auslassen", systemImage: "minus.circle") { pendingSkip = occurrence }
        } label: { Label("Verschieben / auslassen", systemImage: "ellipsis.circle") }.buttonStyle(.glass)
    }
    private func resolve(_ occurrence: RoutineOccurrence, outcome: RoutineOutcome) {
        var snapshot = store.data
        if RoutineDayMutation.resolve(occurrence, outcome: outcome, note: outcome == .skipped ? "Bis zum nächsten regulären Duschtag" : "", in: &snapshot) { store.data = snapshot; error = store.lastSaveError } else { error = "Dieser Duschtag ist nicht mehr offen." }
    }
}
private struct ShowerHistoryAction: Identifiable {
    enum Kind { case notShowered, showered, markWrong, unmark, delete }
    let kind: Kind
    let item: ShowerHistoryItem
    var id: String { "\(kind)-\(item.id)" }
    var title: String {
        switch kind {
        case .notShowered: "Doch nicht geduscht?"
        case .showered: "Doch geduscht?"
        case .markWrong: "Als falsch eingetragen markieren?"
        case .unmark: "Markierung aufheben?"
        case .delete: "Eintrag entfernen?"
        }
    }
    var message: String {
        switch kind {
        case .notShowered: "Der Tag zählt dann nicht mehr als Duschtag. Deine ursprüngliche Angabe bleibt im Korrekturverlauf erhalten – ganz ohne Wertung."
        case .showered: "Der Tag zählt dann als Duschtag. Die vorherige Angabe bleibt im Korrekturverlauf erhalten."
        case .markWrong: "Der Eintrag bleibt durchgestrichen sichtbar, zählt aber nicht mehr. Du kannst das jederzeit wieder aufheben."
        case .unmark: "Der Eintrag zählt danach wieder als Duschtag."
        case .delete: "Der zusätzliche Eintrag wird aus deinem Verlauf entfernt. Direkt danach kannst du das noch rückgängig machen."
        }
    }
    var confirm: String {
        switch kind {
        case .notShowered: "Nicht geduscht"
        case .showered: "Doch geduscht"
        case .markWrong: "Als falsch markieren"
        case .unmark: "Markierung aufheben"
        case .delete: "Entfernen"
        }
    }
}

struct ShowerDaysView: View {
    @EnvironmentObject private var store: AppStore
    @State private var routine: DailyRoutine?
    @State private var entry: ShowerEntry?
    @State private var pending: ShowerHistoryAction?
    @State private var error: String?
    @State private var weekOffset = 0
    @State private var historyLimit = 30
    private var week: Date { Calendar.therapyCalendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date() }
    private var weekStart: Date { Calendar.therapyCalendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week }
    private var history: [ShowerHistoryItem] { ShowerHistory.items(store.data) }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 22) {
                ShowerTodayCard(showDetailsLink: false)
                weekCard
                rhythmCard
                historySection
                NavigationLink { RoutineHistoryView() } label: { Label("Vollständiger Routinenverlauf mit Korrekturen", systemImage: "clock.arrow.circlepath") }
                    .font(.subheadline)
                    .padding(.horizontal, 4)
            }
        }.navigationTitle("Duschtage").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $routine) { RoutineEditorView(routine: $0) }
            .sheet(item: $entry) { ShowerEntryEditor(entry: $0) }
            .alert(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { action in
                Button("Abbrechen", role: .cancel) { pending = nil }
                Button(action.confirm, role: action.kind == .delete || action.kind == .notShowered || action.kind == .markWrong ? .destructive : nil) { apply(action); pending = nil }
            } message: { action in Text(action.message) }
    }

    private var weekCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Vorherige Woche", systemImage: "chevron.left") { withAnimation(.snappy) { weekOffset -= 1 } }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                    Spacer()
                    VStack(spacing: 2) {
                        Text(ArchiveGrouping.week.title(for: week)).font(.system(.headline, design: .rounded))
                        let count = ShowerPlanner.weekCount(store.data, at: week)
                        Text("\(count) von \(store.data.showerPreferences.weeklyGoal) Duschtagen").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Nächste Woche", systemImage: "chevron.right") { withAnimation(.snappy) { weekOffset += 1 } }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                }
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { offset in
                        if let day = Calendar.therapyCalendar.date(byAdding: .day, value: offset, to: weekStart) {
                            weekRow(day)
                            if offset < 6 { Divider() }
                        }
                    }
                }
                Divider()
                Stepper("Wochenziel: \(store.data.showerPreferences.weeklyGoal) Tage", value: $store.data.showerPreferences.weeklyGoal, in: 2...7)
                Text("Bestätigte Duschtage zählen einmal pro Tag. Ausgelassene oder als falsch markierte Einträge zählen nicht.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var rhythmCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Mein Rhythmus", icon: "repeat")
                ForEach(store.data.routines.filter(ShowerPlanner.isShower)) { value in
                    Button { routine = value } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.title + (value.enabled ? "" : " · pausiert")).font(.headline).foregroundStyle(.primary)
                                Text(value.repeatEveryDays == 2 ? "Alle zwei Tage ab " + (value.recurrenceAnchor ?? value.createdAt).formatted(date: .abbreviated, time: .omitted) : value.times.map { $0.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ") + String(format: " · %02d:%02d", $0.hour, $0.minute) }.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
                        }
                        .padding(12)
                        .therapyInsetSurface()
                    }.buttonStyle(TherapyPressStyle())
                }
                if store.data.routines.filter(ShowerPlanner.isShower).isEmpty {
                    Button("Montag, Mittwoch, Freitag planen", systemImage: "calendar.badge.plus") { routine = ShowerPlanner.defaultRoutine() }.buttonStyle(.glass)
                    Button("Alle zwei Tage planen", systemImage: "repeat") { routine = ShowerPlanner.defaultRoutine(everyTwoDays: true) }.buttonStyle(.glass)
                }
                NavigationLink { RoutineHubView() } label: { Label("Routinen & Erinnerungen bearbeiten", systemImage: "slider.horizontal.3") }.font(.subheadline)
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        let items = history
        if items.isEmpty {
            GlassCard {
                ContentUnavailableView("Noch kein Verlauf", systemImage: "shower", description: Text("Hier erscheinen bestätigte, ausgelassene und zusätzliche Duschtage."))
                    .frame(maxWidth: .infinity)
            }
        } else {
            TherapySettingsSection(title: "Verlauf", footer: "Tippe auf ••• um einen Eintrag zu korrigieren. Nichts verschwindet heimlich: Korrekturen bleiben nachvollziehbar.") {
                ForEach(items.prefix(historyLimit)) { item in historyRow(item) }
            }
            if items.count > historyLimit {
                Button("Ältere Einträge anzeigen", systemImage: "chevron.down") { historyLimit += 30 }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func historyRow(_ item: ShowerHistoryItem) -> some View {
        let title = item.markedWrong ? "Falsch eingetragen" : !item.showered ? "Nicht geduscht" : item.kind == .extra ? "Außer der Reihe geduscht" : "Geduscht"
        let icon = item.markedWrong ? "xmark" : !item.showered ? "minus" : item.kind == .extra ? "plus" : "checkmark"
        let tint: Color = item.markedWrong ? .gray : !item.showered ? .orange : .accentColor
        return HStack(spacing: 14) {
            TherapyIconTile(icon: icon, size: 32, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(item.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
                    .strikethrough(item.markedWrong)
                if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if item.corrected && !item.markedWrong { Text("Korrigiert").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
            }
            .opacity(item.markedWrong ? 0.6 : 1)
            Spacer(minLength: 8)
            Menu {
                if item.kind == .extra {
                    Button("Bearbeiten", systemImage: "pencil") { entry = store.data.showerEntries.first { $0.id == item.id } }
                }
                if item.markedWrong {
                    Button("Markierung aufheben", systemImage: "arrow.uturn.backward") { pending = ShowerHistoryAction(kind: .unmark, item: item) }
                } else if item.showered {
                    if item.kind == .planned { Button("Doch nicht geduscht", systemImage: "minus.circle") { pending = ShowerHistoryAction(kind: .notShowered, item: item) } }
                    Button("Als falsch eingetragen markieren", systemImage: "xmark.circle") { pending = ShowerHistoryAction(kind: .markWrong, item: item) }
                } else if item.kind == .planned {
                    Button("Doch geduscht", systemImage: "checkmark.circle") { pending = ShowerHistoryAction(kind: .showered, item: item) }
                }
                if item.kind == .extra {
                    Divider()
                    Button("Eintrag entfernen", systemImage: "trash", role: .destructive) { pending = ShowerHistoryAction(kind: .delete, item: item) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Eintrag korrigieren")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    private func apply(_ action: ShowerHistoryAction) {
        var snapshot = store.data
        let changed: Bool
        switch action.kind {
        case .notShowered: changed = ShowerHistory.setShowered(action.item.id, false, in: &snapshot)
        case .showered: changed = ShowerHistory.setShowered(action.item.id, true, in: &snapshot)
        case .markWrong: changed = ShowerHistory.setMarkedWrong(action.item.id, true, in: &snapshot)
        case .unmark: changed = ShowerHistory.setMarkedWrong(action.item.id, false, in: &snapshot)
        case .delete:
            let before = snapshot.showerEntries.count
            snapshot.showerEntries.removeAll { $0.id == action.item.id }
            changed = snapshot.showerEntries.count != before
        }
        guard changed else { error = "Dieser Eintrag hat sich inzwischen geändert. Bitte prüfe ihn erneut."; return }
        store.data = snapshot
        error = store.lastSaveError
    }

    private func weekRow(_ day: Date) -> some View {
        let done = ShowerPlanner.showered(on: day, data: store.data)
        let skipped = store.data.routineCompletions.contains { $0.outcome == .skipped && ShowerPlanner.isShower($0, data: store.data) && Calendar.current.isDate($0.scheduledAt, inSameDayAs: day) }
        let moved = store.data.routineDeferrals.contains { deferral in Calendar.current.isDate(deferral.scheduledAt, inSameDayAs: day) && store.data.routines.first { $0.id == deferral.routineID }.map(ShowerPlanner.isShower) == true }
        let plannedDay = !ShowerPlanner.today(store.data, at: day).isEmpty
        let isToday = Calendar.current.isDateInToday(day)
        return HStack {
            Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.subheadline.weight(isToday ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(done ? "Geduscht" : skipped ? "Ausgelassen" : moved ? "Verschoben" : plannedDay ? "Geplant" : "Frei",
                  systemImage: done ? "checkmark.circle.fill" : skipped ? "minus.circle" : moved ? "arrow.right.circle" : plannedDay ? "drop.circle" : "circle.dotted")
                .font(.caption.bold())
                .foregroundStyle(done || plannedDay ? Color.accentColor : Color.secondary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
struct ShowerEntryEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: ShowerEntry
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Mein Duschtag", selection: $entry.date, in: ...Date())
                TextField("Meine Notiz · optional", text: $entry.note, axis: .vertical).lineLimit(3...8)
                if let error = store.lastSaveError { Text(error).foregroundStyle(.red) }
            }.therapyFormStyle().navigationTitle("Duschtag festhalten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        var snapshot = store.data
                        if !snapshot.showerEntries.contains(where: { $0.id == entry.id }), Calendar.current.isDateInToday(entry.date), let occurrence = ShowerPlanner.today(snapshot).first(where: { !RoutinePlanner.resolved($0, completions: snapshot.routineCompletions) }) {
                            _ = RoutineDayMutation.resolve(occurrence, outcome: .done, note: entry.note, in: &snapshot)
                        } else { snapshot.showerEntries.removeAll { $0.id == entry.id }; snapshot.showerEntries.insert(entry, at: 0) }
                        store.data = snapshot; if store.lastSaveError == nil { dismiss() }
                    } }
                }
        }
    }
}

private struct EmergencyPanelEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var panel: EmergencyPanel
    let save: (EmergencyPanel) -> Void
    var body: some View {
        Form {
            TextField("Titel", text: $panel.title)
            TextField("Was hilft mir jetzt?", text: $panel.text, axis: .vertical).lineLimit(3...10)
            Picker("Symbol", selection: $panel.symbol) { ForEach(["heart.fill", "hand.raised.fill", "ear.fill", "person.2.fill", "leaf.fill", "drop.fill", "arrow.right.circle.fill"], id: \.self) { Label($0, systemImage: $0).tag($0) } }
            Toggle("Im Plan anzeigen", isOn: $panel.enabled)
            Picker("Gespeicherte Methode", selection: $panel.methodID) { Text("Eigener Text").tag(UUID?.none); ForEach(store.data.copingMethods) { Text($0.title).tag(Optional($0.id)) } }
        }.therapyFormStyle().navigationTitle("Hilfekarte").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { save(panel); dismiss() } } }
    }
}
