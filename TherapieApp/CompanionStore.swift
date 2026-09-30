import Foundation

extension AppStore {
    func saveGuided(_ entry: GuidedCheckIn, complete: Bool) {
        var clean = entry, snapshot = data
        clean.date = min(clean.date, Date())
        clean.mood = clean.mood.map { max(1, min(5, $0)) }
        clean.batteryPercent = clean.batteryPercent.map { max(0, min(100, $0)) }
        clean.stress = clean.stress.map { max(1, min(5, $0)) }
        clean.sensoryLoad = clean.sensoryLoad.map { max(1, min(5, $0)) }
        clean.sleepHours = clean.sleepHours.map { max(0, min(24, $0)) }
        GuidedCheckInMutation.apply(clean, complete: complete, to: &snapshot)
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
        snapshot.routines.removeAll { $0.id == clean.id }; snapshot.routines.append(clean)
        data = snapshot
    }
    func resolveRoutine(_ occurrence: RoutineOccurrence, outcome: RoutineOutcome, note: String = "") {
        guard data.routines.contains(where: { $0.id == occurrence.routineID }),
              !RoutinePlanner.resolved(occurrence, completions: data.routineCompletions), occurrence.due <= Date() else { return }
        var snapshot = data
        snapshot.routineCompletions.insert(RoutineCompletion(routineID: occurrence.routineID, timeID: occurrence.timeID, scheduledAt: occurrence.due, outcome: outcome, note: note), at: 0)
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
        snapshot.routines.removeAll { $0.id == id }
        snapshot.routineSnoozes.removeAll { $0.id.hasPrefix(id.uuidString + ".") }
        // History survives deletion and remains available in exports.
        data = snapshot
    }
    func consumeRoutineAlarmRoute() {
        if let raw = UserDefaults.standard.string(forKey: "therapy.routine.open"), let id = UUID(uuidString: raw) {
            notificationRoutineID = id
            UserDefaults.standard.removeObject(forKey: "therapy.routine.open")
        }
    }
}
