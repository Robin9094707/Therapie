import SwiftUI
import AVFoundation

struct AIBuddyVoiceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = AudioRecorderService()
    @State private var file = FileManager.default.temporaryDirectory.appendingPathComponent("therapy-buddy-" + UUID().uuidString + ".m4a")
    @State private var duration: TimeInterval = 0
    @State private var busy = false
    @State private var starting = false
    @State private var error: String?
    @State private var recordingStart: Task<Void, Never>?
    @State private var transcription: Task<Void, Never>?
    let receive: (String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Deine Sprachnachricht", systemImage: "waveform").font(.headline)
                    Text("Nimm deinen eigenen Gedanken auf. Erst „An OpenAI zum Transkribieren senden“ lädt die Aufnahme hoch. Danach kannst du den erkannten Text bearbeiten, bevor du ihn an den KI-Begleiter sendest.").font(.subheadline).foregroundStyle(.secondary)
                    Text("Keine automatische Aufnahme von Gesprächen. Maximal zwei Minuten; die temporäre Aufnahme wird beim Schließen gelöscht.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if recorder.isRecording {
                        Text("Aufnahme · \(Int(recorder.elapsed)) Sek.").font(.title2.monospacedDigit()).foregroundStyle(.red)
                        Button("Aufnahme stoppen", systemImage: "stop.circle.fill") { duration = recorder.stop() }.buttonStyle(.borderedProminent)
                    } else {
                        if duration > 0 { Label("\(Int(ceil(duration))) Sekunden aufgenommen", systemImage: "checkmark.circle"); Button("Neu aufnehmen", systemImage: "arrow.clockwise") { start() } }
                        else { Button(starting ? "Mikrofon vorbereiten …" : "Aufnahme starten", systemImage: "mic.circle.fill") { start() }.disabled(starting) }
                        if duration > 0 {
                            Button(busy ? "Transkribiere …" : "An OpenAI zum Transkribieren senden", systemImage: "arrow.up.circle") { transcribe() }.buttonStyle(.borderedProminent).disabled(busy)
                            Text("\(store.data.aiSettings.transcriptionModel) · API-Kosten laut OpenAI-Tarif. Dein Transkript wird anschließend in das Eingabefeld übernommen.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if busy { ProgressView() }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
            }.navigationTitle("Einsprechen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { transcription?.cancel(); dismiss() } } }
                .onChange(of: recorder.elapsed) { _, elapsed in if elapsed >= 120 { duration = recorder.stop() } }
                .onChange(of: scenePhase) { _, phase in if phase != .active && recorder.isRecording { duration = recorder.stop() } }
                .onDisappear { recordingStart?.cancel(); transcription?.cancel(); _ = recorder.stop(); try? FileManager.default.removeItem(at: file) }
        }
    }
    private func start() {
        guard !busy, !starting else { return }
        starting = true; error = nil; duration = 0
        recordingStart = Task { @MainActor in defer { starting = false }; do { try await recorder.start(url: file) } catch { self.error = error.localizedDescription } }
    }
    private func transcribe() {
        guard !busy, let key = AIBuddyKeychain.read() else { error = "Bitte zuerst deinen API-Schlüssel hinterlegen."; return }
        busy = true; error = nil
        transcription = Task { @MainActor in
            defer { busy = false }
            do {
                let text = try await AIBuddyAPI().transcribe(file: file, settings: store.data.aiSettings, key: key)
                try Task.checkCancellation()
                receive(text); dismiss()
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
