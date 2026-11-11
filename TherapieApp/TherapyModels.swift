import Foundation

extension WeeklyTask {
    mutating func toggleCompletion(at date: Date = Date()) {
        completed.toggle()
        completedAt = completed ? date : nil
    }
}

enum TherapyCategory: String, Codable, CaseIterable, Identifiable {
    case sensory = "Reize & Wahrnehmung", communication = "Kommunikation", emotions = "Gefühle & Regulation"
    case routines = "Routinen & Veränderungen", relationships = "Beziehungen", work = "Arbeit & Alltag"
    case boundaries = "Grenzen & Bedürfnisse", strengths = "Stärken & Interessen", rest = "Erholung"
    case planning = "Planung & Organisation", selfUnderstanding = "Selbstverständnis", other = "Sonstiges"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sensory: "ear"
        case .communication: "bubble.left.and.bubble.right"
        case .emotions: "heart"
        case .routines: "repeat"
        case .relationships: "person.2"
        case .work: "briefcase"
        case .boundaries: "hand.raised"
        case .strengths: "star"
        case .rest: "leaf"
        case .planning: "list.bullet.clipboard"
        case .selfUnderstanding: "person.crop.circle"
        case .other: "square.grid.2x2"
        }
    }
}

enum TherapyWorkStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Geplant", active = "In Bearbeitung", paused = "Pausiert", completed = "Abgeschlossen"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .planned: "circle.dashed"; case .active: "arrow.trianglehead.2.clockwise"; case .paused: "pause.circle"; case .completed: "checkmark.seal.fill" }
    }
}

struct TherapyFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var parentID: UUID?
    var symbol = "folder"
}

struct TherapyTopic: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var folderID: UUID?
    var category: TherapyCategory = .other
    var status: TherapyWorkStatus = .planned
    var isCurrent = false
    var priority = 2
    var description = ""
    var nextStep = ""
    var helps = ""
    var barriers = ""
}

struct TherapyGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var topicID: UUID?
    var status: TherapyWorkStatus = .planned
    var progress = 0
    var why = ""
    var measure = ""
    var smallStep = ""
    var support = ""
    var dueDate: Date?
    var priority: String?
}

enum NoteAuthor: String, CaseIterable, Identifiable {
    case me = "Ich", therapist = "Therapeutin / Therapeut", together = "Gemeinsam"
    var id: String { rawValue }
}

enum MaterialCategory: String, CaseIterable, Identifiable {
    case worksheet = "Arbeitsblatt", visualPlan = "Visueller Plan", exercise = "Übung", info = "Information"
    case communication = "Kommunikationshilfe", sensory = "Reiz-Strategie", routines = "Routine"
    case recording = "Sprachaufnahme", photo = "Foto", report = "Bericht", other = "Sonstiges"
    var id: String { rawValue }
}

struct SessionPhase: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var minutes = 5
    var colorIndex = 0
}

struct TherapySessionTemplate: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "Meine Therapiestunde"
    var phases = [
        SessionPhase(title: "Kaffee & Vorbereiten", minutes: 5, colorIndex: 0),
        SessionPhase(title: "AirTag besprechen", minutes: 5, colorIndex: 1),
        SessionPhase(title: "Wochenrückblick", minutes: 10, colorIndex: 2),
        SessionPhase(title: "Therapie & Themen", minutes: 40, colorIndex: 3)
    ]
    var note = ""
    var totalMinutes: Int { phases.reduce(0) { $0 + $1.minutes } }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...12).contains(phases.count)
            && phases.allSatisfy { (1...180).contains($0.minutes) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (1...240).contains(totalMinutes)
    }
}

struct RunningTherapySession: Codable, Equatable, Identifiable {
    var id = UUID()
    var templateID: UUID?
    var title = "Therapiezeit"
    var phases: [SessionPhase] = []
    var startedAt = Date()
    var accumulatedPause: TimeInterval = 0
    var pausedAt: Date?
    var endedAt: Date?
    var endedEarly = false
    var summary = ""
    var nextStep = ""
    /// Kompass 7: phases the person skipped (already done before the round, e.g. coffee). Optional, so every
    /// stored session without it still decodes.
    var skippedPhaseTitles: [String]?
    var skippedPhaseIDs: [UUID]?
    var totalSeconds: TimeInterval { TimeInterval(phases.reduce(0) { $0 + max(1, $1.minutes) } * 60) }
    var clockStart: Date { startedAt.addingTimeInterval(accumulatedPause) }
    var expectedEnd: Date { clockStart.addingTimeInterval(totalSeconds) }
    func elapsed(at now: Date = Date()) -> TimeInterval {
        max(0, min(totalSeconds, (endedAt ?? pausedAt ?? now).timeIntervalSince(startedAt) - accumulatedPause))
    }
    func remaining(at now: Date = Date()) -> TimeInterval { max(0, totalSeconds - elapsed(at: now)) }
    func phaseIndex(at now: Date = Date()) -> Int? {
        let elapsed = elapsed(at: now)
        guard elapsed < totalSeconds else { return nil }
        var boundary: TimeInterval = 0
        for (index, phase) in phases.enumerated() {
            boundary += TimeInterval(max(1, phase.minutes) * 60)
            if elapsed < boundary { return index }
        }
        return nil
    }
    mutating func pause(at date: Date = Date()) {
        guard pausedAt == nil, endedAt == nil, remaining(at: date) > 0 else { return }
        pausedAt = date
    }
    mutating func resume(at date: Date = Date()) {
        guard let pause = pausedAt, endedAt == nil else { return }
        accumulatedPause += max(0, date.timeIntervalSince(pause))
        pausedAt = nil
    }
    func isSkipped(_ phase: SessionPhase) -> Bool { skippedPhaseIDs?.contains(phase.id) ?? false }

    /// The phases a skip of `id` would leave out: the current phase is cut short, an upcoming one is removed.
    /// With `through` all phases from the current one up to (excluding) the target are skipped, i.e. a jump.
    func phasesSkipped(jumpingTo id: UUID, at now: Date = Date()) -> [SessionPhase] {
        guard endedAt == nil, let current = phaseIndex(at: now), let target = phases.firstIndex(where: { $0.id == id }), target > current else { return [] }
        return Array(phases[current..<target])
    }

    /// Whether `id` can be skipped right now. The last remaining phase cannot be skipped (that is "Beenden").
    func canSkip(_ id: UUID, at now: Date = Date()) -> Bool {
        guard endedAt == nil, let current = phaseIndex(at: now), let index = phases.firstIndex(where: { $0.id == id }) else { return false }
        if index == current { return index < phases.count - 1 }
        return index > current
    }

    /// Skips one phase. The current phase ends now (the clock jumps to the next phase, which then runs for its
    /// full time); an upcoming phase is taken out of the plan. Paused sessions stay paused.
    @discardableResult
    mutating func skipPhase(_ id: UUID, at now: Date = Date()) -> Bool {
        guard canSkip(id, at: now), let current = phaseIndex(at: now), let index = phases.firstIndex(where: { $0.id == id }) else { return false }
        let title = phases[index].title
        if index == current {
            let boundary = phases.prefix(index + 1).reduce(0.0) { $0 + TimeInterval(max(1, $1.minutes) * 60) }
            let jump = boundary - elapsed(at: now)
            guard jump > 0 else { return false }
            // A hundredth of a second past the boundary keeps the new phase current despite rounding.
            accumulatedPause -= jump + 0.01
            skippedPhaseIDs = (skippedPhaseIDs ?? []) + [id]
        } else {
            phases.remove(at: index)
        }
        skippedPhaseTitles = (skippedPhaseTitles ?? []) + [title]
        return true
    }

    /// Jumps straight to `id`: every phase from the current one up to it is skipped.
    @discardableResult
    mutating func jump(to id: UUID, at now: Date = Date()) -> Bool {
        let skipped = phasesSkipped(jumpingTo: id, at: now)
        guard !skipped.isEmpty else { return false }
        // Remove the upcoming phases first (back to front) so the current boundary stays where it is.
        for phase in skipped.dropFirst().reversed() { skipPhase(phase.id, at: now) }
        return skipPhase(skipped[0].id, at: now)
    }

    static func start(_ template: TherapySessionTemplate, at date: Date = Date()) -> RunningTherapySession {
        RunningTherapySession(templateID: template.id, title: template.title, phases: template.phases, startedAt: date)
    }
}

struct SessionPreferences: Codable, Equatable {
    var liveActivityEnabled = true
    var privateLiveActivity = true // Retained for older portable snapshots.
    var namedLiveActivity: Bool?
    var usesPrivateLiveActivity: Bool { namedLiveActivity == false }
    mutating func showLiveActivityNames(_ enabled: Bool) { namedLiveActivity = enabled; privateLiveActivity = !enabled }
    var notifyAtEnd = true
    var notifyAtPhases = false
}

enum TherapyHierarchy {
    static func descendants(of id: UUID, folders: [TherapyFolder]) -> Set<UUID> {
        var visited: Set<UUID> = [id]
        var pending = [id]
        while let parent = pending.popLast() {
            for folder in folders where folder.parentID == parent && !visited.contains(folder.id) {
                visited.insert(folder.id); pending.append(folder.id)
            }
        }
        visited.remove(id)
        return visited
    }
    static func path(for id: UUID?, folders: [TherapyFolder]) -> String {
        var names: [String] = [], seen: Set<UUID> = []
        var cursor = id
        while let key = cursor, seen.insert(key).inserted, let folder = folders.first(where: { $0.id == key }) {
            names.insert(folder.title, at: 0); cursor = folder.parentID
        }
        return names.isEmpty ? "Ohne Ordner" : names.joined(separator: " / ")
    }
    static func removeFolder(_ id: UUID, data: inout AppData) {
        let parent = data.therapyFolders.first(where: { $0.id == id })?.parentID
        data.therapyFolders.removeAll { $0.id == id }
        for i in data.therapyFolders.indices where data.therapyFolders[i].parentID == id { data.therapyFolders[i].parentID = parent }
        for i in data.therapyTopics.indices where data.therapyTopics[i].folderID == id { data.therapyTopics[i].folderID = parent }
        for i in data.notes.indices where data.notes[i].folderID == id { data.notes[i].folderID = parent }
        for i in data.media.indices where data.media[i].folderID == id { data.media[i].folderID = parent }
    }
    static func removeTopic(_ id: UUID, data: inout AppData) {
        data.therapyTopics.removeAll { $0.id == id }
        for i in data.therapyGoals.indices where data.therapyGoals[i].topicID == id { data.therapyGoals[i].topicID = nil }
        for i in data.notes.indices where data.notes[i].topicID == id { data.notes[i].topicID = nil }
        for i in data.media.indices where data.media[i].topicID == id { data.media[i].topicID = nil }
        for i in data.weeklyTasks.indices where data.weeklyTasks[i].topicID == id { data.weeklyTasks[i].topicID = nil }
    }
}
