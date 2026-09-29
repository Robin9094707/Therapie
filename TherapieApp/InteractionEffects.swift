import SwiftUI
import UIKit

@MainActor
final class TherapyEffects: ObservableObject {
    static let shared = TherapyEffects()
    @Published var celebration = 0
    private var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: "therapy.haptics") as? Bool ?? true }
    func light() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
    }
    func created() { light() }
    func deleted() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
    }
    func completed() {
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        celebration += 1
    }
    func failed() {
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }
    func changed(from old: AppData, to new: AppData) {
        let wasCompleted = Set(old.weeklyTasks.filter(\.completed).map(\.id))
        let taskCompleted = new.weeklyTasks.contains { task in
            task.completed && !wasCompleted.contains(task.id) && old.weeklyTasks.contains(where: { $0.id == task.id })
        }
        let goalCompleted = new.therapyGoals.contains { goal in
            goal.status == .completed && old.therapyGoals.contains { $0.id == goal.id && $0.status != .completed }
        }
        if taskCompleted || goalCompleted { completed(); return }
        func count(_ value: AppData) -> Int {
            value.weeklyTasks.count + value.notes.count + value.media.count + value.reflections.count
                + value.moodCheckIns.count + value.batteryPoints.count + value.weekReviews.count
                + value.therapyFolders.count + value.therapyTopics.count + value.therapyGoals.count
                + value.sessionTemplates.count + value.sessionHistory.count
        }
        if count(new) > count(old) { created() }
        else if count(new) < count(old) { deleted() }
    }
}

struct TherapyCelebrationOverlay: View {
    @ObservedObject private var effects = TherapyEffects.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("therapy.confetti") private var confetti = true
    @State private var began: Date?
    var body: some View {
        ZStack(alignment: .top) {
            if let began {
                if confetti && !reduceMotion {
                    SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        Canvas { drawing, size in
                            let t = context.date.timeIntervalSince(began)
                            for i in 0..<42 {
                                let seed = Double(i)
                                let origin = (0.12 + Double((i * 37) % 80) / 100) * size.width
                                let drift = sin(seed * 1.7) * 85 * t
                                let y = -30 + (100 + Double(i % 7) * 24) * t + 135 * t * t
                                var context = drawing
                                context.opacity = max(0, 1 - t / 1.8)
                                context.translateBy(x: origin + drift, y: y)
                                context.rotate(by: .radians(t * (seed.truncatingRemainder(dividingBy: 5) + 1)))
                                let colors: [Color] = [.indigo, .teal, .pink, .orange, .purple]
                                context.fill(Path(roundedRect: CGRect(x: -3, y: -5, width: 6, height: 10), cornerRadius: 2), with: .color(colors[i % colors.count]))
                            }
                        }
                    }.accessibilityHidden(true)
                }
                Label("Geschafft!", systemImage: "checkmark.seal.fill")
                    .font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: effects.celebration) { _, token in
            began = Date()
            UIAccessibility.post(notification: .announcement, argument: "Geschafft, als erledigt markiert.")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                if token == effects.celebration { began = nil }
            }
        }
    }
}
