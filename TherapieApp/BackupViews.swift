import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let therapieBackup = UTType(exportedAs: "eu.rjuhas.therapie.backup", conformingTo: .data)
}

private struct ExportedBackup: Identifiable {
    let id = UUID()
    let url: URL
}

/// The Files picker copies directly from a URL, avoiding a FileDocument that
/// would read a potentially multi-gigabyte archive entirely into memory.
private struct BackupSavePicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(false) }
    }
}

struct BackupCenterView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var options = BackupOptions()
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var revealPassword = false
    @State private var importPassword = ""
    @State private var showImporter = false
    @State private var selectedFile: URL?
    @State private var prepared: PreparedBackup?
    @State private var exported: ExportedBackup?
    @State private var exportedURL: URL?
    @State private var busy: String?
    @State private var progress = 0.0
    @State private var message: String?
    @State private var error: String?
    @State private var confirmImport = false
    @State private var encryptedExport = true
    @State private var exportedEncrypted = true

    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    introduction
                    filesCard
                    exportCard
                    importCard
                    if let prepared { preview(prepared) }
                    if let busy {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(busy, systemImage: "lock.shield")
                                if progress > 0 { ProgressView(value: progress).accessibilityLabel("Fortschritt") }
                                else { ProgressView() }
                                Text("Bitte lasse die App geöffnet und das iPhone entsperrt, bis die Datei fertig ist.").font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let message { GlassCard { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).fixedSize(horizontal: false, vertical: true) } }
                    if let error { GlassCard { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
                }
            }
            .navigationTitle("Datensicherung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(busy != nil) } }
            .interactiveDismissDisabled(busy != nil)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.therapieBackup, .zip, .data]) { result in
                do {
                    prepared?.discard(); prepared = nil
                    selectedFile = try result.get(); importPassword = ""; error = nil; message = nil
                } catch { self.error = error.localizedDescription }
            }
            .sheet(item: $exported) { file in
                BackupSavePicker(url: file.url) { saved in
                    exported = nil
                    message = saved ? (exportedEncrypted ? "Die verschlüsselte Datei wurde im gewählten Ordner gesichert." : "Das lesbare Klartext-ZIP wurde im gewählten Ordner gesichert.") : "Speichern abgebrochen. Du kannst die fertige Datei erneut sichern."
                    if saved { TherapyEffects.shared.light() }
                }.ignoresSafeArea()
            }
            .alert("Aktuelle Daten ersetzen?", isPresented: $confirmImport) {
                Button("Abbrechen", role: .cancel) {}
                Button("Daten ersetzen", role: .destructive) { install() }
            } message: {
                Text("Deine aktuellen Einträge werden vollständig durch diese geprüfte Sicherung ersetzt, nicht zusammengeführt. Sichere vorher den aktuellen Stand. Ausgelassene Anhänge werden nicht wiederhergestellt.")
            }
            .onDisappear {
                prepared?.discard()
                if let exportedURL { try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent()) }
                password = ""; repeatedPassword = ""; importPassword = ""
            }
        }
    }

    private var introduction: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Alles in einer Datei", icon: "externaldrive.badge.checkmark",
                              subtitle: "Deine Daten mitnehmen, auch auf ein anderes iPhone.")
                Text("Einträge, Stimmung, Akku-Punkte, Themen, Ordner, Ziele, Notizen, Stundenpläne und Darstellungseinstellungen werden gemeinsam gesichert.")
                    .font(.subheadline)
                Text("Die Passwortsicherung schützt Inhalt und Integrität mit AES-256-GCM. Das Passwort wird nicht gespeichert und kann nicht zurückgesetzt werden. Bewahre es getrennt von der Datei auf.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("\(store.data.media.count) Materialien · \(store.data.notes.count) Notizen · \(store.data.moodCheckIns.count) Check-ins")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Exportieren", icon: "square.and.arrow.up", subtitle: "Alle Eintragsdaten werden immer mitgenommen.")
                Picker("Dateiformat", selection: $encryptedExport) {
                    Text("Passwortgeschützte Sicherung").tag(true)
                    Text("Lesbares Klartext-ZIP").tag(false)
                }.pickerStyle(.menu)
                if !encryptedExport {
                    Label("Dieses ZIP ist unverschlüsselt. Jede Person mit Zugriff auf die Datei kann deine Einträge und Anhänge lesen.", systemImage: "lock.open").font(.footnote).foregroundStyle(.orange)
                    Text("Mit Einzeldateien für alle Einträge, einer Übersicht und den vollständigen Daten für den Import. Ohne App lesbar; normale ZIP-Programme können es entpacken.").font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Bilder einschließen", isOn: $options.includePhotos)
                Toggle("Audioaufnahmen einschließen", isOn: $options.includeAudio)
                Toggle("Dokumente einschließen", isOn: $options.includeDocuments)
                if !options.includePhotos || !options.includeAudio || !options.includeDocuments {
                    Text("Ausgelassene Dateien fehlen nach dem Import. Ihre Einträge, Titel, Kategorien und Notizen bleiben erhalten und werden als ohne Anhang gekennzeichnet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.data.media.contains(where: { $0.attachmentOmitted == true }) {
                    Text("Bereits ausgelassene Anhänge können auch mit aktivierten Schaltern nicht erneut mitgesichert werden.").font(.footnote).foregroundStyle(.secondary)
                }
                if encryptedExport { Group {
                    if revealPassword {
                        TextField("Neues Sicherungspasswort", text: $password)
                        TextField("Passwort wiederholen", text: $repeatedPassword)
                    } else {
                        SecureField("Neues Sicherungspasswort", text: $password)
                        SecureField("Passwort wiederholen", text: $repeatedPassword)
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                Toggle("Passwort anzeigen", isOn: $revealPassword)
                Text("Mindestens 8 Zeichen. Eine längere, einzigartige Passphrase schützt besser.").font(.caption).foregroundStyle(.secondary)
                if !repeatedPassword.isEmpty && password != repeatedPassword { Text("Die Passwörter stimmen noch nicht überein.").font(.caption).foregroundStyle(.orange) }
                }
                Button { createExport() } label: { Label(encryptedExport ? "Verschlüsselte Datei erstellen" : "Lesbares ZIP erstellen", systemImage: encryptedExport ? "lock.doc" : "doc.zipper").frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled((encryptedExport && (password.count < 8 || password != repeatedPassword)) || store.loadError != nil)
                if let exportedURL {
                    Button { exported = ExportedBackup(url: exportedURL) } label: { Label("In Dateien sichern", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }
            }.disabled(busy != nil)
        }
    }

    private var importCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Importieren", icon: "square.and.arrow.down", subtitle: "Auch direkt nach einer Neuinstallation möglich.")
                Button { showImporter = true } label: { Label("Sicherungsdatei auswählen", systemImage: "doc.badge.arrow.up").frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }.buttonStyle(.bordered)
                if let selectedFile {
                    Text(selectedFile.lastPathComponent).font(.footnote).lineLimit(3)
                    if selectedFile.pathExtension.lowercased() != "zip" {
                        SecureField("Passwort dieser Sicherung", text: $importPassword).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button { verifyImport() } label: { Label(selectedFile.pathExtension.lowercased() == "zip" ? "ZIP prüfen & Vorschau öffnen" : "Entschlüsseln & prüfen", systemImage: "checkmark.shield").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(selectedFile.pathExtension.lowercased() != "zip" && importPassword.isEmpty)
                }
                Text("Berechtigungen, Kalender-Verknüpfungen und der automatische Backup-Ordner werden auf diesem Gerät neu eingerichtet. Die persönlichen Einstellungen bleiben erhalten.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(busy != nil)
        }
    }

    private func preview(_ prepared: PreparedBackup) -> some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sicherung erfolgreich geprüft", icon: "checkmark.shield.fill", subtitle: "Noch wurden keine aktuellen Daten ersetzt.")
                Text(prepared.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Text("App-Version \(prepared.manifest.appVersion)").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Einträge & Vorlagen", value: "\(prepared.manifest.entryCount)")
                LabeledContent("Dateien", value: "\(prepared.manifest.attachments.count)")
                LabeledContent("Dateigröße der Anhänge", value: ByteCountFormatter.string(fromByteCount: Int64(clamping: prepared.manifest.attachmentBytes), countStyle: .file))
                if prepared.manifest.omittedAttachments > 0 {
                    Label("\(prepared.manifest.omittedAttachments) Anhänge wurden ausgelassen. Die Einträge sind enthalten.", systemImage: "photo.badge.exclamationmark").font(.footnote).foregroundStyle(.orange)
                }
                ResponsiveButtonRow {
                    Button("Daten wiederherstellen", systemImage: "arrow.counterclockwise") { confirmImport = true }.buttonStyle(.borderedProminent)
                    Button("Verwerfen", role: .cancel) { prepared.discard(); self.prepared = nil; importPassword = "" }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func createExport() {
        do {
            let snapshot = try store.exportSnapshot(), root = store.rootURL, preferences = PortablePreferences.capture()
            let selectedOptions = options, secret = password, encrypted = encryptedExport
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3003.0.0"
            busy = encrypted ? "Sicherung wird verschlüsselt …" : "Lesbare Einträge und ZIP werden erstellt …"; progress = 0; message = nil; error = nil
            Task {
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        if !encrypted { return try ReadableBackup.export(data: snapshot, root: root, preferences: preferences, options: selectedOptions, version: version) { value in Task { @MainActor in progress = value } } }
                        return try BackupArchive.export(data: snapshot, root: root, preferences: preferences, options: selectedOptions, password: secret, version: version) { value in
                            Task { @MainActor in progress = value }
                        }
                    }.value
                    if let exportedURL { try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent()) }
                    exportedURL = url; exportedEncrypted = encrypted; exported = ExportedBackup(url: url)
                    password = ""; repeatedPassword = ""
                } catch { self.error = error.localizedDescription }
                busy = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    private func verifyImport() {
        guard let url = selectedFile else { return }
        let secret = importPassword
        prepared?.discard(); prepared = nil
        busy = url.pathExtension.lowercased() == "zip" ? "ZIP wird entpackt und geprüft …" : "Datei wird entschlüsselt und geprüft …"; progress = 0; error = nil; message = nil
        Task {
            do {
                prepared = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var coordinatorError: NSError?, outcome: Result<PreparedBackup, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinated in
                        outcome = Result {
                            if url.pathExtension.lowercased() == "zip" { return try ReadableBackup.prepareImport(url: coordinated) }
                            return try BackupArchive.prepareImport(url: coordinated, password: secret) { value in Task { @MainActor in progress = value } }
                        }
                    }
                    if let coordinatorError { throw coordinatorError }
                    guard let outcome else { throw BackupArchiveError.invalid("Die Datei konnte nicht aus Dateien geladen werden.") }
                    return try outcome.get()
                }.value
                importPassword = ""
            } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    private func install() {
        guard let prepared else { return }
        do {
            try store.installBackup(prepared)
            self.prepared = nil; selectedFile = nil; importPassword = ""
            message = "Alle Daten wurden wiederhergestellt. Richte bei Bedarf Kalender, Erinnerungen und den automatischen Backup-Ordner erneut ein."
            error = nil
        } catch { self.error = error.localizedDescription; prepared.discard(); self.prepared = nil }
    }
    private var filesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Dein Ordner in Dateien", icon: "folder.fill", subtitle: "Auf meinem iPhone → Therapie → Therapiedaten")
                Text("Hier liegen deine Datendatei, Anhänge und lesbaren Einträge. Du kannst den Ordner manuell kopieren, auch wenn die App nicht mehr startet.").font(.subheadline)
                Text(store.readableFileStatus).font(.caption).foregroundStyle(.secondary)
                Button("Lesbare Dateien jetzt aktualisieren", systemImage: "arrow.clockwise") { store.refreshReadableFiles() }.buttonStyle(.bordered).disabled(busy != nil || store.loadError != nil)
                Text("Der Ordner gehört zur App und wird mit ihr gelöscht. Kopiere ihn vor einer Deinstallation an einen anderen Speicherort. Kopieren ist sicherer als Änderungen an den laufenden Datendateien.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
