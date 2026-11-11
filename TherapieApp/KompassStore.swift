import Foundation
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted by intents that open the app (alarm stop, alarm button, shortcuts) after they stored their route.
    static let therapyIntentRoute = Notification.Name("therapy.intent-route")
}

enum TherapyIntentSignal {
    /// Intents run in the app process; posting lets the visible scene consume the route immediately instead of
    /// waiting for the next polling tick or a later scene change.
    static func post() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .therapyIntentRoute, object: nil) }
    }
}

// MARK: - Quiet mode actions

extension AppStore {
    func startQuiet(categories: [ReminderCategory] = [], until: Date?, note: String = "") {
        var snapshot = data
        QuietPolicy.pause(&snapshot.quietMode, categories: categories, until: until, note: note)
        data = snapshot
        TherapyEffects.shared.light()
    }
    func endQuiet(_ id: UUID) {
        var snapshot = data
        QuietPolicy.end(id, in: &snapshot.quietMode)
        data = snapshot
        TherapyEffects.shared.light()
    }
    func endAllQuiet() {
        var snapshot = data
        QuietPolicy.endAll(&snapshot.quietMode)
        data = snapshot
        TherapyEffects.shared.light()
    }
    func extendQuiet(_ id: UUID, hours: Double) {
        var snapshot = data
        QuietPolicy.extend(id, in: &snapshot.quietMode, by: hours * 3600)
        data = snapshot
    }
    func silence(_ item: PlannedReminder, wholeSource: Bool, until: Date?) {
        var snapshot = data
        QuietPolicy.silence(&snapshot.quietMode, key: wholeSource ? item.source : item.key, wholeSource: wholeSource, title: item.title, category: item.category, until: until)
        data = snapshot
        TherapyEffects.shared.light()
    }
    func restoreSilenced(_ id: UUID) {
        var snapshot = data
        QuietPolicy.restore(id, in: &snapshot.quietMode)
        data = snapshot
    }
    func setCategoryMuted(_ category: ReminderCategory, muted: Bool) {
        var snapshot = data
        snapshot.quietMode.mutedCategories.removeAll { $0 == category }
        if muted { snapshot.quietMode.mutedCategories.append(category) }
        data = snapshot
    }

    /// Called when the app comes back from an alarm or intent: redraw every screen from the current data and
    /// re-plan reminders, so the first frame after "Stopp" is never a stale preview.
    func refreshAfterIntent(force: Bool = false) {
        // Rebuilding every tab is only needed for the frame iOS captured while the app was not visible. While the
        // app is on screen a rebuild would reset navigation, so the route is just presented.
        if force || UIApplication.shared.applicationState != .active { surfaceRevision &+= 1 }
        TaskNotificationCoordinator.shared.refresh(self)
        TherapyWidgetBridge.refresh(self, force: true)
    }
}

// MARK: - Betreutes Wohnen actions

extension AppStore {
    func openAssistedLiving() {
        selectedTab = TherapyTab.assistedLiving
        notificationAssistedLiving = true
    }

    func saveAssistedLivingAppointment(_ appointment: AssistedLivingAppointment) {
        var clean = appointment
        clean.title = String(clean.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        if clean.title.isEmpty { clean.title = "BeWo-Termin" }
        clean.durationMinutes = max(5, min(600, clean.durationMinutes))
        clean.moodBefore = clean.moodBefore.map { max(1, min(5, $0)) }
        clean.moodAfter = clean.moodAfter.map { max(1, min(5, $0)) }
        clean.agreements = clean.agreements.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        clean.updatedAt = Date()
        var snapshot = data
        snapshot.assistedLivingAppointments.removeAll { $0.id == clean.id }
        snapshot.assistedLivingAppointments.append(clean)
        snapshot.assistedLivingAppointments.sort { $0.date > $1.date }
        // Topics picked for this visit move to "next" unless they were already discussed.
        for index in snapshot.assistedLivingTopics.indices where clean.topicIDs.contains(snapshot.assistedLivingTopics[index].id) && snapshot.assistedLivingTopics[index].status == .open {
            snapshot.assistedLivingTopics[index].status = .next
        }
        data = snapshot
    }

    func deleteAssistedLivingAppointment(_ id: UUID) {
        var snapshot = data
        snapshot.assistedLivingAppointments.removeAll { $0.id == id }
        for index in snapshot.assistedLivingTopics.indices where snapshot.assistedLivingTopics[index].appointmentID == id {
            snapshot.assistedLivingTopics[index].appointmentID = nil
        }
        data = snapshot
    }

    /// Stores a regular visit as an appointment (keeping its rhythm link) and returns it.
    @discardableResult
    func materialize(_ occurrence: AssistedLivingOccurrence) -> AssistedLivingAppointment {
        if let id = occurrence.appointmentID, let existing = data.assistedLivingAppointments.first(where: { $0.id == id }) { return existing }
        var appointment = AssistedLivingPlanner.materialize(occurrence, settings: data.assistedLivingSettings)
        appointment.topicIDs = data.assistedLivingTopics.filter { $0.status == .next }.map(\.id)
        saveAssistedLivingAppointment(appointment)
        return appointment
    }

    func skipRegularVisit(_ occurrence: AssistedLivingOccurrence) {
        guard occurrence.regularVisitID != nil, occurrence.appointmentID == nil else { return }
        var snapshot = data
        snapshot.assistedLivingSettings.skippedRegularDates.append(occurrence.date)
        snapshot.assistedLivingSettings.skippedRegularDates = snapshot.assistedLivingSettings.skippedRegularDates.filter { $0 > Date().addingTimeInterval(-60 * 86400) }
        data = snapshot
    }

    func saveAssistedLivingTopic(_ topic: AssistedLivingTopic) {
        var clean = topic
        clean.title = String(clean.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !clean.title.isEmpty else { return }
        clean.priority = max(1, min(3, clean.priority))
        if clean.status == .discussed && clean.discussedAt == nil { clean.discussedAt = Date() }
        clean.updatedAt = Date()
        var snapshot = data
        if let index = snapshot.assistedLivingTopics.firstIndex(where: { $0.id == clean.id }) { snapshot.assistedLivingTopics[index] = clean }
        else { snapshot.assistedLivingTopics.insert(clean, at: 0) }
        data = snapshot
    }

    func deleteAssistedLivingTopic(_ id: UUID) {
        var snapshot = data
        snapshot.assistedLivingTopics.removeAll { $0.id == id }
        for index in snapshot.assistedLivingAppointments.indices { snapshot.assistedLivingAppointments[index].topicIDs.removeAll { $0 == id } }
        data = snapshot
    }

    func setTopicStatus(_ id: UUID, _ status: AssistedLivingTopicStatus, appointmentID: UUID? = nil) {
        var snapshot = data
        if status == .discussed, let appointmentID {
            AssistedLivingPlanner.discuss(id, in: appointmentID, data: &snapshot)
        } else if let index = snapshot.assistedLivingTopics.firstIndex(where: { $0.id == id }) {
            snapshot.assistedLivingTopics[index].status = status
            if status == .discussed { snapshot.assistedLivingTopics[index].discussedAt = Date() }
            snapshot.assistedLivingTopics[index].updatedAt = Date()
        }
        data = snapshot
        TherapyEffects.shared.light()
    }

    func toggleAgreement(_ agreementID: UUID, in appointmentID: UUID) {
        guard let appointment = data.assistedLivingAppointments.firstIndex(where: { $0.id == appointmentID }),
              let agreement = data.assistedLivingAppointments[appointment].agreements.firstIndex(where: { $0.id == agreementID }) else { return }
        var snapshot = data
        snapshot.assistedLivingAppointments[appointment].agreements[agreement].done.toggle()
        snapshot.assistedLivingAppointments[appointment].agreements[agreement].doneAt = snapshot.assistedLivingAppointments[appointment].agreements[agreement].done ? Date() : nil
        data = snapshot
        TherapyEffects.shared.light()
    }

    func saveAssistedLivingGoal(_ goal: AssistedLivingGoal) {
        var clean = goal
        clean.title = String(clean.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !clean.title.isEmpty else { return }
        clean.steps = clean.steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !clean.steps.isEmpty && clean.steps.allSatisfy(\.done) && clean.completedAt == nil { clean.completedAt = Date() }
        if clean.steps.contains(where: { !$0.done }) { clean.completedAt = nil }
        var snapshot = data
        if let index = snapshot.assistedLivingGoals.firstIndex(where: { $0.id == clean.id }) { snapshot.assistedLivingGoals[index] = clean }
        else { snapshot.assistedLivingGoals.insert(clean, at: 0) }
        data = snapshot
    }

    func deleteAssistedLivingGoal(_ id: UUID) {
        data.assistedLivingGoals.removeAll { $0.id == id }
    }

    func toggleGoalStep(_ stepID: UUID, in goalID: UUID) {
        guard let goal = data.assistedLivingGoals.first(where: { $0.id == goalID }) else { return }
        var changed = goal
        guard let index = changed.steps.firstIndex(where: { $0.id == stepID }) else { return }
        changed.steps[index].done.toggle()
        changed.steps[index].doneAt = changed.steps[index].done ? Date() : nil
        saveAssistedLivingGoal(changed)
        TherapyEffects.shared.light()
    }
}
