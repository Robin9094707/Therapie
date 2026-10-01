import Foundation
import SwiftUI
import ActivityKit
import UserNotifications

@MainActor
final class TherapySessionController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var liveStatus = ""
    private weak var store: AppStore?
    private var lastPresentedPhase: String?
    private var synchronizationGeneration = UUID()
    private var synchronizationTask: Task<Void, Never>?
    init(store: AppStore) { self.store = store }

    func start(_ template: TherapySessionTemplate) {
        guard !busy, template.isValid, let store, store.data.currentSession == nil else { return }
        store.data.currentSession = .start(template)
        guard store.lastSaveError == nil else { TherapyEffects.shared.failed(); return }
        TherapyEffects.shared.light()
        synchronize()
    }
    func pauseOrResume() {
        guard !busy, let store, var session = store.data.currentSession else { return }
        if session.pausedAt == nil { session.pause() } else { session.resume() }
        store.data.currentSession = session
        TherapyEffects.shared.light()
        synchronize()
    }
    func finish(early: Bool) {
        guard let store, var session = store.data.currentSession else { return }
        let now = Date()
        if session.pausedAt != nil { session.resume(at: now) }
        session.endedAt = early ? now : session.expectedEnd
        session.endedEarly = early
        var snapshot = store.data
        snapshot.currentSession = nil
        snapshot.sessionHistory.removeAll { $0.id == session.id }
        snapshot.sessionHistory.insert(session, at: 0)
        store.data = snapshot
        store.offerCheckIn(for: session)
        Self.cancelNotifications(session.id)
        let id = session.id.uuidString
        Task { for activity in Activity<TherapyActivityAttributes>.activities where activity.attributes.sessionID == id { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
    private func phaseSignature(_ session: RunningTherapySession) -> String {
        session.id.uuidString + ":" + String(session.phaseIndex() ?? -1) + ":" + String(session.pausedAt != nil) + ":" + String(store?.data.sessionPreferences.usesPrivateLiveActivity ?? false) + ":" + String(store?.data.sessionPreferences.liveActivityEnabled ?? false)
    }
    func reconcile() {
        guard let session = store?.data.currentSession else { lastPresentedPhase = nil; return }
        if session.pausedAt == nil, session.remaining() <= 0 { finish(early: false); return }
        if !busy, lastPresentedPhase != phaseSignature(session) { synchronize() }
    }
    func synchronize() {
        guard !busy, let store else { return }
        if let active = store.data.currentSession, active.pausedAt == nil, active.remaining() <= 0 { finish(early: false) }
        let session = store.data.currentSession
        lastPresentedPhase = session.map(phaseSignature)
        let preferences = store.data.sessionPreferences
        let generation = synchronizationGeneration
        busy = true
        synchronizationTask = Task {
            defer { if generation == synchronizationGeneration { busy = false } }
            for activity in Activity<TherapyActivityAttributes>.activities {
                if activity.attributes.sessionID != session?.id.uuidString || !preferences.liveActivityEnabled {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            guard generation == synchronizationGeneration else { return }
            guard let session else { liveStatus = ""; return }
            await synchronizeNotifications(session, preferences: preferences)
            guard generation == synchronizationGeneration, self.store?.data.currentSession?.id == session.id else { return }
            guard preferences.liveActivityEnabled else { liveStatus = "Live-Aktivität ausgeschaltet. Der Timer läuft in der App weiter."; return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                liveStatus = "Live-Aktivitäten sind in den iPhone-Einstellungen deaktiviert. Der Timer bleibt gespeichert."
                return
            }
            let state = activityState(session, privateMode: preferences.usesPrivateLiveActivity)
            let content = ActivityContent(state: state, staleDate: session.pausedAt == nil ? state.currentPhase()?.end ?? session.expectedEnd : nil)
            if let activity = Activity<TherapyActivityAttributes>.activities.first(where: { $0.attributes.sessionID == session.id.uuidString }) {
                await activity.update(content)
                liveStatus = "Live-Aktivität aktiv · Sperrbildschirm & Dynamic Island"
            } else {
                do {
                    _ = try Activity.request(attributes: TherapyActivityAttributes(sessionID: session.id.uuidString), content: content, pushType: nil)
                    liveStatus = "Live-Aktivität aktiv · Sperrbildschirm & Dynamic Island"
                } catch { liveStatus = "Live-Aktivität konnte nicht gestartet werden: " + error.localizedDescription }
            }
        }
    }

    func restoredData() {
        // Wait for an older synchronization before clearing its notifications.
        // Otherwise asynchronous cleanup could erase the newly restored timer.
        let pending = synchronizationTask
        synchronizationGeneration = UUID()
        let generation = synchronizationGeneration
        busy = true
        synchronizationTask = Task {
            await pending?.value
            guard generation == synchronizationGeneration else { return }
            for activity in Activity<TherapyActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            guard generation == synchronizationGeneration else { return }
            center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("therapy.session.") }.map(\.identifier))
            busy = false
            synchronize()
        }
    }
    private func activityState(_ session: RunningTherapySession, privateMode: Bool) -> TherapyActivityAttributes.ContentState {
        var cursor = session.clockStart
        let phases = session.phases.enumerated().map { index, phase in
            let end = cursor.addingTimeInterval(TimeInterval(max(1, phase.minutes) * 60))
            defer { cursor = end }
            return TherapyActivityAttributes.Phase(title: TherapyPhaseTimeline.displayTitle(phase.title, index: index, privateMode: privateMode), start: cursor, end: end)
        }
        var state = TherapyActivityAttributes.ContentState(start: session.clockStart, end: session.expectedEnd,
            paused: session.pausedAt != nil, remaining: Int(ceil(session.remaining())), phases: phases, referenceDate: session.pausedAt ?? Date())
        if let bytes = try? JSONEncoder().encode(state), bytes.count > 3500 { state.phases = [] }
        return state
    }
    private func synchronizeNotifications(_ session: RunningTherapySession, preferences: SessionPreferences) async {
        Self.cancelNotifications(session.id)
        guard session.pausedAt == nil, preferences.notifyAtEnd || preferences.notifyAtPhases else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        var cursor = session.clockStart
        for (index, phase) in session.phases.enumerated() {
            cursor = cursor.addingTimeInterval(TimeInterval(max(1, phase.minutes) * 60))
            let last = index == session.phases.count - 1
            guard (last ? preferences.notifyAtEnd : preferences.notifyAtPhases), cursor > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = last ? "Deine geplante Zeit ist um" : "Nächster Zeitabschnitt"
            content.body = last ? "Du kannst deinen Rückblick in der App festhalten." : "Dein Stundenplan geht zum nächsten Abschnitt über."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, cursor.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "therapy.session.\(session.id).\(index)", content: content, trigger: trigger))
        }
    }
    static func cancelNotifications(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<12).map { "therapy.session.\(id).\($0)" })
    }
    static func endAll() {
        Task { for activity in Activity<TherapyActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("therapy.session.") }.map(\.identifier))
        }
    }
}
