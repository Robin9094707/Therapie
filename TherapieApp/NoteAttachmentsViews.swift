import SwiftUI
import PhotosUI
import UIKit

/// A pure form section. Presenters belong to the stable editor, never to its recycled rows.
struct NoteAttachmentsSection: View {
    @EnvironmentObject private var store: AppStore
    @Binding var note: TherapyNote
    @Binding var photo: PhotosPickerItem?
    var importing: Bool
    var error: String?
    let record: () -> Void
    let choose: () -> Void
    let open: (MediaItem) -> Void
    var body: some View {
        Section("Bilder, Sprache & Dokumente") {
            HStack {
                PhotosPicker(selection: $photo, matching: .images) { Label("Bild", systemImage: "photo.badge.plus") }.accessibilityIdentifier("note.attach.photo")
                Spacer()
                Button("Sprache", systemImage: "mic", action: record).accessibilityIdentifier("note.attach.audio")
            }.buttonStyle(.bordered).disabled(importing)
            Button("Aus dem Archiv anhängen", systemImage: "paperclip", action: choose).disabled(importing).accessibilityIdentifier("note.attach.archive")
            if importing { ProgressView("Bild wird hinzugefügt …") }
            ForEach(note.mediaIDs ?? [], id: \.self) { id in
                if let item = store.data.media.first(where: { $0.id == id }) {
                    HStack(spacing: 12) {
                        MediaAttachmentThumbnail(item: item)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.bold())
                            Button("Öffnen / anhören") { open(item) }.font(.caption).accessibilityIdentifier("note.attachment.open." + id.uuidString)
                        }
                        Spacer(minLength: 4)
                        Button(role: .destructive) { note.mediaIDs?.removeAll { $0 == id } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(item.title + " von der Notiz lösen").accessibilityIdentifier("note.attachment.detach." + id.uuidString)
                    }.buttonStyle(.borderless)
                } else {
                    HStack { Label("Anhang nicht verfügbar", systemImage: "paperclip"); Spacer(); Button("Lösen") { note.mediaIDs?.removeAll { $0 == id } } }
                }
            }
            Text("Anhänge bleiben im Archiv, auch wenn du sie von dieser Notiz löst oder die Notiz verwirfst.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}

enum NoteAttachmentDestination: Identifiable {
    case record, archive, media(UUID)
    var id: String { switch self { case .record: "record"; case .archive: "archive"; case .media(let id): "media-" + id.uuidString } }
}
struct NoteArchivePicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let choose: (UUID) -> Void
    var body: some View {
        NavigationStack {
            List {
                if store.data.media.isEmpty { ContentUnavailableView("Dein Archiv ist noch leer", systemImage: "paperclip") }
                ForEach(store.data.media) { item in
                    Button { choose(item.id); dismiss() } label: { HStack { MediaAttachmentThumbnail(item: item); VStack(alignment: .leading) { Text(item.title); Text(item.kind.displayName).font(.caption).foregroundStyle(.secondary) } } }.accessibilityIdentifier("note.archive.choose." + item.id.uuidString)
                }
            }.navigationTitle("Anhang auswählen").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }.accessibilityIdentifier("note.archive")
        }
    }
}
