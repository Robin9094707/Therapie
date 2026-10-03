import SwiftUI
import AVFoundation
import PDFKit

struct ChatAudioPlayer: View {
    let url: URL
    var caption = "Sprachnachricht"
    @StateObject private var player = TherapyAudioPlayback()
    @Environment(\.scenePhase) private var scene
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.title).frame(width: 44, height: 44) }.accessibilityLabel(player.playing ? "Audio pausieren" : "Audio abspielen")
                VStack(alignment: .leading) { Text(caption).font(.caption.bold()); Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.1, player.duration)).accessibilityLabel("Audioposition") }
                Text("\(Int(player.position))/\(Int(ceil(player.duration))) s").font(.caption.monospacedDigit())
            }
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onAppear { player.load(url) }.onChange(of: url) { _, value in player.load(value) }.onDisappear { player.stop() }.onChange(of: scene) { _, phase in if phase != .active { player.stop() } else { player.load(url) } }
    }
}
struct ChatStoredAttachment: View {
    @EnvironmentObject private var store: AppStore
    var item: MediaItem
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading) {
            if item.attachmentOmitted == true { Label(item.title + " · Datei im Backup ausgelassen", systemImage: item.kind.symbol).font(.caption).foregroundStyle(.secondary) }
            else if let url = try? BackupArchive.sourceURL(item.relativePath, root: store.rootURL) {
                if item.kind == .audio { ChatAudioPlayer(url: url) }
                else { Button { open = true } label: { HStack { MediaAttachmentThumbnail(item: item); Text(item.title).font(.subheadline); Image(systemName: "arrow.up.right.square") } }.buttonStyle(.plain) }
            } else { Label("Anhang nicht verfügbar", systemImage: "exclamationmark.triangle").font(.caption) }
        }.sheet(isPresented: $open) { TherapyMediaDetailView(itemID: item.id) }
    }
}
/// Tap to lock, hold to record, swipe up to lock or left to discard. Release previews.
struct ChatVoiceRecorder: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scene
    @StateObject private var recorder = AudioRecorderService()
    @State private var file = FileManager.default.temporaryDirectory.appendingPathComponent("buddy-chat-" + UUID().uuidString + ".m4a")
    @State private var duration: TimeInterval = 0
    @State private var starting = false
    @State private var busy = false
    @State private var locked = false
    @State private var touchStart: Date?
    @State private var cancelledGesture = false
    @State private var consent = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var activityID = UUID()
    var disabled: Bool
    var beforeRecording: () -> Void
    var onStateChange: (Bool) -> Void
    var receive: (String, URL, TimeInterval) async -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if duration > 0 {
                ChatAudioPlayer(url: file, caption: "Vor dem Senden anhören")
                HStack {
                    Button("Verwerfen", systemImage: "trash") { reset() }.disabled(busy)
                    Spacer()
                    Button(busy ? "Transkribiere …" : "Audio senden", systemImage: "arrow.up.circle.fill") { send() }.buttonStyle(.borderedProminent).disabled(busy || disabled)
                }.font(.caption)
            } else {
                HStack {
                    if recorder.isRecording {
                        Text("\(Int(recorder.elapsed)) s · " + (locked ? "Aufnahme gesperrt" : "↑ Sperren · ← Verwerfen")).font(.caption.monospacedDigit()).foregroundStyle(.red)
                        Button("Verwerfen", systemImage: "trash") { operation?.cancel(); reset() }.font(.caption)
                        Button("Stoppen & anhören", systemImage: "stop.circle.fill") { stop() }.font(.caption)
                    }
                    if busy || starting { ProgressView().controlSize(.small) }
                    Image(systemName: recorder.isRecording ? "mic.circle.fill" : "mic.fill").font(.title2).foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor).frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle()).accessibilityLabel("Audio aufnehmen. Tippen zum Sperren, halten und nach oben wischen zum Sperren.").accessibilityAddTraits(.isButton)
                        .accessibilityAction { if recorder.isRecording { stop() } else { locked = true; start() } }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard !disabled, !busy, !cancelledGesture, duration == 0 else { return }
                            if touchStart == nil { touchStart = Date(); if !recorder.isRecording && !starting { start() } }
                            if value.translation.height < -60 { locked = true }
                            if value.translation.width < -100 { cancelledGesture = true; operation?.cancel(); reset() }
                        }.onEnded { _ in
                            defer { touchStart = nil; cancelledGesture = false }
                            guard !cancelledGesture, let start = touchStart else { return }
                            if Date().timeIntervalSince(start) < 0.35 || starting { locked = true }
                            else if !locked { stop() }
                        })
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .alert("Audio-Uploads aktivieren?", isPresented: $consent) {
            Button("Abbrechen", role: .cancel) {}
            Button("Aktivieren") { store.data.aiSettings.allowVoiceUploads = true; locked = true; start() }
        } message: { Text("Erst „Audio senden“ überträgt deine eigene Aufnahme an OpenAI zur Transkription und sendet danach den Text an deinen KI-Begleiter. API-Kosten entstehen. Maximal zwei Minuten. Die Originalaufnahme bleibt lokal im Chat und in Backups; Freigabe im KI-Profil widerrufbar.") }
        .onChange(of: recorder.elapsed) { _, value in if value >= 120 { stop() } }
        .onChange(of: recorder.isRecording) { _, _ in updateState() }
        .onChange(of: duration) { _, _ in updateState() }
        .onChange(of: starting) { _, _ in updateState() }
        .onChange(of: busy) { _, _ in updateState() }
        .onChange(of: scene) { _, phase in if phase != .active && recorder.isRecording { stop() } }
        .onChange(of: store.data.aiSettings.allowVoiceUploads) { _, allowed in if !allowed { operation?.cancel(); reset() } }
        .onDisappear { operation?.cancel(); reset(); store.activeBuddyVoiceIDs.remove(activityID); onStateChange(false) }
    }
    private func updateState() { let active = starting || busy || recorder.isRecording || duration > 0; if active { store.activeBuddyVoiceIDs.insert(activityID) } else { store.activeBuddyVoiceIDs.remove(activityID) }; onStateChange(active) }
    private func start() {
        guard !disabled, !starting, !busy else { return }
        guard store.data.aiSettings.allowVoiceUploads else { touchStart = nil; consent = true; return }
        guard AIBuddyKeychain.read() != nil else { error = "Bitte zuerst den API-Schlüssel hinterlegen."; return }
        beforeRecording(); starting = true; error = nil
        operation = Task { @MainActor in
            defer { starting = false }
            do { try await recorder.start(url: file); if Task.isCancelled { reset() } }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func stop() { guard recorder.isRecording else { return }; duration = recorder.stop(); locked = false }
    private func send() {
        guard !busy, duration > 0, let key = AIBuddyKeychain.read() else { return }
        busy = true; error = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let text = try await AIBuddyAPI().transcribe(file: file, settings: store.data.aiSettings, key: key)
                try Task.checkCancellation()
                guard store.data.aiSettings.allowVoiceUploads, store.data.aiSettings.enabled else { return }
                if await receive(text, file, duration) { reset() }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func reset() { _ = recorder.stop(); duration = 0; locked = false; try? FileManager.default.removeItem(at: file) }
}

enum ChatDocumentText {
    static func read(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 10_000_000 else { throw AIBuddyAPIError(message: "Dateien dürfen höchstens 10 MB groß sein.") }
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            var text = ""
            for index in 0..<min(30, pdf.pageCount) { text += pdf.page(at: index)?.string ?? ""; text += "\n"; if text.count >= 12000 { break } }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBuddyAPIError(message: "Dieses PDF hat keinen lesbaren Text. Für Bildinhalte bitte ein Foto anhängen.") }
            return String(text.prefix(12000))
        }
        guard size <= 1_000_000, let text = String(data: try Data(contentsOf: url), encoding: .utf8), !text.contains("\0") else { throw AIBuddyAPIError(message: "Bitte eine Textdatei oder ein PDF mit lesbarem Text auswählen.") }
        return String(text.prefix(12000))
    }
}
