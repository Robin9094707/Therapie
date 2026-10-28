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
        /// Final lock-screen state after the planned time; the island itself is removed by iOS.
        var finished: Bool? = nil
        /// Session name for the Lock Screen header; nil in neutral mode and for older content.
        var title: String? = nil
        /// True when the planned time has passed, even if the app could not end the activity yet.
        func isOver(at date: Date = Date()) -> Bool { finished == true || (!paused && date >= end) }
        /// Position of the current phase ("2 von 4") at render time.
        func phasePosition(at date: Date = Date()) -> (index: Int, count: Int)? {
            let clock = paused ? referenceDate ?? end.addingTimeInterval(-Double(remaining)) : date
            return TherapyPhaseTimeline.activeIndex(in: phases, at: clock).map { (index: $0, count: phases.count) }
        }
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
