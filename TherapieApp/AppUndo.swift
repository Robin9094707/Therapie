import SwiftUI

struct AppUndoStep {
    var date = Date()
    var snapshot: AppData
}

extension AppStore {
    func rememberChange(from old: AppData, to new: AppData) {
        guard !undoInProgress else { return }
        var before = old, after = new
        // Clock reconciliations and device identifiers are not user input transactions.
        before.currentSession = nil; after.currentSession = nil
        before.schedule.calendarEventIdentifier = nil; after.schedule.calendarEventIdentifier = nil
        before.schedule.alarmIDs = []; after.schedule.alarmIDs = []
        guard before != after else { return }
        pruneUndo()
        undoSteps.append(AppUndoStep(snapshot: old))
        if undoSteps.count > 20 { undoSteps.removeFirst(undoSteps.count - 20) }
        let retained = Set(new.media.map(\.relativePath))
        for item in old.media where !retained.contains(item.relativePath) { deferredMediaDeletion[item.relativePath] = Date().addingTimeInterval(600) }
        undoAvailable = true
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.undoAvailable = false
        }
    }
    func undoLastChange() {
        pruneUndo()
        guard let step = undoSteps.popLast() else { return }
        aiController.cancel()
        // Preserve the live timer and OS ownership while restoring the actual records/settings.
        var restored = step.snapshot
        restored.currentSession = data.currentSession
        restored.schedule.calendarEventIdentifier = data.schedule.calendarEventIdentifier
        restored.schedule.alarmIDs = data.schedule.alarmIDs
        let current = data
        undoInProgress = true
        data = restored
        undoInProgress = false
        if lastSaveError != nil { undoInProgress = true; data = current; undoInProgress = false; undoSteps.append(step) }
        undoAvailable = undoSteps.last.map { Date().timeIntervalSince($0.date) < 10 } ?? false
        if lastSaveError == nil { TherapyEffects.shared.light() }
    }
    func pruneUndo() {
        undoSteps.removeAll { Date().timeIntervalSince($0.date) > 600 }
        let retained = Set(data.media.map(\.relativePath) + undoSteps.flatMap { $0.snapshot.media.map(\.relativePath) })
        for (path, expiry) in deferredMediaDeletion where expiry <= Date() && !retained.contains(path) {
            do { try BackupArchive.validatePath(path); try FileManager.default.removeItem(at: rootURL.appendingPathComponent(path)) } catch { /* Retain current data even if cleanup cannot finish. */ }
            deferredMediaDeletion.removeValue(forKey: path)
        }
        undoAvailable = undoSteps.last.map { Date().timeIntervalSince($0.date) < 10 } ?? false
    }
    func clearUndo() { undoExpiryTask?.cancel(); undoExpiryTask = nil; undoSteps = []; deferredMediaDeletion = [:]; undoAvailable = false }
}

struct UndoChangesButton: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if store.undoAvailable && store.visibleAIComposerIDs.isEmpty {
            Button { store.undoLastChange() } label: { Label("Letzte Eingabe rückgängig", systemImage: "arrow.uturn.backward").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 10) }
                .buttonStyle(.plain).background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.08), radius: 6).padding(8)
                .accessibilityIdentifier("input.undo").accessibilityHint("Die Schaltfläche verschwindet zehn Sekunden nach der letzten Änderung")
        }
    }
}
