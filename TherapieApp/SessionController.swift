import Foundation
import SwiftUI
import ActivityKit
import UserNotifications
import UIKit
import BackgroundTasks

/// Owns the running therapy session's Live Activity (Lock Screen + Dynamic Island) and its reminders.
///
/// iOS only lets an app *start* a Live Activity while it is in the foreground, so the activity is requested
/// synchronously the moment a session starts or the app is about to leave the screen – never behind slower
/// notification work. Updates and endings run in one serial chain that captures its target activities up front,
/// so an older cleanup can never end a newer activity. Nothing is ended unless the stored data is really loaded.
@MainActor
final class TherapySessionController: ObservableObject {
    nonisolated static let refreshTaskIdentifier = "eu.rjuhas.therapie.session-refresh"
    @Published private(set) var busy = false
    @Published private(set) var liveStatus = ""
    private weak var store: AppStore?
    private var lastPresentedPhase: String?
    private var notificationGeneration = UUID()
    private var notificationTask: Task<Void, Never>?
    private var activityChain: Task<Void, Never>?
    private var backgroundAssertion: UIBackgroundTaskIdentifier = .invalid
    init(store: AppStore) { self.store = store }

    func start(_ template: TherapySessionTemplate) {
        guard template.isValid, let store, store.storageReady, store.data.currentSession == nil else { return }
        store.data.currentSession = .start(template)
        guard store.lastSaveError == nil else { TherapyEffects.shared.failed(); return }
        TherapyEffects.shared.light()
        synchronize()
    }
    func pauseOrResume() {
        guard let store, store.storageReady, var session = store.data.currentSession else { return }
        if session.pausedAt == nil { session.pause() } else { session.resume() }
        store.data.currentSession = session
        TherapyEffects.shared.light()
        synchronize()
    }
    func finish(early: Bool) {
        guard let store, store.storageReady, var session = store.data.currentSession else { return }
        guard early || store.activeBuddyVoiceIDs.isEmpty else { return }
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
        // Invalidate pending reminder work for this session; its generation check then skips cleanup, so release
        // the busy flag here instead of leaving the start buttons disabled.
        notificationGeneration = UUID()
        busy = false
        lastPresentedPhase = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
        var final = activityState(session, privateMode: store.data.sessionPreferences.usesPrivateLiveActivity)
        final.paused = false; final.finished = true; final.remaining = 0
        let content = ActivityContent(state: final, staleDate: nil)
        let targets = Self.activities()
        // Leave a calm "finished" card on the Lock Screen for a short while instead of vanishing abruptly.
        enqueueActivityWork {
            for activity in targets {
                if activity.attributes.sessionID == session.id.uuidString { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))) }
                else { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
        liveStatus = ""
    }

    /// Called when the app turns inactive or moves to the background. The app is still allowed to request a
    /// Live Activity while inactive, so a missing one is started here, and the current one receives fresh
    /// content (phase name, stale date at the next boundary) before iOS suspends the app.
    func prepareForBackground() {
        guard let store, store.storageReady, let session = store.data.currentSession else { return }
        beginBackgroundAssertion()
        if session.pausedAt == nil, session.remaining() <= 0 { finish(early: false); return }
        lastPresentedPhase = phaseSignature(session)
        presentLiveActivity(session, preferences: store.data.sessionPreferences, forceUpdate: true)
        scheduleBackgroundRefresh(for: session)
        // Release the assertion once the queued updates have been delivered to the system.
        let chain = activityChain
        Task { [weak self] in
            await chain?.value
            self?.endBackgroundAssertion()
        }
    }
    /// Manual repair while the app is visible: replaces the session's Live Activity with a freshly requested one.
    func reconnectLiveActivity() {
        guard let store, store.storageReady, let session = store.data.currentSession else { return }
        let preferences = store.data.sessionPreferences
        guard preferences.liveActivityEnabled else { liveStatus = "Live-Aktivität ausgeschaltet. Schalte sie in den Timer-Einstellungen ein."; return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveStatus = "Live-Aktivitäten sind in den iPhone-Einstellungen deaktiviert (Einstellungen › Therapie)."
            return
        }
        let previous = Self.activities()
        enqueueActivityWork { for activity in previous { await activity.end(nil, dismissalPolicy: .immediate) } }
        do {
            _ = try Activity.request(attributes: TherapyActivityAttributes(sessionID: session.id.uuidString), content: activityContent(session, preferences: preferences), pushType: nil)
            liveStatus = "Live-Aktivität neu verbunden · Sperrbildschirm & Dynamic Island"
            TherapyEffects.shared.light()
        } catch {
            liveStatus = "Live-Aktivität konnte nicht gestartet werden: " + error.localizedDescription
        }
        lastPresentedPhase = phaseSignature(session)
        scheduleBackgroundRefresh(for: session)
    }
    private func phaseSignature(_ session: RunningTherapySession) -> String {
        let preferences = store?.data.sessionPreferences
        return session.id.uuidString + ":" + String(session.phaseIndex() ?? -1) + ":" + String(session.pausedAt != nil) + ":" + String(preferences?.usesPrivateLiveActivity ?? false) + ":" + String(preferences?.liveActivityEnabled ?? false)
    }
    func reconcile() {
        guard let store, store.storageReady else { return }
        guard let session = store.data.currentSession else { lastPresentedPhase = nil; return }
        if session.pausedAt == nil, session.remaining() <= 0 { finish(early: false); return }
        if lastPresentedPhase != phaseSignature(session) { synchronize() }
    }

    /// Brings Live Activity, phase reminders and the background refresh in line with the stored session.
    func synchronize() {
        // Never act on placeholder data: before the protected store is loaded `currentSession` reads as nil
        // and ending "stale" activities would remove the running session from the Dynamic Island.
        guard let store, store.storageReady else { return }
        if let active = store.data.currentSession, active.pausedAt == nil, active.remaining() <= 0 { finish(early: false); return }
        let session = store.data.currentSession
        let preferences = store.data.sessionPreferences
        lastPresentedPhase = session.map(phaseSignature)
        guard let session else {
            endActivities(except: nil)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            liveStatus = ""
            return
        }
        presentLiveActivity(session, preferences: preferences, forceUpdate: false)
        scheduleBackgroundRefresh(for: session)
        synchronizeNotifications(session, preferences: preferences)
    }

    private func presentLiveActivity(_ session: RunningTherapySession, preferences: SessionPreferences, forceUpdate: Bool) {
        let id = session.id.uuidString
        guard preferences.liveActivityEnabled else {
            endActivities(except: nil)
            liveStatus = "Live-Aktivität ausgeschaltet. Der Timer läuft in der App weiter."
            return
        }
        endActivities(except: id)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveStatus = "Live-Aktivitäten sind in den iPhone-Einstellungen deaktiviert (Einstellungen › Therapie). Der Timer bleibt gespeichert."
            return
        }
        let content = activityContent(session, preferences: preferences)
        if let activity = Self.activities().first(where: { $0.attributes.sessionID == id }) {
            if forceUpdate || activity.content.state != content.state || activity.content.staleDate != content.staleDate {
                enqueueActivityWork { await activity.update(content) }
            }
            liveStatus = "Live-Aktivität aktiv · Sperrbildschirm & Dynamic Island"
        } else {
            do {
                // Synchronous on purpose: this must happen while the app is still allowed to start activities.
                _ = try Activity.request(attributes: TherapyActivityAttributes(sessionID: id), content: content, pushType: nil)
                liveStatus = "Live-Aktivität aktiv · Sperrbildschirm & Dynamic Island"
            } catch {
                liveStatus = "Live-Aktivität konnte nicht gestartet werden: " + error.localizedDescription + " Öffne die App erneut, um es nochmal zu versuchen."
            }
        }
    }
    private func activityContent(_ session: RunningTherapySession, preferences: SessionPreferences) -> ActivityContent<TherapyActivityAttributes.ContentState> {
        let state = activityState(session, privateMode: preferences.usesPrivateLiveActivity)
        // Stale at the next phase boundary (or the planned end): iOS redraws the activity at that moment, so the
        // phase name and the "time is up" state are recomputed even while the app stays suspended.
        let staleDate = session.pausedAt == nil ? Self.nextBoundary(in: state, after: Date()) : nil
        return ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)
    }
    nonisolated static func nextBoundary(in state: TherapyActivityAttributes.ContentState, after date: Date) -> Date? {
        guard !state.paused, state.finished != true, date < state.end else { return nil }
        return state.phases.map(\.end).filter { $0 > date }.min() ?? state.end
    }
    private func endActivities(except keptID: String?) {
        let targets = Self.activities().filter { $0.attributes.sessionID != keptID }
        guard !targets.isEmpty else { return }
        enqueueActivityWork { for activity in targets { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
    private func enqueueActivityWork(_ work: @escaping @MainActor () async -> Void) {
        let previous = activityChain
        activityChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
    private static func activities() -> [Activity<TherapyActivityAttributes>] { Activity<TherapyActivityAttributes>.activities }

    // MARK: Background refresh

    /// Asks iOS to wake the app near the next phase boundary. iOS decides the exact time; the stale date and the
    /// timer-driven views keep the Live Activity correct in between.
    private func scheduleBackgroundRefresh(for session: RunningTherapySession) {
        guard session.pausedAt == nil, store?.data.sessionPreferences.liveActivityEnabled == true else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }
        Self.submitBackgroundRefresh(at: Self.nextBoundary(in: activityState(session, privateMode: true), after: Date()))
    }
    nonisolated static func submitBackgroundRefresh(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskIdentifier)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = date.addingTimeInterval(1)
        try? BGTaskScheduler.shared.submit(request)
    }
    /// Runs from the app-refresh background task. It needs no access to the protected data store: every running
    /// activity already carries its phase plan, so it only redraws (new stale date) or ends after the planned time.
    nonisolated static func refreshLiveActivitiesInBackground() async {
        let now = Date()
        var next: Date?
        for activity in Activity<TherapyActivityAttributes>.activities {
            var state = activity.content.state
            guard state.finished != true, !state.paused else { continue }
            if now >= state.end {
                state.finished = true; state.remaining = 0
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(now.addingTimeInterval(15 * 60)))
            } else {
                let stale = nextBoundary(in: state, after: now)
                state.remaining = Int(ceil(state.end.timeIntervalSince(now)))
                await activity.update(ActivityContent(state: state, staleDate: stale, relevanceScore: 100))
                if let stale { next = min(next ?? stale, stale) }
            }
        }
        submitBackgroundRefresh(at: next)
    }

    private func beginBackgroundAssertion() {
        guard backgroundAssertion == .invalid else { return }
        backgroundAssertion = UIApplication.shared.beginBackgroundTask(withName: "Therapie-Live-Aktivität") { [weak self] in
            Task { @MainActor in self?.endBackgroundAssertion() }
        }
    }
    private func endBackgroundAssertion() {
        guard backgroundAssertion != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundAssertion)
        backgroundAssertion = .invalid
    }

    func restoredData() {
        // Wait for older work before clearing notifications; asynchronous cleanup could otherwise erase the
        // newly restored timer.
        let pendingNotifications = notificationTask
        notificationGeneration = UUID()
        let generation = notificationGeneration
        let targets = Self.activities()
        lastPresentedPhase = nil
        busy = true
        enqueueActivityWork { for activity in targets { await activity.end(nil, dismissalPolicy: .immediate) } }
        let chain = activityChain
        notificationTask = Task {
            await pendingNotifications?.value
            await chain?.value
            guard generation == notificationGeneration else { return }
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            guard generation == notificationGeneration else { return }
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
            paused: session.pausedAt != nil, remaining: Int(ceil(session.remaining())), phases: phases, referenceDate: session.pausedAt)
        state.title = TherapyPhaseTimeline.sessionTitle(session.title, privateMode: privateMode)
        if let bytes = try? JSONEncoder().encode(state), bytes.count > 3500 { state.phases = [] }
        return state
    }
    private func synchronizeNotifications(_ session: RunningTherapySession, preferences: SessionPreferences) {
        notificationGeneration = UUID()
        let generation = notificationGeneration
        let previous = notificationTask
        busy = true
        notificationTask = Task {
            await previous?.value
            defer { if generation == notificationGeneration { busy = false } }
            guard generation == notificationGeneration else { return }
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
                guard generation == notificationGeneration else { return }
                let content = UNMutableNotificationContent()
                content.title = last ? "Deine geplante Zeit ist um" : "Nächster Zeitabschnitt"
                if last { content.body = "Du kannst deinen Rückblick in der App festhalten." }
                else if index + 1 < session.phases.count, !preferences.usesPrivateLiveActivity { content.body = "Jetzt: " + session.phases[index + 1].title }
                else { content.body = "Dein Stundenplan geht zum nächsten Abschnitt über." }
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, cursor.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "therapy.session.\(session.id).\(index)", content: content, trigger: trigger))
            }
        }
    }
    static func cancelNotifications(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<12).map { "therapy.session.\(id).\($0)" })
    }
    static func endAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskIdentifier)
        Task { for activity in Activity<TherapyActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("therapy.session.") }.map(\.identifier))
        }
    }
}
