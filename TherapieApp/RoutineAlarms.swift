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
@MainActor
final class RoutineAlarmCoordinator {
    static let shared = RoutineAlarmCoordinator()
    private let storageKey = "therapy.routine.alarms"
    private var revision = 0
    func requestAccess(_ store: AppStore) async {
        do {
            let granted = try await AlarmService.shared.requestAuthorization()
            store.routineAlarmStatus = granted ? "Wecker sind freigegeben." : "Bitte Wecker in den iPhone-Einstellungen erlauben."
            await refresh(store)
        } catch { store.routineAlarmStatus = error.localizedDescription }
    }
    func refresh(_ store: AppStore) async {
        revision += 1; let generation = revision
        let snapshot = store.data
        let candidates = RoutinePlanner.slots(data: snapshot).filter { slot in snapshot.routines.contains { $0.id == slot.occurrence.routineID && $0.urgentAlarm && $0.remindersEnabled } }
        var desired = RoutinePlanner.admittedSlots(candidates, budget: 4)
        var desiredIDs = Set(desired.map(\.id))
        for slot in candidates where desired.count < 8 {
            if desiredIDs.insert(slot.id).inserted { desired.append(slot) }
        }
        desired.sort { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
        var owned = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        func key(_ slot: RoutineReminderSlot) -> String {
            let routine = snapshot.routines.first(where: { $0.id == slot.occurrence.routineID })
            let timeTitle = routine?.times.first(where: { $0.id == slot.occurrence.timeID })?.title ?? ""
            let title = snapshot.companionSettings.privateRoutineTitles ? "private" : (routine?.title ?? "") + " · " + timeTitle
            let digest = SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
            return slot.id + "." + digest
        }
        let valid = Set(desired.map(key))
        if let alarms = try? AlarmManager.shared.alarms {
            let live = Set(alarms.map(\.id))
            for (key, raw) in owned where UUID(uuidString: raw).map({ !live.contains($0) }) ?? true { owned.removeValue(forKey: key) }
        }
        var cancellationFailures = 0
        for (key, raw) in owned where !valid.contains(key) {
            if let id = UUID(uuidString: raw) {
                do { try AlarmManager.shared.cancel(id: id); owned.removeValue(forKey: key) }
                catch { cancellationFailures += 1 }
            } else { owned.removeValue(forKey: key) }
        }
        UserDefaults.standard.set(owned, forKey: storageKey)
        guard AlarmManager.shared.authorizationState == .authorized else {
            store.routineAlarmStatus = desired.isEmpty ? "Keine dringenden Wecker geplant." : "Dringende Wecker benötigen deine AlarmKit-Freigabe."
            return
        }
        guard cancellationFailures == 0 else {
            store.routineAlarmStatus = "\(cancellationFailures) alte Wecker konnten nicht entfernt werden. Neue Wecker werden erst nach erfolgreicher Bereinigung ergänzt."
            return
        }
        // Device IDs live outside AppData and therefore never travel through backups.
        do {
            for slot in desired where owned[key(slot)] == nil {
                guard generation == revision else { return }
                guard let routine = snapshot.routines.first(where: { $0.id == slot.occurrence.routineID }) else { continue }
                let id = UUID()
                let timeTitle = routine.times.first(where: { $0.id == slot.occurrence.timeID })?.title ?? ""
                let publicTitle = routine.title + (timeTitle.isEmpty ? "" : " · " + timeTitle)
                let title = snapshot.companionSettings.privateRoutineTitles ? "Deine wichtige Routine" : String(publicTitle.prefix(100))
                let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title))), metadata: TherapyAlarmMetadata(category: "routine", offsetMinutes: 0), tintColor: .indigo)
                let configuration = AlarmManager.AlarmConfiguration<TherapyAlarmMetadata>.alarm(schedule: .fixed(slot.fireAt), attributes: attributes, stopIntent: OpenRoutineIntent(routineID: routine.id))
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                guard generation == revision else { try? AlarmManager.shared.cancel(id: id); return }
                owned[key(slot)] = id.uuidString
                UserDefaults.standard.set(owned, forKey: storageKey)
            }
            let planned = Set(desired.map(\.id))
            let firstGap = candidates.first { !planned.contains($0.id) }?.fireAt
            let end = firstGap?.formatted(date: .abbreviated, time: .shortened) ?? desired.last?.fireAt.formatted(date: .abbreviated, time: .shortened) ?? "–"
            store.routineAlarmStatus = desired.isEmpty ? "Keine dringenden Wecker geplant." : "\(desired.count) dringende Wecker eingerichtet. Vollständige Wiederholungen bis \(end); bis dahin App öffnen. Einzelne spätere Basis-Wecker können schon geplant sein."
            if cancellationFailures > 0 { store.routineAlarmStatus += " \(cancellationFailures) alte Wecker konnten nicht entfernt werden. Bitte in den iPhone-Einstellungen prüfen." }
        } catch { store.routineAlarmStatus = "Wecker konnten nicht vollständig eingerichtet werden: " + error.localizedDescription }
    }
    func cancel() {
        revision += 1
        let owned = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        for raw in owned.values { if let id = UUID(uuidString: raw) { try? AlarmManager.shared.cancel(id: id) } }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
