import Foundation
import SwiftUI
import AlarmKit
import AppIntents
import CryptoKit

struct OpenRoutineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Routine öffnen"
    static var openAppWhenRun = true
    @Parameter(title: "Routine") var routineID: String
    init() {}
    init(routineID: UUID) { self.routineID = routineID.uuidString }
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(routineID, forKey: "therapy.routine.open")
        return .result()
    }
}
struct OpenCompanionReminderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Erinnerung öffnen"
    static var openAppWhenRun = true
    @Parameter(title: "Eintrag") var route: String
    init() {}
    init(route: String) { self.route = route }
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(route, forKey: "therapy.companion.open")
        return .result()
    }
}
@MainActor
final class RoutineAlarmCoordinator {
    static let shared = RoutineAlarmCoordinator()
    private let storageKey = "therapy.routine.alarms"
    private var revision = 0
    private var refreshing = false
    private var refreshRequested = false
    func requestAccess(_ store: AppStore) async {
        do {
            let granted = try await AlarmService.shared.requestAuthorization()
            store.routineAlarmStatus = granted ? "Wecker sind freigegeben." : "Bitte Wecker in den iPhone-Einstellungen erlauben."
            await refresh(store)
        } catch { store.routineAlarmStatus = error.localizedDescription }
    }
    func refresh(_ store: AppStore) async {
        refreshRequested = true
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshRequested = false
            await reconcile(store)
        } while refreshRequested && !Task.isCancelled
    }
    private func reconcile(_ store: AppStore) async {
        let generation = revision
        guard store.lastSaveError == nil, store.loadError == nil else { return }
        if !store.data.schedule.alarmIDs.isEmpty {
            do {
                try AlarmService.shared.cancel(ids: store.data.schedule.alarmIDs)
                var snapshot = store.data
                if snapshot.schedule.therapyAlarmsEnabled == nil { snapshot.schedule.therapyAlarmsEnabled = true }
                snapshot.schedule.alarmIDs = []; store.data = snapshot
                guard store.lastSaveError == nil else { return }
            } catch { store.routineAlarmStatus = "Alte Therapie-Wecker konnten noch nicht entfernt werden: " + error.localizedDescription; return }
        }
        let candidates = CompanionAlarmPlanner.candidates(store.data)
        let desired = CompanionAlarmPlanner.admitted(candidates)
        var owned = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        func key(_ slot: CompanionAlarmSlot) -> String {
            let digest = SHA256.hash(data: Data((slot.title + "|" + slot.route).utf8)).map { String(format: "%02x", $0) }.joined()
            return slot.id + "." + digest
        }
        let valid = Set(desired.map(key))
        let inventory = try? AlarmManager.shared.alarms
        let alarms = inventory ?? []
        let alerting = Set(alarms.filter { $0.state == .alerting }.map(\.id))
        if inventory != nil {
            let live = Set(alarms.map(\.id))
            for (key, raw) in owned where UUID(uuidString: raw).map({ !live.contains($0) }) ?? true { owned.removeValue(forKey: key) }
        }
        var cancellationFailures = 0
        for (key, raw) in owned where !valid.contains(key) {
            if let id = UUID(uuidString: raw) {
                // Passing its fire time never means that a ringing alarm should be dismissed.
                // Explicit completion/removal may cancel it; ordinary refreshes leave it ringing.
                if alerting.contains(id) && AlarmOwnershipPolicy.keepAlerting(key: key, data: store.data) { continue }
                do { try AlarmManager.shared.cancel(id: id); owned.removeValue(forKey: key) }
                catch { cancellationFailures += 1 }
            } else { owned.removeValue(forKey: key) }
        }
        UserDefaults.standard.set(owned, forKey: storageKey)
        guard AlarmManager.shared.authorizationState == .authorized else {
            store.routineAlarmStatus = desired.isEmpty ? "Keine optionalen Wecker geplant." : "Wecker benötigen deine AlarmKit-Freigabe. Mitteilungen und Wecker haben getrennte Freigaben."
            return
        }
        guard cancellationFailures == 0 else {
            store.routineAlarmStatus = "\(cancellationFailures) alte Wecker konnten nicht entfernt werden. Neue Wecker werden erst nach erfolgreicher Bereinigung ergänzt."
            return
        }
        do {
            for slot in desired where owned[key(slot)] == nil {
                guard generation == revision else { return }
                let id = UUID()
                let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: String(slot.title.prefix(100))))), metadata: TherapyAlarmMetadata(category: "companion", offsetMinutes: 0), tintColor: .indigo)
                let configuration = AlarmManager.AlarmConfiguration<TherapyAlarmMetadata>.alarm(schedule: .fixed(slot.fireAt), attributes: attributes, stopIntent: OpenCompanionReminderIntent(route: slot.route))
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                guard generation == revision else {
                    do { try AlarmManager.shared.cancel(id: id) }
                    catch { var retained = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]; retained[key(slot)] = id.uuidString; UserDefaults.standard.set(retained, forKey: storageKey) }
                    return
                }
                owned[key(slot)] = id.uuidString
                UserDefaults.standard.set(owned, forKey: storageKey)
            }
            let planned = Set(desired.map(\.id))
            let firstGap = candidates.first { !planned.contains($0.id) }?.fireAt
            let end = firstGap?.formatted(date: .abbreviated, time: .shortened) ?? desired.last?.fireAt.formatted(date: .abbreviated, time: .shortened) ?? "–"
            store.routineAlarmStatus = desired.isEmpty ? "Keine optionalen Wecker geplant." : "\(desired.count) AlarmKit-Wecker aktualisiert um \(Date().formatted(date: .omitted, time: .shortened)). Vorrat bis \(end); App regelmäßig öffnen."
            if firstGap != nil { store.routineAlarmStatus += " Weitere spätere Wiederholungen werden beim Öffnen ergänzt." }
        } catch { store.routineAlarmStatus = "Wecker konnten nicht vollständig eingerichtet werden: " + error.localizedDescription }
    }
    func cancel() {
        revision += 1
        refreshRequested = false
        var owned = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        for (key, raw) in owned {
            guard let id = UUID(uuidString: raw) else { owned.removeValue(forKey: key); continue }
            do { try AlarmManager.shared.cancel(id: id); owned.removeValue(forKey: key) } catch { /* Retain ownership for the next cleanup. */ }
        }
        UserDefaults.standard.set(owned, forKey: storageKey)
    }
}
