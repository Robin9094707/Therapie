import Foundation

@main struct LivePhaseChecks {
    enum Failure: Error { case assertion(String) }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { count += 1; if try !value() { throw Failure.assertion(message) } }
    static func main() throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-01T08:00:00Z")!
        let template = TherapySessionTemplate()
        let session = RunningTherapySession.start(template, at: start)
        var cursor = session.clockStart
        let phases = session.phases.enumerated().map { index, phase in
            let end = cursor.addingTimeInterval(Double(phase.minutes) * 60); defer { cursor = end }
            return TherapyPhaseTimeline.Phase(title: TherapyPhaseTimeline.displayTitle(phase.title, index: index, privateMode: false), start: cursor, end: end)
        }
        var state = TherapyActivityAttributes.ContentState(start: session.clockStart, end: session.expectedEnd, paused: false, remaining: 3600, phases: phases, referenceDate: start)
        try expect(state.currentPhase(at: start)?.title == "Kaffee & Vorbereiten", "Live state starts with actual coffee name")
        try expect(state.currentPhase(at: start.addingTimeInterval(300))?.title == "AirTag besprechen", "Exact phase end moves to AirTag, not previous phase")
        try expect(state.currentPhase(at: start.addingTimeInterval(-1)) == nil, "No phase before the plan starts")
        try expect(state.currentPhase(at: session.expectedEnd) == nil, "No current phase after all planned time")
        state.paused = true; state.referenceDate = start.addingTimeInterval(330)
        try expect(state.currentPhase(at: start.addingTimeInterval(3000))?.title == "AirTag besprechen", "Paused live activity freezes the actual section")
        state.referenceDate = nil; state.remaining = 3270
        try expect(state.currentPhase(at: start.addingTimeInterval(3000))?.title == "AirTag besprechen", "Older paused content without reference date decodes safely")
        state.paused = false; state.referenceDate = start
        let roundtrip = try JSONDecoder().decode(TherapyActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        try expect(roundtrip == state, "Exact Live Activity content with names and reference round-trips")
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        object.removeValue(forKey: "referenceDate")
        let oldState = try JSONDecoder().decode(TherapyActivityAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(oldState.referenceDate == nil && oldState.phases == state.phases, "Previous Live Activity content remains supported")
        let crowded = (0..<12).map { index in TherapyPhaseTimeline.Phase(title: TherapyPhaseTimeline.displayTitle(String(repeating: "👨‍👩‍👧‍👦\"\\", count: 80), index: index, privateMode: false), start: start.addingTimeInterval(Double(index * 60)), end: start.addingTimeInterval(Double((index + 1) * 60))) }
        state.phases = crowded
        try expect(try JSONEncoder().encode(state).count < 3500, "Twelve Unicode-heavy named phases fit the actual content budget")
        try expect(crowded.count == 12 && crowded.allSatisfy { !$0.title.isEmpty }, "Payload keeps later phases instead of clearing the plan")
        try expect(TherapyPhaseTimeline.displayTitle("Kaffee\n &  Vorbereiten", index: 0, privateMode: false) == "Kaffee & Vorbereiten", "Titles normalize spacing for compact surfaces")
        try expect(TherapyPhaseTimeline.displayTitle("Kaffee", index: 0, privateMode: true) == "Abschnitt 1", "Explicit neutral-name mode remains available")
        var preferences = try JSONDecoder().decode(SessionPreferences.self, from: Data(#"{"liveActivityEnabled":true,"privateLiveActivity":true,"notifyAtEnd":true,"notifyAtPhases":false}"#.utf8))
        try expect(!preferences.usesPrivateLiveActivity && preferences.namedLiveActivity == nil, "Existing app installs default to requested actual names")
        preferences.showLiveActivityNames(false)
        let restored = try JSONDecoder().decode(SessionPreferences.self, from: JSONEncoder().encode(preferences))
        try expect(restored.usesPrivateLiveActivity && restored.privateLiveActivity, "Explicit neutral choice persists and preserves older snapshot compatibility")
        preferences.showLiveActivityNames(true)
        try expect(!preferences.usesPrivateLiveActivity && !preferences.privateLiveActivity, "Showing actual names updates compatible stored preference")
        print("Passed \(count) actual Live Activity state, phase boundary, pause, Unicode payload and portable setting checks.")
    }
}
