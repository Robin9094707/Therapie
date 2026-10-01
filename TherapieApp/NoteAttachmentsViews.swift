import SwiftUI
import PhotosUI
import UIKit
import QuickLook

struct NoteAttachmentsSection: View {
    @EnvironmentObject private var store: AppStore
    @Binding var note: TherapyNote
    @State private var photo: PhotosPickerItem?
    @State private var recording = false
    @State private var chooseExisting = false
    @State private var preview: URL?
    @State private var error: String?
    @State private var importing = false
    private func link(_ id: UUID) { if !(note.mediaIDs ?? []).contains(id) { note.mediaIDs = (note.mediaIDs ?? []) + [id] } }
    var body: some View {
        Section("Bilder, Sprache & Dokumente") {
            HStack {
                PhotosPicker(selection: $photo, matching: .images) { Label("Bild", systemImage: "photo.badge.plus") }.disabled(importing)
                Spacer()
                Button("Sprache", systemImage: "mic") { recording = true }
            }.buttonStyle(.bordered)
            Button("Aus dem Archiv anhängen", systemImage: "paperclip") { chooseExisting = true }
            if importing { ProgressView("Bild wird hinzugefügt …") }
            ForEach(note.mediaIDs ?? [], id: \.self) { id in
                if let item = store.data.media.first(where: { $0.id == id }) {
                    HStack(alignment: .center, spacing: 12) {
                        if item.kind == .photo, let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL), let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        } else { Image(systemName: item.kind.symbol).font(.title2).frame(width: 56, height: 56) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.bold())
                            if let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL), item.attachmentOmitted != true {
                                Button("Öffnen / anhören") { preview = url }.font(.caption)
                            } else { Text("Datei nicht verfügbar · Informationen erhalten").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 4)
                        Button(role: .destructive) { note.mediaIDs?.removeAll { $0 == id } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(item.title + " von der Notiz lösen")
                    }
                } else {
                    HStack { Label("Anhang nicht verfügbar", systemImage: "paperclip"); Spacer(); Button("Lösen") { note.mediaIDs?.removeAll { $0 == id } } }
                }
            }
            Text("Anhänge bleiben im Archiv, auch wenn du sie von dieser Notiz löst oder die Notiz verwirfst.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }; importing = true
            Task { @MainActor in
                defer { importing = false; photo = nil }
                do {
                    guard let bytes = try await selected.loadTransferable(type: Data.self), let image = UIImage(data: bytes), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileReadCorruptFile) }
                    try store.importPhoto(bytes: jpeg, fileExtension: "jpg", title: note.title.isEmpty ? "Notizfoto" : note.title, note: "", tags: [], location: nil)
                    if let failure = store.lastSaveError { error = failure; return }
                    if let item = store.data.media.first { link(item.id) }; error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $recording) { AudioRecordingView(onSaved: link) }
        .sheet(isPresented: $chooseExisting) {
            NavigationStack {
                List {
                    if store.data.media.isEmpty { Text("Dein Archiv ist noch leer.").foregroundStyle(.secondary) }
                    ForEach(store.data.media) { item in
                        Button { link(item.id); chooseExisting = false } label: { Label(item.title, systemImage: item.kind.symbol) }
                    }
                }.navigationTitle("Anhang auswählen").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { chooseExisting = false } } }
            }
        }
        .quickLookPreview($preview)
    }
}
