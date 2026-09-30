import Foundation
import UserNotifications

@MainActor
final class TaskNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotificationCoordinator()
    static let taskCategory = "THERAPY_TASK"
    static let energyCategory = "THERAPY_ENERGY_WEEK"
    static let energyIdentifier = "therapy.energy-week"
    private weak var store: AppStore?
    private var updateTask: Task<Void, Never>?
    private var generation = 0

    func attach(_ store: AppStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: "DONE", title: "Erledigt", options: [.foreground]),
            UNNotificationAction(identifier: "LATER", title: "Eine Stunde später", options: [.foreground]),
            UNNotificationAction(identifier: "OPEN", title: "Weiterarbeiten", options: [.foreground])
        ]
        let category = UNNotificationCategory(identifier: Self.taskCategory, actions: actions, intentIdentifiers: [])
        let energy = UNNotificationCategory(identifier: Self.energyCategory, actions: [UNNotificationAction(identifier: "ENERGY", title: "Wochenenergie eintragen", options: [.foreground])], intentIdentifiers: [])
        center.setNotificationCategories([category, energy])
    }
    func refresh(_ store: AppStore) {
        self.store = store
        generation += 1; let revision = generation
        updateTask?.cancel()
        updateTask = Task {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await apply(snapshot: store.data, revision: revision)
        }
    }
    func requestAccess(_ store: AppStore) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            store.taskReminderStatus = granted ? "Mitteilungen sind freigegeben." : "Mitteilungen sind nicht erlaubt. Aktiviere sie in den iPhone-Einstellungen."
            refresh(store)
        } catch { store.taskReminderStatus = error.localizedDescription }
    }
    private func apply(snapshot: AppData, revision: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard revision == generation else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            let pending = await center.pendingNotificationRequests()
            guard revision == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("therapy.task.") || $0.identifier == Self.energyIdentifier }.map(\.identifier))
            store?.taskReminderStatus = "Für Aufgabenerinnerungen bitte Mitteilungen freigeben."
            return
        }
        let all = TaskReminderPlanner.slots(tasks: snapshot.weeklyTasks, schedule: snapshot.schedule)
        // Never schedule half of a task's selected days: later tasks remain unscheduled with a visible count.
        let slots = TaskReminderPlanner.admittedSlots(all), admitted = Set(slots.map(\.taskID))
        var requests: [UNNotificationRequest] = []
        for slot in slots {
            guard let task = snapshot.weeklyTasks.first(where: { $0.id == slot.taskID }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Dein nächster kleiner Schritt"
            content.body = snapshot.reminderPreferences.privateTaskTitles ? "Eine offene Wochenaufgabe wartet auf dich. Du kannst weitermachen, verschieben oder sie als erledigt markieren." : String(task.title.prefix(160))
            content.categoryIdentifier = Self.taskCategory
            content.userInfo = ["taskID": task.id.uuidString]
            if snapshot.reminderPreferences.taskSound { content.sound = .default }
            let components = DateComponents(hour: slot.hour, minute: slot.minute, weekday: slot.weekday)
            requests.append(UNNotificationRequest(identifier: slot.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
        if snapshot.reminderPreferences.energyReviewEnabled,
           let next = TherapyDateHelper.nextOccurrence(schedule: snapshot.schedule) {
            let date = next.addingTimeInterval(-Double(max(0, min(1440, snapshot.reminderPreferences.energyReviewMinutesBeforeTherapy))) * 60)
            let content = UNMutableNotificationContent()
            content.title = "Deine Wochenenergie"
            content.body = "Was hat dir seit der letzten Therapie Energie gegeben, was hat sie gekostet?"
            content.categoryIdentifier = Self.energyCategory
            content.userInfo = ["energyReview": true]
            content.sound = .default
            let parts = Calendar.current.dateComponents([.weekday, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: Self.energyIdentifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
        }
        let previous = await center.pendingNotificationRequests()
        guard revision == generation else { return }
        let validIDs = Set(requests.map(\.identifier))
        let stale = previous.filter { ($0.identifier.hasPrefix("therapy.task.") || $0.identifier == Self.energyIdentifier) && !validIDs.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let delivered = await center.deliveredNotifications()
        guard revision == generation else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("therapy.task.") && !validIDs.contains($0.request.identifier) }.map { $0.request.identifier })
        do {
            for request in requests {
                guard revision == generation else { return }
                try await center.add(request)
            }
            guard revision == generation else { return }
            let missing = Set(all.map(\.taskID)).subtracting(admitted).count
            store?.taskReminderStatus = missing == 0 ? "Erinnerungen für \(admitted.count) offene Aufgaben aktiv. Sie wiederholen sich bis zum Erledigen." : "\(admitted.count) Aufgaben mit Erinnerung; \(missing) weitere passen nicht mehr. Wähle täglich statt vieler einzelner Wochentage oder schalte nicht benötigte Erinnerungen aus."
        } catch { store?.taskReminderStatus = "Erinnerungen konnten nicht vollständig eingerichtet werden: " + error.localizedDescription }
    }
    func cancel() {
        generation += 1; updateTask?.cancel()
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("therapy.task.") || $0.identifier == Self.energyIdentifier }.map(\.identifier))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            guard let store = self.store else { return }
            if response.notification.request.content.categoryIdentifier == Self.energyCategory {
                store.openEnergyReview = true; return
            }
            guard let raw = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: raw),
                  let task = store.data.weeklyTasks.first(where: { $0.id == id }) else { return }
            switch response.actionIdentifier {
            case "DONE": if !task.completed { store.toggleTask(id) }
            case "LATER": store.postponeTask(id, minutes: 60); store.notificationTaskID = id
            default: store.notificationTaskID = id
            }
        }
    }
}
