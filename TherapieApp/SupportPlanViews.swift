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

struct ShowerDaysView: View {
    @EnvironmentObject private var store: AppStore
    @State private var routine: DailyRoutine?
    @State private var entry: ShowerEntry?
    @State private var deleting: ShowerEntry?
    private var planned: [RoutineCompletion] {
        store.data.routineCompletions.filter { entry in
            guard entry.outcome == .done else { return false }
            let routine = store.data.routines.first { $0.id == entry.routineID }
            return routine?.symbol == "shower.fill" || (entry.routineTitle ?? routine?.title ?? "").localizedCaseInsensitiveContains("dusch")
        }.sorted { $0.recordedAt > $1.recordedAt }
    }
    private var lastDate: Date? { (store.data.showerEntries.map(\.date) + planned.map(\.recordedAt)).max() }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Meine Duschtage", icon: "shower.fill", subtitle: "Fest planen oder flexibel festhalten. Beides ist möglich.")
                        if let lastDate { Text("Zuletzt: " + lastDate.formatted(date: .abbreviated, time: .shortened)).font(.title3.bold()) }
                        Button("Duschtag festhalten", systemImage: "plus.circle") { entry = ShowerEntry() }.buttonStyle(.borderedProminent)
                        Button("Feste Duschtage planen", systemImage: "calendar") { routine = DailyRoutine(title: "Duschen", symbol: "shower.fill", times: [RoutineTime(weekdays: [2, 4, 6], hour: 19, minute: 0)]) }.buttonStyle(.bordered)
                        Text("Beim festen Plan bestätigst du Tage und Uhrzeit im Routine-Editor. Flexible Einträge lösen keine Erinnerung aus.").font(.caption).foregroundStyle(.secondary)
                        NavigationLink { RoutineHubView() } label: { Label("Geplante Routinen bearbeiten", systemImage: "checkmark.circle") }
                    }
                }
                ForEach(store.data.showerEntries.sorted { $0.date > $1.date }) { item in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.date.formatted(date: .complete, time: .shortened)).font(.headline)
                            if !item.note.isEmpty { Text(item.note) }
                            HStack { Button("Bearbeiten") { entry = item }; Spacer(); Button("Löschen", role: .destructive) { deleting = item } }
                        }
                    }
                }
                if !planned.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Bestätigte Duschroutinen", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Color.accentColor)
                            ForEach(planned.prefix(30)) { completion in
                                NavigationLink { RoutineDetailView(routineID: completion.routineID) } label: {
                                    VStack(alignment: .leading, spacing: 4) { Text(completion.recordedAt.formatted(date: .abbreviated, time: .shortened)); if !completion.note.isEmpty { Text(completion.note).font(.caption) } }
                                }
                            }
                            NavigationLink { RoutineHistoryView() } label: { Text("Gesamten Verlauf öffnen") }
                        }
                    }
                }
                if store.data.showerEntries.isEmpty && planned.isEmpty { Text("Dein Verlauf füllt sich, wenn du Duschtage selbst bestätigst.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Duschtage").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $routine) { RoutineEditorView(routine: $0) }
            .sheet(item: $entry) { ShowerEntryEditor(entry: $0) }
            .alert("Duschtag löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Abbrechen", role: .cancel) { deleting = nil }; Button("Löschen", role: .destructive) { if let deleting { store.data.showerEntries.removeAll { $0.id == deleting.id } }; deleting = nil } }
    }
}
private struct ShowerEntryEditor: View {
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
                        var snapshot = store.data; snapshot.showerEntries.removeAll { $0.id == entry.id }; snapshot.showerEntries.insert(entry, at: 0); store.data = snapshot; if store.lastSaveError == nil { dismiss() }
                    } }
                }
        }
    }
}
