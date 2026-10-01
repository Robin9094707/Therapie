import Foundation
#if os(iOS)
import ActivityKit
typealias TherapyActivityConformance = ActivityAttributes
#else
// Allows the exact portable ContentState to be verified by the macOS CI checks.
protocol TherapyActivityConformance {}
#endif

struct TherapyActivityAttributes: TherapyActivityConformance {
    typealias Phase = TherapyPhaseTimeline.Phase
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var paused: Bool
        var remaining: Int
        var phases: [Phase]
        var referenceDate: Date?
        func phaseRemaining(at date: Date = Date()) -> TimeInterval? {
            guard let phase = currentPhase(at: date) else { return nil }
            let clock = paused ? referenceDate ?? end.addingTimeInterval(-Double(remaining)) : date
            return max(0, phase.end.timeIntervalSince(clock))
        }
        func currentPhase(at date: Date = Date()) -> Phase? {
            let clock = paused ? referenceDate ?? end.addingTimeInterval(-Double(remaining)) : date
            return TherapyPhaseTimeline.activeIndex(in: phases, at: clock).map { phases[$0] }
        }
    }
    let sessionID: String
}
