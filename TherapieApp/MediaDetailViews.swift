import SwiftUI
import UIKit
import QuickLook
import AVFoundation

struct MediaAttachmentThumbnail: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    var body: some View {
        if item.attachmentOmitted != true, item.kind == .photo, let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
        } else { Image(systemName: item.kind.symbol).font(.title2).frame(width: 56, height: 56).background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true) }
    }
}
@MainActor final class TherapyAudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func load(_ url: URL) {
        stop()
        do { let value = try AVAudioPlayer(contentsOf: url); value.delegate = self; value.prepareToPlay(); player = value; duration = value.duration; position = 0; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func toggle() {
        guard let player else { return }
        if playing { player.pause(); playing = false; timer?.invalidate(); timer = nil; return }
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true)
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { throw ServiceError.generic("Die Aufnahme konnte nicht abgespielt werden.") }
            playing = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 } }
        } catch { self.error = error.localizedDescription }
    }
    func seek(_ value: Double) { position = max(0, min(duration, value)); player?.currentTime = position }
    func stop() { player?.stop(); player = nil; timer?.invalidate(); timer = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.playing = false; self.position = self.duration; self.timer?.invalidate(); self.timer = nil } }
}
struct TherapyMediaDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @StateObject private var audio = TherapyAudioPlayback()
    let itemID: UUID
    @State private var editing: MediaItem?
    @State private var preview: URL?
    private var item: MediaItem? { store.data.media.first { $0.id == itemID } }
    private func availableURL(_ item: MediaItem) -> URL? {
        guard item.attachmentOmitted != true, let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL), FileManager.default.fileExists(atPath: url.path) else { return nil }; return url
    }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                if let item {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(item.title, systemImage: item.kind.symbol).font(.system(.title2, design: .rounded, weight: .bold)).textSelection(.enabled)
                                Text(item.createdAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                if !item.note.isEmpty { Text(item.note).textSelection(.enabled) }
                                if let source = item.source, !source.isEmpty { Text("Quelle: " + source).font(.caption).foregroundStyle(.secondary) }
                                HashtagChips(tags: item.tags)
                            }
                        }
                        if let url = availableURL(item) {
                            if item.kind == .photo, let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityLabel(item.title)
                            }
                            if item.kind == .audio {
                                GlassCard {
                                    VStack(spacing: 16) {
                                        Label("Deine Sprachnachricht", systemImage: "waveform").font(.headline)
                                        Button(audio.playing ? "Pause" : "Anhören", systemImage: audio.playing ? "pause.circle.fill" : "play.circle.fill") { audio.toggle() }.buttonStyle(.borderedProminent).disabled(audio.duration <= 0).accessibilityIdentifier("media.audio.play")
                                        Slider(value: Binding(get: { audio.position }, set: { audio.seek($0) }), in: 0...max(1, audio.duration)).accessibilityLabel("Position in der Aufnahme")
                                        HStack { Text(clock(audio.position)); Spacer(); Text(clock(audio.duration)) }.font(.caption.monospacedDigit())
                                        if let error = audio.error { Text(error).font(.caption).foregroundStyle(.red) }
                                    }
                                }.task(id: url) { audio.load(url) }
                            }
                            ResponsiveButtonRow {
                                Button(item.kind == .photo ? "Bild groß öffnen" : "Datei öffnen", systemImage: "arrow.up.right.square") { preview = url }.buttonStyle(.bordered)
                                ShareLink(item: url) { Label("Teilen", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                            }
                        } else { ContentUnavailableView("Datei nicht verfügbar", systemImage: "doc.badge.ellipsis", description: Text("Die Informationen bleiben erhalten. Die Datei fehlt oder wurde beim Backup ausgelassen.")) }
                    }
                } else { ContentUnavailableView("Material nicht mehr vorhanden", systemImage: "doc.badge.ellipsis") }
            }.navigationTitle("Dein Material").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.accessibilityIdentifier("media.detail.close") }
                    ToolbarItem(placement: .confirmationAction) { if let item { Button("Bearbeiten", systemImage: "pencil") { editing = item } } }
                }
                .sheet(item: $editing) { TherapyMediaEditorView(item: $0) }
                .quickLookPreview($preview)
                .onDisappear { audio.stop() }
                .onChange(of: scene) { _, phase in if phase != .active, audio.playing { audio.toggle() } }
        }
    }
    private func clock(_ value: Double) -> String { let seconds = max(0, Int(value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
struct TherapyNoteDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    @State private var editing: TherapyNote?
    @State private var media: MediaItem?
    private var note: TherapyNote? { store.data.notes.first { $0.id == noteID } }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                if let note {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard(emphasized: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(note.title, systemImage: note.isImportant == true ? "pin.fill" : "note.text").font(.system(.title2, design: .rounded, weight: .bold))
                                Text(note.createdAt.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                HashtagChips(tags: note.tags)
                                if let author = note.author { Text(author).font(.caption).foregroundStyle(.secondary) }
                                if !note.text.isEmpty { Text(note.text).textSelection(.enabled).accessibilityIdentifier("note.detail.text") }
                            }
                        }
                        if !(note.mediaIDs ?? []).isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Deine Anhänge", icon: "paperclip")
                                    ForEach(note.mediaIDs ?? [], id: \.self) { id in
                                        if let item = store.data.media.first(where: { $0.id == id }) {
                                            Button { media = item } label: { HStack { MediaAttachmentThumbnail(item: item); VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.kind.displayName + " · öffnen").font(.caption) }; Spacer(); Image(systemName: "chevron.right") } }.accessibilityIdentifier("note.detail.attachment." + id.uuidString)
                                        } else { Label("Anhang nicht mehr im Archiv", systemImage: "paperclip") }
                                    }
                                }
                            }
                        }
                    }
                } else { ContentUnavailableView("Notiz nicht mehr vorhanden", systemImage: "note.text") }
            }.navigationTitle("Deine Notiz").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { if let note { Button("Bearbeiten", systemImage: "pencil") { editing = note } } } }
                .sheet(item: $editing) { TherapyNoteEditorView(note: $0) }
                .sheet(item: $media) { TherapyMediaDetailView(itemID: $0.id) }
        }
    }
}
