import Foundation
import UserNotifications

@MainActor
final class TaskNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotificationCoordinator()
    static let taskCategory = "THERAPY_TASK"
    static let routineCategory = "THERAPY_ROUTINE"
    static let checkInCategory = "THERAPY_CHECKIN"
    static let energyCategory = "THERAPY_ENERGY_WEEK"
    static let energyIdentifier = "therapy.energy-week"
    static let assistedLivingCategory = "THERAPY_BEWO"
    static let quietEndIdentifier = "therapy.quiet.end"
    /// Identifiers this coordinator owns; anything else (session, weekly check-in) is managed elsewhere.
    static func owns(_ identifier: String) -> Bool {
        identifier.hasPrefix("therapy.task.") || identifier.hasPrefix("therapy.routine.") || identifier.hasPrefix("therapy.checkin.")
            || identifier.hasPrefix("therapy.bewo.") || identifier == energyIdentifier || identifier == quietEndIdentifier
    }
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
        let routine = UNNotificationCategory(identifier: Self.routineCategory, actions: [
            UNNotificationAction(identifier: "ROUTINE_OPEN", title: "Öffnen & bestätigen", options: [.foreground]),
            UNNotificationAction(identifier: "ROUTINE_LATER", title: "Eine Stunde später", options: [.foreground])
        ], intentIdentifiers: [])
        let checkIn = UNNotificationCategory(identifier: Self.checkInCategory, actions: [UNNotificationAction(identifier: "CHECKIN_OPEN", title: "Check-in starten", options: [.foreground])], intentIdentifiers: [])
        let bewo = UNNotificationCategory(identifier: Self.assistedLivingCategory, actions: [UNNotificationAction(identifier: "BEWO_OPEN", title: "Vorbereiten", options: [.foreground])], intentIdentifiers: [])
        center.setNotificationCategories([category, energy, routine, checkIn, bewo])
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
        if let store { await RoutineAlarmCoordinator.shared.refresh(store) }
        let settings = await center.notificationSettings()
        guard revision == generation else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            let pending = await center.pendingNotificationRequests()
            guard revision == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { Self.owns($0.identifier) }.map(\.identifier))
            store?.taskReminderStatus = "Für Aufgabenerinnerungen bitte Mitteilungen freigeben."
            store?.checkInReminderStatus = "Bitte Mitteilungen in den iPhone-Einstellungen erlauben."
            store?.routineReminderStatus = "Routine-Mitteilungen sind nicht freigegeben. Bitte in den iPhone-Einstellungen erlauben."
            return
        }
        let all = TaskReminderPlanner.slots(tasks: snapshot.weeklyTasks, schedule: snapshot.schedule)
        // Never schedule half of a task's selected days: later tasks remain unscheduled with a visible count.
        let taskBudget = (snapshot.routines.contains { $0.enabled && $0.remindersEnabled } || !(snapshot.companionSettings.checkInReminders ?? []).filter(\.enabled).isEmpty) ? 16 : 40
        let slots = TaskReminderPlanner.admittedSlots(all, budget: taskBudget), admitted = Set(slots.map(\.taskID))
        var requests: [UNNotificationRequest] = []
        let quiet = snapshot.quietMode
        var quietTaskSlots = 0
        for slot in slots {
            guard let task = snapshot.weeklyTasks.first(where: { $0.id == slot.taskID }) else { continue }
            // Quiet mode: a timed pause delivers the first occurrence after it once; permanent silence skips it.
            let plan = ReminderInventory.taskPlan(slot, settings: quiet)
            if plan != .repeating { quietTaskSlots += 1 }
            if plan == .none { continue }
            let content = UNMutableNotificationContent()
            content.title = "Dein nächster kleiner Schritt"
            content.body = snapshot.reminderPreferences.privateTaskTitles ? "Eine offene Wochenaufgabe wartet auf dich. Du kannst weitermachen, verschieben oder sie als erledigt markieren." : String(task.title.prefix(160))
            content.categoryIdentifier = Self.taskCategory
            content.userInfo = ["taskID": task.id.uuidString]
            if snapshot.reminderPreferences.taskSound { content.sound = .default }
            if case .once(let date) = plan {
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                requests.append(UNNotificationRequest(identifier: slot.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            } else {
                let components = DateComponents(hour: slot.hour, minute: slot.minute, weekday: slot.weekday)
                requests.append(UNNotificationRequest(identifier: slot.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            }
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
            if date > Date(), QuietPolicy.reason(category: .wellbeing, source: "energy", id: Self.energyIdentifier, fireAt: date, settings: quiet) == nil {
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                requests.append(UNNotificationRequest(identifier: Self.energyIdentifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
        let allCheckInSlots = CheckInReminderPlanner.slots(data: snapshot).filter {
            QuietPolicy.reason(category: .checkIns, source: "checkin.\($0.kind.rawValue)", id: $0.id, fireAt: $0.fireAt, settings: quiet) == nil
        }
        let checkInSlots = Array(allCheckInSlots.prefix(min(20, max(0, 48 - requests.count))))
        for slot in checkInSlots {
            let content = UNMutableNotificationContent()
            content.title = slot.title ?? slot.kind.title
            content.body = "Ein kurzer Moment für dich. Du kannst jede Frage überspringen und später weitermachen."
            content.sound = .default
            content.categoryIdentifier = Self.checkInCategory
            content.userInfo = ["checkInKind": slot.kind.rawValue, "slotID": slot.slotID?.uuidString ?? ""]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.fireAt)
            requests.append(UNNotificationRequest(identifier: slot.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        let routineCandidates = RoutinePlanner.slots(data: snapshot).filter { slot in
            guard let routine = snapshot.routines.first(where: { $0.id == slot.occurrence.routineID }) else { return false }
            guard !(snapshot.appleIntegration.remindersEnabled && routine.appleReminders != false) else { return false }
            return QuietPolicy.reason(category: .routines, source: "routine.\(routine.id)", id: slot.id, fireAt: slot.fireAt, settings: quiet) == nil
        }
        let routineSlots = RoutinePlanner.admittedSlots(routineCandidates, budget: max(0, 48 - requests.count))
        for slot in routineSlots {
            guard let routine = snapshot.routines.first(where: { $0.id == slot.occurrence.routineID }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Deine Routine wartet auf dich"
            let timeTitle = routine.times.first(where: { $0.id == slot.occurrence.timeID })?.title ?? ""
            let publicTitle = routine.title + (timeTitle.isEmpty ? "" : " · " + timeTitle)
            content.body = snapshot.companionSettings.privateRoutineTitles ? "Eine Routine ist noch offen. Öffne sie zum Bestätigen oder verschiebe sie eine Stunde." : String(publicTitle.prefix(160))
            content.sound = .default
            content.categoryIdentifier = Self.routineCategory
            content.userInfo = ["routineID": routine.id.uuidString, "timeID": slot.occurrence.timeID.uuidString, "due": slot.occurrence.due.timeIntervalSince1970, "scheduledAt": slot.occurrence.scheduledAt.timeIntervalSince1970]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.fireAt)
            requests.append(UNNotificationRequest(identifier: slot.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        for slot in AssistedLivingPlanner.reminderSlots(snapshot).prefix(max(0, 56 - requests.count))
            where QuietPolicy.reason(category: .assistedLiving, source: "bewo", id: slot.id, fireAt: slot.fireAt, settings: quiet) == nil {
            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = snapshot.assistedLivingSettings.privateTitles ? "Öffne die App, um dich in Ruhe vorzubereiten." : "Sammle vorher kurz deine Themen – die App zeigt dir die offene Liste."
            content.sound = .default
            content.categoryIdentifier = Self.assistedLivingCategory
            content.userInfo = ["bewo": slot.occurrence.id]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.fireAt)
            requests.append(UNNotificationRequest(identifier: slot.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        // The weekly mood moment repeats on its own; quiet mode removes it while silenced and restores it afterwards.
        if snapshot.wellnessSettings.reminderEnabled {
            let settings = snapshot.wellnessSettings
            let next = ReminderInventory.nextDates(weekday: max(1, min(7, settings.reminderWeekday)), hour: max(0, min(23, settings.reminderHour)), minute: max(0, min(59, settings.reminderMinute)), after: Date(), count: 1).first
            if let next, QuietPolicy.reason(category: .wellbeing, source: "wellness", id: "therapy.weekly-checkin.\(Int(next.timeIntervalSince1970))", fireAt: next, settings: quiet) != nil {
                center.removePendingNotificationRequests(withIdentifiers: [WeeklyReminderService.identifier])
            } else {
                let content = UNMutableNotificationContent()
                content.title = "Ein Moment für dich"
                content.body = "Wenn es für dich passt, halte kurz fest, wie deine Woche war."
                content.sound = .default
                let components = DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute, weekday: settings.reminderWeekday)
                try? await center.add(UNNotificationRequest(identifier: WeeklyReminderService.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            }
        }
        if quiet.announceEnd, let resume = QuietPolicy.resumeDate(quiet), resume > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Deine Ruhe ist vorbei"
            content.body = "Öffne Kompass kurz, damit alle Erinnerungen wieder regelmäßig laufen."
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resume)
            requests.append(UNNotificationRequest(identifier: Self.quietEndIdentifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        let previous = await center.pendingNotificationRequests()
        guard revision == generation else { return }
        let validIDs = Set(requests.map(\.identifier))
        // Repeating and one-shot task requests share an identifier; replace them so a changed trigger takes effect.
        let changedTriggers = previous.filter { old in requests.contains { $0.identifier == old.identifier && ($0.trigger as? UNCalendarNotificationTrigger)?.repeats != (old.trigger as? UNCalendarNotificationTrigger)?.repeats } }.map(\.identifier)
        let stale = previous.filter { Self.owns($0.identifier) && !validIDs.contains($0.identifier) }.map(\.identifier) + changedTriggers
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let delivered = await center.deliveredNotifications()
        guard revision == generation else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { ($0.request.identifier.hasPrefix("therapy.task.") || $0.request.identifier.hasPrefix("therapy.routine.") || $0.request.identifier.hasPrefix("therapy.checkin.") || $0.request.identifier.hasPrefix("therapy.bewo.")) && !validIDs.contains($0.request.identifier) }.map { $0.request.identifier })
        do {
            for request in requests {
                guard revision == generation else { return }
                try await center.add(request)
            }
            guard revision == generation else { return }
            store?.checkInReminderStatus = checkInSlots.isEmpty ? "Keine Check-in-Erinnerungen ausstehend." : "\(checkInSlots.count) Check-in-Erinnerungen für die nächsten 7 Tage geplant. Erledigte Check-ins entfernen den Hinweis für diesen Tag. Öffne die App regelmäßig zum Erneuern."
            if allCheckInSlots.count > checkInSlots.count { store?.checkInReminderStatus += " \(allCheckInSlots.count - checkInSlots.count) spätere Hinweise passen aktuell nicht in den Vorrat; App regelmäßig öffnen." }
            let coveredIDs = Set(routineSlots.map(\.id))
            let firstGap = routineCandidates.first { !coveredIDs.contains($0.id) }?.fireAt
            let coverage = firstGap?.formatted(date: .abbreviated, time: .shortened) ?? routineSlots.last?.fireAt.formatted(date: .abbreviated, time: .shortened) ?? "–"
            let candidateRoutines = Set(routineCandidates.map { $0.occurrence.id })
            let scheduledRoutines = Set(routineSlots.map { $0.occurrence.id })
            let unplanned = candidateRoutines.subtracting(scheduledRoutines).count
            store?.routineReminderStatus = routineSlots.isEmpty ? "Keine Routine-Mitteilungen ausstehend." : "\(routineSlots.count) Hinweise eingerichtet. Vollständige Wiederholungen bis \(coverage). App bis dahin erneut öffnen. Spätere Basis-Hinweise können schon geplant sein."
            if unplanned > 0 { store?.routineReminderStatus += " \(unplanned) Termine haben aktuell keinen Platz im Vorrat. Vergrößere Wiederholungsabstände oder reduziere aktive Erinnerungen." }
            let missing = Set(all.map(\.taskID)).subtracting(admitted).count
            store?.quietStatus = QuietPolicy.globalPause(quiet).map { pause in pause.until.map { "Ruhe bis " + QuietPolicy.shortStamp($0) + "." } ?? "Ruhe ist aktiv, bis du sie beendest." } ?? (quietTaskSlots > 0 ? "\(quietTaskSlots) Aufgaben-Erinnerungen ruhen gerade." : "")
            store?.taskReminderStatus = missing == 0 ? "Erinnerungen für \(admitted.count) offene Aufgaben aktiv. Sie wiederholen sich bis zum Erledigen." : "\(admitted.count) Aufgaben mit Erinnerung; \(missing) weitere passen nicht mehr. Wähle täglich statt vieler einzelner Wochentage oder schalte nicht benötigte Erinnerungen aus."
        } catch { store?.checkInReminderStatus = "Check-in-Erinnerungen unvollständig: " + error.localizedDescription; store?.taskReminderStatus = "Erinnerungen konnten nicht vollständig eingerichtet werden: " + error.localizedDescription; store?.routineReminderStatus = "Routine-Mitteilungen unvollständig: " + error.localizedDescription }
    }
    func cancel() {
        generation += 1; updateTask?.cancel()
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { Self.owns($0.identifier) }.map(\.identifier))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            guard let store = self.store else { return }
            if response.notification.request.content.categoryIdentifier == Self.checkInCategory {
                if let raw = response.notification.request.content.userInfo["checkInKind"] as? String, let kind = GuidedCheckInKind(rawValue: raw) { store.openDailyCheckIn(kind, slotID: (response.notification.request.content.userInfo["slotID"] as? String).flatMap(UUID.init(uuidString:))) }
                refresh(store)
                return
            }
            if response.notification.request.content.categoryIdentifier == Self.routineCategory {
                let info = response.notification.request.content.userInfo
                guard let raw = info["routineID"] as? String, let routineID = UUID(uuidString: raw),
                      let rawTime = info["timeID"] as? String, let timeID = UUID(uuidString: rawTime),
                      let due = info["due"] as? Double else { return }
                if response.actionIdentifier == "ROUTINE_LATER" {
                    let scheduledAt = Date(timeIntervalSince1970: info["scheduledAt"] as? Double ?? due)
                    if let occurrence = RoutinePlanner.occurrences(data: store.data, now: Date(), days: 1).first(where: { $0.routineID == routineID && $0.timeID == timeID && $0.scheduledAt == scheduledAt && $0.due <= Date() }) { store.snoozeRoutine(occurrence) }
                }
                store.notificationRoutineID = routineID
                refresh(store)
                return
            }
            if response.notification.request.content.categoryIdentifier == Self.assistedLivingCategory {
                store.openAssistedLiving(); return
            }
            if response.notification.request.identifier == Self.quietEndIdentifier {
                store.notificationQuietCenter = true; refresh(store); return
            }
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
