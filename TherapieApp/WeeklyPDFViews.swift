import SwiftUI
import PDFKit
import UIKit

struct WeeklyPDFReportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var options = WeeklyPrintOptions()
    @State private var result: WeeklyPDFResult?
    @State private var error: String?
    @State private var generating = false
    @State private var showingPreview = false
    @State private var showingShare = false
    private var candidates: [MediaItem] {
        let period = options.period
        let linked = Set(store.data.notes.filter { period.contains($0.createdAt) || ($0.updatedAt.map(period.contains) ?? false) }.flatMap { $0.mediaIDs ?? [] } + store.data.guidedCheckIns.filter { period.contains($0.date) }.flatMap(\.mediaIDs))
        return store.data.media.filter { $0.kind == .photo && $0.attachmentOmitted != true && (period.contains($0.createdAt) || linked.contains($0.id)) }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Wochenbericht") {
                    DatePicker("Woche auswählen", selection: $options.weekStart, in: ...Date(), displayedComponents: .date)
                    Text(options.period.start.formatted(date: .abbreviated, time: .omitted) + " – " + options.period.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    Picker("Höchstens", selection: $options.maxPages) { ForEach(1...3, id: \.self) { Text("\($0) \($0 == 1 ? "Seite" : "Seiten")").tag($0) } }.pickerStyle(.segmented)
                    Text("Standard: letzte Kalenderwoche, Montag bis Sonntag. Der Bericht fasst zusammen; längere Texte und zusätzliche Einträge werden bei Bedarf gekürzt und am Seitenende gekennzeichnet.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Das soll mit auf die Seiten") {
                    Toggle("Mein Name", isOn: $options.includeName)
                    Toggle("Stimmung & Verlauf", isOn: $options.includeMood)
                    Toggle("Akku & Akku-Stichwörter", isOn: $options.includeBattery)
                    Toggle("Check-ins & Therapierückblicke", isOn: $options.includeCheckIns)
                    Toggle("Aufgaben", isOn: $options.includeTasks)
                    Toggle("Ziele", isOn: $options.includeGoals)
                    Toggle("Routinenprotokoll", isOn: $options.includeRoutines)
                    Toggle("Notizen", isOn: $options.includeNotes)
                }
                Section("Bilder bewusst auswählen · höchstens 3") {
                    Text("Kein Bild wird automatisch eingefügt. Sprachaufnahmen und Dateien werden nicht eingebettet.").font(.caption).foregroundStyle(.secondary)
                    ForEach(candidates) { item in
                        Toggle(item.title, isOn: Binding(get: { options.photoIDs.contains(item.id) }, set: { selected in if selected { options.photoIDs.insert(item.id) } else { options.photoIDs.remove(item.id) } }))
                            .disabled(!options.photoIDs.contains(item.id) && options.photoIDs.count >= 3)
                    }
                    if candidates.isEmpty { Text("Keine Fotos aus dieser Woche oder ihren Notizen.").foregroundStyle(.secondary) }
                }
                Section {
                    Button { generate() } label: { Label(generating ? "PDF wird erstellt …" : "PDF erstellen & ansehen", systemImage: "doc.richtext") }.disabled(generating)
                    if generating { ProgressView() }
                    if let result {
                        Text("\(result.pages) \(result.pages == 1 ? "Seite" : "Seiten") · \(result.shortenedRows) Texte gekürzt · \(result.omittedRows) weitere Einträge nicht abgedruckt").font(.caption).foregroundStyle(.secondary)
                        if result.missingPhotos > 0 { Text("\(result.missingPhotos) Bilder konnten nicht gelesen werden.").foregroundStyle(.orange) }
                        Button("Vorschau öffnen", systemImage: "doc.text.magnifyingglass") { showingPreview = true }
                        Button("PDF speichern / teilen", systemImage: "square.and.arrow.up") { showingShare = true }
                        Button("Drucken", systemImage: "printer") { printReport(result.url) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Text("Nur gewählte Bereiche werden ausgegeben. Prüfe die Vorschau vor dem Teilen. Es findet keine automatische Übermittlung statt.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Meine Therapiewoche").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
                .onChange(of: options) { old, new in
                    result = nil
                    if old.period != new.period { options.photoIDs = [] }
                }
                .sheet(isPresented: $showingPreview) {
                    if let result {
                        NavigationStack { WeeklyPDFPreview(url: result.url).navigationTitle("Druckvorschau").navigationBarTitleDisplayMode(.inline).toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Schließen") { showingPreview = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("Drucken", systemImage: "printer") { printReport(result.url) } }
                        } }
                    }
                }
                .sheet(isPresented: $showingShare) { if let result { WellnessShareView(url: result.url) } }
        }
    }
    private func generate() {
        generating = true; error = nil
        let data = store.data, selected = options
        let plan = WeeklyPrintPlan.make(data: data, options: selected)
        let photos = plan.photoIDs.compactMap { id -> ReportPhoto? in
            guard let item = data.media.first(where: { $0.id == id }) else { return nil }
            return ReportPhoto(url: try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL), caption: item.title)
        }
        Task { @MainActor in
            defer { generating = false }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TherapieWochenberichte", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try BackupArchive.protect(directory)
                let url = directory.appendingPathComponent("Therapiewoche-" + UUID().uuidString + ".pdf")
                let rendered = try await Task.detached(priority: .userInitiated) { try WeeklyPDFRenderer.render(plan, photos: photos, to: url) }.value
                try BackupArchive.protect(url)
                guard options == selected else { try? FileManager.default.removeItem(at: url); return }
                result = rendered; showingPreview = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func printReport(_ url: URL) {
        let printer = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil); info.outputType = .general; info.jobName = "Meine Therapiewoche"
        printer.printInfo = info; printer.printingItem = url; printer.showsPageRange = true
        printer.present(animated: true) { _, _, failure in if let failure { error = failure.localizedDescription } }
    }
}
struct WeeklyPDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = .secondarySystemBackground; view.document = PDFDocument(url: url); return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}
