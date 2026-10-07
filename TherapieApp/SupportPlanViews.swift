import SwiftUI
import PhotosUI
import UIKit

struct EmergencyPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing = false
    @State private var showAI = false
    private var plan: PersonalEmergencyPlan { store.data.emergencyPlan }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 22) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(plan.title, systemImage: "lifepreserver.fill").font(.largeTitle.bold()).foregroundStyle(Color.accentColor)
                        if !plan.hasContent {
                            Text("Hier ist Platz für deinen persönlichen Plan.").font(.title2.bold())
                            Text("Trage einen ersten Schritt, hilfreiche Informationen und bei Bedarf ein Bild ein.").font(.title3)
                            Button("Meinen Plan gestalten", systemImage: "pencil") { editing = true }.buttonStyle(.borderedProminent).controlSize(.large)
                        } else {
                            if !plan.firstStep.isEmpty { Text("Mein erster Schritt").font(.headline).foregroundStyle(.secondary); Text(plan.firstStep).font(.system(.largeTitle, design: .rounded, weight: .bold)).textSelection(.enabled) }
                            if let id = plan.imageID, let item = store.data.media.first(where: { $0.id == id }) { EmergencyPlanImage(item: item) }
                            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, text in
                                HStack(alignment: .top, spacing: 14) {
                                    Text("\(index + 1)").font(.title2.bold()).foregroundStyle(Color.accentColor).frame(minWidth: 30)
                                    Text(text).font(.title2).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !plan.warningSigns.isEmpty { planCard("Meine Warnzeichen", text: plan.warningSigns, icon: "bell") }
                if !plan.support.isEmpty { planCard("Meine Unterstützung", text: plan.support, icon: "person.2.fill") }
                ForEach(store.data.copingMethods.filter { plan.methodIDs.contains($0.id) }) { method in
                    NavigationLink { MethodDetailView(methodID: method.id) } label: { Label(method.title, systemImage: method.kind == .thoughtStop ? "hand.raised.fill" : "sparkles").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
                }
                NavigationLink { GroundingExerciseView() } label: { Label("5-4-3-2-1 starten", systemImage: "hand.raised.fingers.spread.fill").font(.title3.bold()).padding(.vertical, 14) }.buttonStyle(.bordered)
                Button("Mit KI einen Plan entwerfen", systemImage: "sparkles") { showAI = true }.buttonStyle(.bordered)
            }
        }.navigationTitle("Notfallplan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bearbeiten", systemImage: "pencil") { editing = true } }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: ([plan.title, plan.firstStep] + plan.steps + [plan.warningSigns, plan.support]).filter { !$0.isEmpty }.joined(separator: "\n\n")) { Image(systemName: "square.and.arrow.up") } }
            }
            .sheet(isPresented: $editing) { EmergencyPlanEditorView(plan: plan) }
            .sheet(isPresented: $showAI) { SupportAIProposalView(purpose: .emergency) }
    }
    private func planCard(_ title: String, text: String, icon: String) -> some View {
        GlassCard { VStack(alignment: .leading, spacing: 12) { Label(title, systemImage: icon).font(.headline).foregroundStyle(Color.accentColor); Text(text).font(.title2).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) }
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
            }.navigationTitle("Notfallplan gestalten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
            }.navigationTitle("Bild auswählen").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
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
                    Button("Weiter", systemImage: "arrow.right") { step += 1 }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Diesen Sinn überspringen") { step += 1 }.buttonStyle(.bordered)
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
                            }.buttonStyle(.borderedProminent).disabled(saved)
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
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Mein Duschtag", icon: "shower.fill")
                    ShowerDayActions(now: context.date)
                    let count = ShowerPlanner.weekCount(store.data, at: context.date)
                    let goal = max(1, min(7, store.data.showerPreferences.weeklyGoal))
                    ProgressView(value: Double(min(count, goal)), total: Double(goal)).tint(.accentColor)
                    Text("Diese Woche: \(count) von \(goal) Duschtagen · \(max(0, goal - count)) fehlen zu deinem Ziel").font(.caption).foregroundStyle(.secondary)
                    Button("Außer der Reihe geduscht", systemImage: "plus.circle") { entry = ShowerEntry() }.buttonStyle(.bordered)
                    if showDetailsLink { NavigationLink { ShowerDaysView() } label: { Label("Wochenplan & Verlauf", systemImage: "calendar") } }
                }
            }
        }.sheet(item: $entry) { ShowerEntryEditor(entry: $0) }
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
        Button("Geduscht", systemImage: "checkmark.circle.fill") { confirming = occurrence }.buttonStyle(.borderedProminent)
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
        } label: { Label("Verschieben / auslassen", systemImage: "ellipsis.circle") }.buttonStyle(.bordered)
    }
    private func resolve(_ occurrence: RoutineOccurrence, outcome: RoutineOutcome) {
        var snapshot = store.data
        if RoutineDayMutation.resolve(occurrence, outcome: outcome, note: outcome == .skipped ? "Bis zum nächsten regulären Duschtag" : "", in: &snapshot) { store.data = snapshot; error = store.lastSaveError } else { error = "Dieser Duschtag ist nicht mehr offen." }
    }
}
struct ShowerDaysView: View {
    @EnvironmentObject private var store: AppStore
    @State private var routine: DailyRoutine?
    @State private var entry: ShowerEntry?
    @State private var deleting: ShowerEntry?
    @State private var weekOffset = 0
    private var week: Date { Calendar.therapyCalendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date() }
    private var weekStart: Date { Calendar.therapyCalendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week }
    private var planned: [RoutineCompletion] { store.data.routineCompletions.filter { ShowerPlanner.isShower($0, data: store.data) }.sorted { $0.recordedAt > $1.recordedAt } }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 18) {
                ShowerTodayCard(showDetailsLink: false)
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Mein Wochenziel", icon: "calendar", subtitle: "Dein persönliches Ziel. Bestätigte Duschtage zählen einmal pro Tag; Auslassen zählt nicht.")
                        Stepper("\(store.data.showerPreferences.weeklyGoal) Duschtage pro Woche", value: $store.data.showerPreferences.weeklyGoal, in: 1...7)
                        HStack {
                            Button("Vorherige Woche", systemImage: "chevron.left") { weekOffset -= 1 }.labelStyle(.iconOnly)
                            Spacer(); Text(ArchiveGrouping.week.title(for: week)).font(.headline); Spacer()
                            Button("Nächste Woche", systemImage: "chevron.right") { weekOffset += 1 }.labelStyle(.iconOnly)
                        }
                        ForEach(0..<7, id: \.self) { offset in
                            if let day = Calendar.therapyCalendar.date(byAdding: .day, value: offset, to: weekStart) { weekRow(day) }
                        }
                        let count = ShowerPlanner.weekCount(store.data, at: week)
                        Text("\(count) bestätigte Tage · \(max(0, store.data.showerPreferences.weeklyGoal - count)) fehlen zum Ziel").font(.subheadline.bold()).foregroundStyle(Color.accentColor)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Mein Rhythmus", icon: "repeat")
                        ForEach(store.data.routines.filter(ShowerPlanner.isShower)) { value in
                            Button { routine = value } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(value.title + (value.enabled ? "" : " · pausiert")).font(.headline)
                                    Text(value.repeatEveryDays == 2 ? "Alle zwei Tage ab " + (value.recurrenceAnchor ?? value.createdAt).formatted(date: .abbreviated, time: .omitted) : value.times.map { $0.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ") + String(format: " · %02d:%02d", $0.hour, $0.minute) }.joined(separator: " / ")).font(.caption)
                                }
                            }.buttonStyle(.plain)
                        }
                        if store.data.routines.filter(ShowerPlanner.isShower).isEmpty {
                            Button("Montag, Mittwoch, Freitag planen", systemImage: "calendar.badge.plus") { routine = ShowerPlanner.defaultRoutine() }.buttonStyle(.bordered)
                            Button("Alle zwei Tage planen", systemImage: "repeat") { routine = ShowerPlanner.defaultRoutine(everyTwoDays: true) }.buttonStyle(.bordered)
                        }
                        Text("Tage und Uhrzeit bestätigst du im Editor. Bestehende Pläne werden weiterverwendet.").font(.caption).foregroundStyle(.secondary)
                        NavigationLink { RoutineHubView() } label: { Label("Routinen & Erinnerungen bearbeiten", systemImage: "pencil") }
                    }
                }
                Text("Verlauf · auch außerhalb der Reihe").font(.title3.bold())
                ForEach(store.data.showerEntries.sorted { $0.date > $1.date }) { item in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(item.date.formatted(date: .complete, time: .shortened), systemImage: "shower.fill").font(.headline)
                            if !item.note.isEmpty { Text(item.note) }
                            HStack { Button("Bearbeiten") { entry = item }; Spacer(); Button("Löschen", role: .destructive) { deleting = item } }
                        }
                    }
                }
                ForEach(planned.prefix(40)) { log in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(log.outcome == .done ? "Geduscht" : "Ausgelassen", systemImage: log.outcome == .done ? "checkmark.circle.fill" : "minus.circle").font(.headline)
                            Text(log.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            if !log.note.isEmpty { Text(log.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                NavigationLink { RoutineHistoryView() } label: { Text("Vollständigen Verlauf und Korrekturen öffnen") }
            }
        }.navigationTitle("Duschtage").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $routine) { RoutineEditorView(routine: $0) }
            .sheet(item: $entry) { ShowerEntryEditor(entry: $0) }
            .alert("Duschtag löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Abbrechen", role: .cancel) { deleting = nil }; Button("Löschen", role: .destructive) { if let deleting { store.data.showerEntries.removeAll { $0.id == deleting.id } }; deleting = nil } }
    }
    private func weekRow(_ day: Date) -> some View {
        let done = ShowerPlanner.dates(store.data).contains { Calendar.current.isDate($0, inSameDayAs: day) }
        let skipped = planned.contains { $0.outcome == .skipped && Calendar.current.isDate($0.scheduledAt, inSameDayAs: day) }
        let moved = store.data.routineDeferrals.contains { deferral in Calendar.current.isDate(deferral.scheduledAt, inSameDayAs: day) && store.data.routines.first { $0.id == deferral.routineID }.map(ShowerPlanner.isShower) == true }
        let plannedDay = !ShowerPlanner.today(store.data, at: day).isEmpty
        return HStack {
            Text(day.formatted(.dateTime.weekday(.wide).day().month())).frame(maxWidth: .infinity, alignment: .leading)
            Label(done ? "Geduscht" : skipped ? "Ausgelassen" : moved ? "Verschoben" : plannedDay ? "Geplant" : "Frei", systemImage: done ? "checkmark.circle.fill" : skipped ? "minus.circle" : moved ? "arrow.right.circle" : plannedDay ? "shower.fill" : "circle.dotted").font(.caption.bold()).foregroundStyle(done || plannedDay ? Color.accentColor : Color.secondary)
        }.accessibilityElement(children: .combine)
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
            }.navigationTitle("Duschtag festhalten").navigationBarTitleDisplayMode(.inline)
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
