import Foundation

extension AppStore {
    func saveGuided(_ entry: GuidedCheckIn, complete: Bool) {
        var clean = entry, snapshot = data
        clean.date = min(clean.date, Date())
        clean.moodPercent = clean.moodPercent.map { max(0, min(100, $0)) }
        clean.mood = clean.mood.map { max(1, min(5, $0)) }
        clean.batteryPercent = clean.batteryPercent.map { max(0, min(100, $0)) }
        clean.stress = clean.stress.map { max(1, min(5, $0)) }
        clean.sensoryLoad = clean.sensoryLoad.map { max(1, min(5, $0)) }
        clean.sleepHours = clean.sleepHours.map { max(0, min(24, $0)) }
        guard GuidedCheckInMutation.apply(clean, complete: complete, to: &snapshot) else {
            lastSaveError = "Für diesen Check-in gibt es heute schon einen Eintrag. Öffne ihn zum Bearbeiten; deine neue Eingabe bleibt hier erhalten."
            return
        }
        data = snapshot
    }
    func offerCheckIn(for session: RunningTherapySession) {
        guard data.companionSettings.offerTherapyCheckIn,
              !data.guidedCheckIns.contains(where: { $0.sessionID == session.id }) else { return }
        var entry = GuidedCheckIn(kind: .therapy, sessionID: session.id)
        entry.summary = session.summary
        saveGuided(entry, complete: false)
        if lastSaveError == nil { pendingGuidedCheckIn = entry }
    }
    func saveRoutine(_ entry: DailyRoutine) {
        var clean = entry
        clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.title.isEmpty, !clean.times.isEmpty, clean.times.allSatisfy({ !$0.weekdays.isEmpty }) else { return }
        clean.retryMinutes = max(5, min(180, clean.retryMinutes))
        clean.escalationMinutes = max(5, min(60, clean.escalationMinutes))
        for index in clean.times.indices {
            clean.times[index].weekdays = Set(clean.times[index].weekdays).filter { (1...7).contains($0) }.sorted()
            clean.times[index].hour = max(0, min(23, clean.times[index].hour))
            clean.times[index].minute = max(0, min(59, clean.times[index].minute))
        }
        var snapshot = data
        if let previous = snapshot.routines.first(where: { $0.id == clean.id }) { RoutineHistoryMutation.preserveTitles(in: &snapshot, routine: previous) }
        snapshot.routines.removeAll { $0.id == clean.id }; snapshot.routines.append(clean)
        data = snapshot
    }
    func resolveRoutine(_ occurrence: RoutineOccurrence, outcome: RoutineOutcome, note: String = "") {
        guard data.routines.contains(where: { $0.id == occurrence.routineID }),
              !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions), occurrence.due <= Date() else { return }
        var snapshot = data
        let routine = snapshot.routines.first { $0.id == occurrence.routineID }!
        snapshot.routineCompletions.insert(RoutineCompletion(routineID: occurrence.routineID, timeID: occurrence.timeID, scheduledAt: occurrence.due, outcome: outcome, note: note, routineTitle: routine.title, timeTitle: routine.times.first { $0.id == occurrence.timeID }?.title), at: 0)
        snapshot.routineSnoozes.removeAll { $0.id == occurrence.id }
        data = snapshot
    }
    func snoozeRoutine(_ occurrence: RoutineOccurrence) {
        guard !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions) else { return }
        var snapshot = data
        snapshot.routineSnoozes.removeAll { $0.id == occurrence.id }
        snapshot.routineSnoozes.append(RoutineSnooze(id: occurrence.id, until: Date().addingTimeInterval(3600)))
        data = snapshot
    }
    func deleteRoutine(_ id: UUID) {
        var snapshot = data
        if let previous = snapshot.routines.first(where: { $0.id == id }) { RoutineHistoryMutation.preserveTitles(in: &snapshot, routine: previous) }
        snapshot.routines.removeAll { $0.id == id }
        snapshot.routineSnoozes.removeAll { $0.id.hasPrefix(id.uuidString + ".") }
        // History survives deletion and remains available in exports.
        data = snapshot
    }
    func correctRoutineLog(id: UUID, outcome: RoutineOutcome, note: String, reason: String) {
        var snapshot = data
        if RoutineHistoryMutation.correct(id: id, outcome: outcome, note: note, reason: reason, in: &snapshot) { data = snapshot }
    }
    func openDailyCheckIn(_ kind: GuidedCheckInKind, slotID: UUID? = nil) {
        guard DayCheckInPolicy.allows(kind: kind, id: slotID, settings: data.companionSettings),
              let slot = DayCheckInPolicy.slot(kind: kind, id: slotID, settings: data.companionSettings) else {
            checkInReminderStatus = "Dieser Check-in liegt außerhalb seines Zeitfensters oder ist deaktiviert."; return
        }
        let now = Date()
        pendingGuidedCheckIn = DayCheckInPolicy.reopen(DayCheckInPolicy.entry(slot, at: now), in: data)
    }
    func deleteGuided(_ id: UUID) {
        var snapshot = data
        snapshot.guidedCheckIns.removeAll { $0.id == id }
        snapshot.batteryPoints.removeAll { $0.checkInID == id }
        data = snapshot
    }
    func deleteBatteryPoint(_ id: UUID) {
        var snapshot = data
        snapshot.batteryPoints.removeAll { $0.id == id }
        for index in snapshot.guidedCheckIns.indices { snapshot.guidedCheckIns[index].energyPoints?.removeAll { $0.id == id } }
        data = snapshot
    }
    func consumeRoutineAlarmRoute() {
        if let route = UserDefaults.standard.string(forKey: "therapy.companion.open") {
            UserDefaults.standard.removeObject(forKey: "therapy.companion.open")
            let parts = route.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "therapy" { notificationTherapy = true }
            if parts.first == "energy" { openEnergyReview = true }
            if parts.first == "wellness" { notificationMood = true }
            if parts.count >= 2 {
                switch parts[0] {
                case "session": if let id = UUID(uuidString: parts[1]), data.currentSession?.id == id { notificationSession = true }
                case "routine": notificationRoutineID = UUID(uuidString: parts[1])
                case "task": if let id = UUID(uuidString: parts[1]), data.weeklyTasks.contains(where: { $0.id == id && !$0.completed }) { notificationTaskID = id }
                case "checkin": if let kind = GuidedCheckInKind(rawValue: parts[1]) { openDailyCheckIn(kind, slotID: parts.count > 2 ? UUID(uuidString: parts[2]) : nil) }
                default: break
                }
            }
        }
        if let raw = UserDefaults.standard.string(forKey: "therapy.routine.open"), let id = UUID(uuidString: raw) {
            notificationRoutineID = id
            UserDefaults.standard.removeObject(forKey: "therapy.routine.open")
        }
    }
}
