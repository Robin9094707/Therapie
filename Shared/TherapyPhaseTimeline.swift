import Foundation

/// Shared by the app and widget so pause and exact boundaries select the same phase.
enum TherapyPhaseTimeline {
    struct Phase: Codable, Hashable {
        let title: String
        let start: Date
        let end: Date
    }
    static func activeIndex(in phases: [Phase], at date: Date) -> Int? {
        phases.firstIndex { $0.start <= date && date < $0.end }
    }
    /// Session name for compact surfaces; neutral mode hides it.
    static func sessionTitle(_ title: String, privateMode: Bool) -> String? {
        guard !privateMode else { return nil }
        let clean = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        return clean.count > 32 ? String(clean.prefix(31)) + "…" : clean
    }
    static func displayTitle(_ title: String, index: Int, privateMode: Bool) -> String {
        guard !privateMode else { return "Abschnitt \(index + 1)" }
        let clean = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !clean.isEmpty else { return "Abschnitt \(index + 1)" }
        var result = ""
        for character in clean.prefix(40) {
            let next = result + String(character)
            guard next.utf8.count <= 76 else { break }
            result = next
        }
        if result.count < clean.count { result += "…" }
        return result.isEmpty ? "Abschnitt \(index + 1)" : result
    }
}
