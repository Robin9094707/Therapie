import Foundation
import EventKit
import HomeKit

@MainActor
final class AppleRemindersService {
    static let shared = AppleRemindersService()
    private let events = EKEventStore()
    private let calendarKey = "therapy.apple.reminders.calendar"
    private let marker = "Therapie • verwalteter Eintrag\nID: "
    private var worker: Task<Void, Never>?
    private var queued = false
    private var observed = false
    private weak var store: AppStore?
    var authorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    func connect(_ store: AppStore) async {
        do {
            guard try await events.requestFullAccessToReminders() else { store.appleReminderStatus = "Zugriff abgelehnt. In den iPhone-Einstellungen kannst du ihn erlauben."; return }
            store.data.appleIntegration.remindersEnabled = true
            refresh(store)
        } catch { store.appleReminderStatus = error.localizedDescription }
    }
    func refresh(_ store: AppStore) {
        self.store = store
        if !observed {
            observed = true
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: events, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self, let store = self.store { self.refresh(store) } }
            }
        }
        queued = true
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            defer { self.worker = nil }
            // EventKit emits changes from our own writes too. Idempotent writes settle the queue.
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            repeat { self.queued = false; await self.reconcile(store) } while self.queued && !Task.isCancelled
        }
    }
    private func ownedCalendar(create: Bool) throws -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let existing = events.calendar(withIdentifier: id), existing.allowedEntityTypes.contains(.reminder) { return existing }
        guard create else { return nil }
        let calendar = EKCalendar(for: .reminder, eventStore: events)
        calendar.title = "Therapie · Routinen"
        guard let source = events.defaultCalendarForNewReminders()?.source ?? events.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
            throw ServiceError.generic("Keine beschreibbare Erinnerungen-Quelle gefunden. Richte zuerst eine Liste in Apple-Erinnerungen ein.")
        }
        calendar.source = source
        try events.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
        return calendar
    }
    private func reconcile(_ store: AppStore) async {
        guard store.storageReady, store.lastSaveError == nil else { return }
        guard authorized else { if store.data.appleIntegration.remindersEnabled { store.appleReminderStatus = "Apple-Erinnerungen benötigen vollen Zugriff. Verbinde die Liste in Apple-Integration." }; return }
        do {
            guard let calendar = try ownedCalendar(create: store.data.appleIntegration.remindersEnabled) else { return }
            let fetched: [EKReminder] = await withCheckedContinuation { continuation in
                events.fetchReminders(matching: events.predicateForReminders(in: [calendar])) { continuation.resume(returning: $0 ?? []) }
            }
            guard store.storageReady, store.lastSaveError == nil else { return }
            let owned = fetched.filter { ($0.notes ?? "").hasPrefix(marker) }
            func key(_ reminder: EKReminder) -> String { String((reminder.notes ?? "").dropFirst(marker.count)).components(separatedBy: "\n")[0] }
            let drafts = AppleReminderPlanner.drafts(data: store.data)
            let byID = Dictionary(drafts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if store.data.appleIntegration.remindersEnabled {
                var snapshot = store.data
                for reminder in owned where reminder.isCompleted {
                    guard let draft = byID[key(reminder)] else { continue }
                    if let occurrence = draft.routineOccurrence, !RoutinePlanner.resolved(occurrence, completions: snapshot.routineCompletions),
                       let routine = snapshot.routines.first(where: { $0.id == occurrence.routineID }) {
                        snapshot.routineCompletions.insert(.init(routineID: occurrence.routineID, timeID: occurrence.timeID, scheduledAt: occurrence.scheduledAt,
                            recordedAt: reminder.completionDate ?? Date(), outcome: .done, note: "In Apple-Erinnerungen bestätigt", routineTitle: routine.title), at: 0)
                        snapshot.routineSnoozes.removeAll { $0.id == occurrence.id }
                    }
                    if let id = draft.taskID, let index = snapshot.weeklyTasks.firstIndex(where: { $0.id == id && !$0.completed }) {
                        snapshot.weeklyTasks[index].completed = true; snapshot.weeklyTasks[index].completedAt = reminder.completionDate ?? Date()
                    }
                }
                if snapshot != store.data { store.data = snapshot; guard store.lastSaveError == nil else { return } }
            }
            let desired = AppleReminderPlanner.drafts(data: store.data)
            let valid = Set(desired.map(\.id))
            var existing = Dictionary(owned.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
            for reminder in owned where !valid.contains(key(reminder)) {
                if !store.data.appleIntegration.remindersEnabled || store.data.appleIntegration.removeFinishedReminders {
                    try events.remove(reminder, commit: false)
                } else if !reminder.isCompleted { reminder.isCompleted = true; try events.save(reminder, commit: false) }
            }
            for draft in desired {
                let reminder = existing.removeValue(forKey: draft.id) ?? EKReminder(eventStore: events)
                let isNew = reminder.calendar == nil
                if isNew { reminder.calendar = calendar }
                let parts = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: draft.due)
                let url = URL(string: "therapie://" + draft.route)
                if isNew || reminder.title != draft.title || reminder.dueDateComponents != parts || reminder.url != url || reminder.isCompleted {
                    reminder.title = draft.title; reminder.notes = marker + draft.id
                    reminder.dueDateComponents = parts; reminder.url = url; reminder.isCompleted = false
                    reminder.alarms = [EKAlarm(absoluteDate: draft.due)]
                    try events.save(reminder, commit: false)
                }
            }
            try events.commit()
            store.appleReminderStatus = store.data.appleIntegration.remindersEnabled ? "\(desired.count) Einträge in „Therapie · Routinen“. Zuletzt abgeglichen: \(Date().formatted(date: .omitted, time: .shortened))." : "Verwaltete Erinnerungen entfernt. Andere Listen bleiben erhalten."
        } catch { events.reset(); store.appleReminderStatus = "Abgleich fehlgeschlagen: " + error.localizedDescription }
    }
}

@MainActor
final class TherapyHomeService: NSObject, ObservableObject, HMHomeManagerDelegate {
    static let shared = TherapyHomeService()
    @Published var scenes: [HomeSceneChoice] = []
    @Published var status = "HomeKit ist optional."
    private var manager: HMHomeManager?
    private let bindingsKey = "therapy.home.scene.bindings"
    struct HomeSceneChoice: Identifiable { var id: String; var title: String; var home: HMHome; var scene: HMActionSet }
    private var signingAllowsHomeKit: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let bytes = try? Data(contentsOf: url),
              let text = String(data: bytes, encoding: .isoLatin1), let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let object = try? PropertyListSerialization.propertyList(from: Data(text[start.lowerBound..<end.upperBound].utf8), format: nil) as? [String:Any],
              let entitlements = object["Entitlements"] as? [String:Any] else { return false }
        return entitlements["com.apple.developer.homekit"] as? Bool == true
    }
    func connect() {
        guard signingAllowsHomeKit else {
            status = "Diese Signierung gibt HomeKit nicht frei. Verwende eine persönliche Automation in Kurzbefehle mit einer Home-Szene. Der Signaturdienst muss die HomeKit-Berechtigung erhalten."; return
        }
        if manager == nil { manager = HMHomeManager(); manager?.delegate = self }
        update()
    }
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { Task { @MainActor in self.update() } }
    private func update() {
        scenes = (manager?.homes ?? []).flatMap { home in home.actionSets.map { HomeSceneChoice(id: $0.uniqueIdentifier.uuidString, title: home.name + " · " + $0.name, home: home, scene: $0) } }.sorted { $0.title < $1.title }
        status = scenes.isEmpty ? "Noch keine freigegebenen Home-Szenen. Erlaube den Zugriff und lege eine Szene in Apple Home an." : "\(scenes.count) Home-Szenen verfügbar."
    }
    func binding(for id: UUID) -> String { (UserDefaults.standard.dictionary(forKey: bindingsKey) as? [String:String])?[id.uuidString] ?? "" }
    func bind(_ sceneID: String, to id: UUID) {
        var bindings = UserDefaults.standard.dictionary(forKey: bindingsKey) as? [String:String] ?? [:]
        if sceneID.isEmpty { bindings.removeValue(forKey: id.uuidString) } else { bindings[id.uuidString] = sceneID }
        UserDefaults.standard.set(bindings, forKey: bindingsKey); objectWillChange.send()
    }
    func run(for id: UUID, occurrenceID: String? = nil) {
        let sceneID = binding(for: id)
        guard !sceneID.isEmpty else { return }
        connect()
        guard let choice = scenes.first(where: { $0.id == sceneID }) else { return }
        let doneKey = occurrenceID.map { "therapy.home.ran." + $0 }
        if let doneKey, UserDefaults.standard.bool(forKey: doneKey) { return }
        choice.home.executeActionSet(choice.scene) { error in
            Task { @MainActor in
                if let error { self.status = error.localizedDescription }
                else { self.status = "Szene „\(choice.scene.name)“ ausgeführt."; if let doneKey { UserDefaults.standard.set(true, forKey: doneKey) } }
            }
        }
    }
}
