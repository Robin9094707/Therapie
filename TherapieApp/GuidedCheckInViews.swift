import SwiftUI
import PhotosUI
import UIKit

struct EnergyBatteryControl: View {
    @Binding var percent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { percent < 25 ? .orange : percent < 60 ? .teal : .indigo }
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 22).fill(Color.primary.opacity(0.05))
                        RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, (geometry.size.width - 12) * CGFloat(percent) / 100)).padding(6)
                        Text("\(percent) %").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().frame(maxWidth: .infinity)
                    }.overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.18), lineWidth: 3) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        percent = max(0, min(100, Int(value.location.x / max(1, geometry.size.width) * 100)))
                    })
                }.frame(height: 102)
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.2)).frame(width: 9, height: 34)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Dein Energie-Akku").accessibilityValue("\(percent) Prozent")
                .accessibilityAdjustableAction { direction in
                    if direction == .increment { percent = min(100, percent + 5) }
                    else if direction == .decrement { percent = max(0, percent - 5) }
                }
            Slider(value: Binding(get: { Double(percent) }, set: { percent = Int($0) }), in: 0...100, step: 1).tint(color).accessibilityLabel("Akku in Prozent")
            HStack { Text("Leer"); Spacer(); Text("Voll") }.font(.caption).foregroundStyle(.secondary)
            Text(percent < 25 ? "Heute darf es ein kleiner Schritt sein." : percent < 60 ? "Plane auch Zeit zum Auftanken ein." : "Was möchtest du mit deiner Energie machen?").font(.subheadline).foregroundStyle(.secondary)
        }.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: percent)
    }
}
struct GuidedCheckInView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var entry: GuidedCheckIn
    @State private var battery = 50
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?
    @State private var showExit = false
    private let titles = ["Ankommen", "Deine Stimmung", "Dein Energie-Akku", "Reize & Erholung", "Dein Rückblick", "Deine nächsten Schritte", "Für deine Therapie", "Alles in deinem Tempo"]
    private var step: Int { max(0, min(7, entry.step)) }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Label(entry.kind.title, systemImage: entry.kind.symbol).font(.headline); Spacer(); Text("\(step + 1) / 8").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    ProgressView(value: Double(step + 1), total: 8).tint(.indigo)
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(titles[step]).font(.system(.title, design: .rounded, weight: .bold))
                            questionContent
                        }
                    }.id(step).transition(.opacity.combined(with: .move(edge: .trailing)))
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { if entry.isDraft { persistDraft(); if store.lastSaveError == nil { dismiss() } } else { showExit = true } } } }
            .safeAreaInset(edge: .bottom) { footer.padding(16).background(.regularMaterial) }
            .alert("Bearbeitung beenden?", isPresented: $showExit) { Button("Weiter bearbeiten", role: .cancel) {}; Button("Änderungen verwerfen", role: .destructive) { dismiss() } } message: { Text("Änderungen am abgeschlossenen Check-in werden erst beim abschließenden Speichern übernommen. Neu importierte Fotos bleiben als Materialien im Archiv.") }
            .onAppear { battery = entry.batteryPercent ?? 50 }
            .onChange(of: selection) { _, value in if let value { Task { await addPhoto(value) } } }
        }
    }
    @ViewBuilder private var questionContent: some View {
        switch step {
        case 0:
            Text(intro).font(.body).foregroundStyle(.secondary)
            Label("Jede Frage ist freiwillig", systemImage: "hand.raised").font(.subheadline)
            Text("Du kannst überspringen, zurückgehen und später weitermachen. Nur beim Abschließen werden neue Aufgaben angelegt.").font(.footnote).foregroundStyle(.secondary)
            TextField("Ein Gedanke zum Einstieg", text: $entry.summary, axis: .vertical).textFieldStyle(.roundedBorder)
        case 1:
            Text("Wie geht es dir gerade?")
            VStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button { entry.mood = value; TherapyEffects.shared.light() } label: {
                        HStack { Text(MoodCheckIn.moodFaces[value - 1]).font(.title2); Text(MoodCheckIn.moodTitles[value - 1]); Spacer(); if entry.mood == value { Image(systemName: "checkmark.circle.fill") } }.padding(12).background(entry.mood == value ? Color.indigo.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityAddTraits(entry.mood == value ? .isSelected : [])
                }
            }
        case 2:
            Text("Ziehe im Akku oder nutze den Regler. Auch 0 % ist okay.").foregroundStyle(.secondary)
            EnergyBatteryControl(percent: $battery).onChange(of: battery) { _, value in entry.batteryPercent = value }
            Button(entry.batteryPercent == nil ? "Diesen Akkustand übernehmen" : "Akku wurde gewählt", systemImage: "checkmark.circle") { entry.batteryPercent = battery }.buttonStyle(.bordered)
            field("Was lädt deinen Akku auf?", text: $entry.givesEnergy)
            field("Was kostet dich Energie?", text: $entry.takesEnergy)
        case 3:
            optionalScale("Wie stark ist dein Stress?", value: $entry.stress)
            optionalScale("Wie stark belasten dich Reize?", value: $entry.sensoryLoad)
            Toggle("Schlaf festhalten", isOn: Binding(get: { entry.sleepHours != nil }, set: { entry.sleepHours = $0 ? 8 : nil }))
            if entry.sleepHours != nil { Stepper("Schlaf: \((entry.sleepHours ?? 8).formatted()) Stunden", value: Binding(get: { entry.sleepHours ?? 8 }, set: { entry.sleepHours = $0 }), in: 0...24, step: 0.5) }
        case 4:
            field(entry.kind == .morning ? "Was steht heute an?" : "Was ist passiert? Was war wichtig?", text: $entry.summary)
            field("Ein kleiner Erfolg", text: $entry.smallWin)
            field("Was brauchst du jetzt?", text: $entry.nextNeed)
        case 5:
            Text("Aufgaben von dir, aus der Therapie oder gemeinsam. Du kannst beliebig viele Schritte sammeln.").font(.subheadline).foregroundStyle(.secondary)
            ForEach($entry.tasks) { $task in
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Aufgabe", text: $task.title).textFieldStyle(.roundedBorder)
                    Picker("Von wem?", selection: $task.source) { ForEach(["Von mir", "Aus der Therapie", "Gemeinsam"], id: \.self) { Text($0).tag($0) } }
                    TextField("Der kleinste machbare Schritt", text: $task.smallStep, axis: .vertical)
                    TextField("Details oder Unterstützung", text: $task.details, axis: .vertical)
                    Toggle("Zieltermin", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? Date() : nil }))
                    if task.dueDate != nil { DatePicker("Bis wann?", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }), displayedComponents: .date) }
                    Button("Entfernen", role: .destructive) { entry.tasks.removeAll { $0.id == task.id } }
                }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            }
            Button("Aufgabe hinzufügen", systemImage: "plus.circle.fill") { entry.tasks.append(CheckInTaskDraft()) }.buttonStyle(.bordered)
            if !entry.isDraft { Text("Dieser Check-in ist bereits abgeschlossen. Änderungen werden erst mit Speichern übernommen; erledigte Aufgaben bleiben erledigt.").font(.caption).foregroundStyle(.secondary) }
        case 6:
            field("Was möchtest du beim nächsten Termin besprechen?", text: $entry.therapyQuestion)
            PhotosPicker(selection: $selection, matching: .images) { Label(importing ? "Foto wird gespeichert …" : "Ein Foto ergänzen", systemImage: "photo.badge.plus") }.disabled(importing)
            ForEach(entry.mediaIDs, id: \.self) { id in
                if let media = store.data.media.first(where: { $0.id == id }) { Label(media.title + (media.attachmentOmitted == true ? " · Datei nicht im Backup enthalten" : ""), systemImage: "photo").font(.subheadline) }
            }
            Text("Fotos bleiben auch als einzelne Materialien im Archiv erhalten. Deine Einträge werden nicht automatisch versendet.").font(.footnote).foregroundStyle(.secondary)
        default:
            GuidedCheckInSummary(entry: entry)
            Text("Beim Abschließen speicherst du deinen Check-in und neue Wochenaufgaben. Die Zusammenfassung kannst du anschließend teilen.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var intro: String {
        switch entry.kind {
        case .morning: "Starte mit einem ruhigen Blick auf dich. Was brauchst du für einen guten Morgen?"
        case .evening: "Der Tag darf jetzt ausklingen. Halte fest, was wichtig war und was dir gutgetan hat."
        case .therapy: "Nimm dir einen Moment nach deiner Therapiestunde. Was nimmst du mit, und welche kleinen Schritte folgen?"
        case .free: "Ein Moment nur für dich. Halte fest, wie es dir geht und was du gerade brauchst."
        }
    }
    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if step > 0 { Button("Zurück") { advance(-1) }.buttonStyle(.bordered) }
                Button(step == 7 ? "Check-in speichern" : "Weiter", systemImage: step == 7 ? "checkmark" : "arrow.right") {
                    if step == 7 { store.saveGuided(entry, complete: true); if store.lastSaveError == nil { dismiss() } else { error = store.lastSaveError } }
                    else { advance(1) }
                }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(importing)
            }
            if step > 0 && step < 7 { Button("Frage überspringen") { clearStep(); advance(1) }.font(.subheadline).disabled(importing) }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.subheadline.weight(.semibold)); TextField("Optional", text: text, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder) }
    }
    private func optionalScale(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: Binding(get: { value.wrappedValue ?? 0 }, set: { value.wrappedValue = $0 == 0 ? nil : $0 })) {
                Text("Offen").tag(0); ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
            Text("1 = wenig · 5 = sehr stark").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func advance(_ amount: Int) { withAnimation(reduceMotion ? nil : .smooth) { entry.step = max(0, min(7, step + amount)) }; persistDraft() }
    private func persistDraft() { guard entry.isDraft else { return }; store.saveGuided(entry, complete: false); error = store.lastSaveError }
    private func clearStep() {
        switch step { case 1: entry.mood = nil; case 2: entry.batteryPercent = nil; entry.givesEnergy = ""; entry.takesEnergy = ""; case 3: entry.stress = nil; entry.sensoryLoad = nil; entry.sleepHours = nil; case 4: entry.summary = ""; entry.smallWin = ""; entry.nextNeed = ""; case 5: if entry.isDraft { entry.tasks = [] }; case 6: entry.therapyQuestion = ""; default: break }
    }
    private func addPhoto(_ item: PhotosPickerItem) async {
        importing = true; defer { importing = false; selection = nil }
        do {
            guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw ServiceError.permissionDenied("Das Foto konnte nicht gelesen werden.") }
            let title = entry.kind.title + " – " + Date().formatted(date: .abbreviated, time: .omitted)
            try store.importPhoto(bytes: jpeg, fileExtension: "jpg", title: title, note: "Foto zum geführten Check-in", tags: [entry.kind.title], location: nil)
            if let id = store.data.media.first?.id { entry.mediaIDs.append(id); persistDraft() }
        } catch { self.error = error.localizedDescription }
    }
}
struct GuidedCheckInSummary: View {
    let entry: GuidedCheckIn
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Stimmung", value: entry.mood.map { MoodCheckIn.moodTitles[max(0, min(4, $0 - 1))] } ?? "Nicht angegeben")
            LabeledContent("Akku", value: entry.batteryPercent.map { "\($0) %" } ?? "Nicht angegeben")
            if let stress = entry.stress { LabeledContent("Stress", value: "\(stress)/5") }
            if let sensory = entry.sensoryLoad { LabeledContent("Reize", value: "\(sensory)/5") }
            if let sleep = entry.sleepHours { LabeledContent("Schlaf", value: "\(sleep.formatted()) Stunden") }
            ForEach([("Rückblick", entry.summary), ("Gibt Energie", entry.givesEnergy), ("Kostet Energie", entry.takesEnergy), ("Kleiner Erfolg", entry.smallWin), ("Jetzt brauche ich", entry.nextNeed), ("Für die Therapie", entry.therapyQuestion)], id: \.0) { title, text in
                if !text.isEmpty { VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()); Text(text).textSelection(.enabled) } }
            }
            ForEach(entry.tasks.filter { !$0.title.isEmpty }) { task in Label(task.title, systemImage: "checklist").font(.subheadline) }
            if !entry.mediaIDs.isEmpty { Label("\(entry.mediaIDs.count) verknüpfte Fotos", systemImage: "photo") }
        }
    }
}
