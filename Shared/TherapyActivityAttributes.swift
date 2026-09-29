import Foundation
import ActivityKit

struct TherapyActivityAttributes: ActivityAttributes {
    struct Phase: Codable, Hashable {
        let title: String
        let start: Date
        let end: Date
    }
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var paused: Bool
        var remaining: Int
        var phases: [Phase]
    }
    let sessionID: String
}
