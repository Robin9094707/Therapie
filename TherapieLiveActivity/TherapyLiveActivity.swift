import SwiftUI
import WidgetKit
import ActivityKit

@main
struct TherapyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TherapyLiveActivityWidget()
        TherapyEmergencyQuickWidget()
        TherapyDirectOverviewWidget()
        TherapyDirectShowerWidget()
        TherapyOverviewWidget()
        TherapyAppointmentWidget()
        TherapyRoutinesWidget()
        TherapyRemindersWidget()
        TherapySessionWidget()
    }
}

struct TherapyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TherapyActivityAttributes.self) { context in
            SessionLockScreenView(state: context.state)
                .padding(16)
                .activitySystemActionForegroundColor(.teal)
                .widgetURL(URL(string: "therapie://session"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionRing(state: context.state, size: 48)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        SessionActivityClock(state: context.state)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100, alignment: .trailing)
                        Text(context.state.isOver() ? "geschafft" : context.state.paused ? "pausiert" : "verbleibend")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        SessionCaption(state: context.state).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        SessionPhaseTitle(state: context.state).font(.headline).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !context.state.isOver() { SessionPhaseStrip(state: context.state) }
                        HStack {
                            SessionEndLabel(state: context.state)
                            Spacer()
                            Link(destination: URL(string: "therapie://session")!) {
                                Label("Öffnen", systemImage: "arrow.up.forward.app.fill").font(.caption.weight(.semibold))
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                SessionRing(state: context.state, size: 22)
            } compactTrailing: {
                SessionActivityClock(state: context.state)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48, alignment: .trailing)
                    .foregroundStyle(.teal)
            } minimal: {
                SessionRing(state: context.state, size: 22)
            }
            .widgetURL(URL(string: "therapie://session"))
            .keylineTint(.teal)
        }
    }
}

/// Lock Screen layout. Clocks and bars are timer-driven; names and the "time is up" state are evaluated when iOS
/// draws the activity, which it does again at every stale date (the next phase boundary) without the app.
struct SessionLockScreenView: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        let over = state.isOver()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SessionRing(state: state, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    SessionCaption(state: state).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    SessionPhaseTitle(state: state).font(.headline).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !over {
                    SessionActivityClock(state: state)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
            if over {
                Label("Gut gemacht. Öffne die App, um in Ruhe festzuhalten, was dir wichtig war.", systemImage: "heart.text.square.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                SessionPhaseStrip(state: state)
                HStack {
                    SessionEndLabel(state: state)
                    Spacer()
                    SessionNextLabel(state: state)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SessionRing: View {
    let state: TherapyActivityAttributes.ContentState
    var size: CGFloat
    var body: some View {
        ZStack {
            if state.isOver() {
                Image(systemName: "checkmark.circle.fill").resizable().scaledToFit().foregroundStyle(.green)
            } else {
                if state.paused {
                    ProgressView(value: pausedProgress).progressViewStyle(.circular).labelsHidden()
                } else {
                    ProgressView(timerInterval: state.start...state.end, countsDown: false).progressViewStyle(.circular).labelsHidden()
                }
                Image(systemName: state.paused ? "pause.fill" : "leaf.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.teal)
            }
        }
        .tint(.teal)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private var pausedProgress: Double {
        let total = max(1, state.end.timeIntervalSince(state.start))
        return max(0, min(1, (total - Double(state.remaining)) / total))
    }
}

/// "Therapiestunde · Abschnitt 2 von 4 · bis 15:20" – the end time keeps the line honest if iOS has not redrawn yet.
struct SessionCaption: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        let name = state.title ?? "Therapiestunde"
        if state.isOver() { Text(name + " · beendet") }
        else if state.paused { Text(name + " · Pause") }
        else if let position = state.phasePosition(), let phase = state.currentPhase(), position.count > 1 {
            Text("Abschnitt \(position.index + 1) von \(position.count) · bis \(phase.end, style: .time)")
        } else { Text(name) }
    }
}

/// Phase name chosen when iOS draws the activity. The app sets the stale date to the next phase boundary, so iOS
/// redraws right there and the name follows the plan even while the app is suspended.
struct SessionPhaseTitle: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        if state.isOver() { Text("Geschafft") }
        else if let phase = state.currentPhase() { Text((state.paused ? "Pausiert · " : "") + phase.title) }
        else { Text(state.paused ? "Pausiert" : (state.title ?? "Deine Zeit läuft")) }
    }
}

struct SessionPhaseStrip: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        let phases = Array(state.phases.prefix(8))
        let current = state.phasePosition()?.index
        if phases.isEmpty {
            bar(start: state.start, end: state.end)
        } else {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                    VStack(alignment: .leading, spacing: 4) {
                        bar(start: phase.start, end: phase.end)
                        if phases.count <= 4 {
                            Text(phase.title).font(.caption2.weight(index == current ? .bold : .medium))
                                .foregroundStyle(index == current ? Color.primary : Color.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    @ViewBuilder private func bar(start: Date, end: Date) -> some View {
        if state.paused {
            let clock = state.referenceDate ?? state.end.addingTimeInterval(-Double(state.remaining))
            ProgressView(value: max(0, min(1, clock.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))).labelsHidden().tint(.teal)
        } else {
            ProgressView(timerInterval: start...end, countsDown: false).labelsHidden().tint(.teal)
        }
    }
}

struct SessionEndLabel: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        if state.isOver() { Label("Zeit ist um", systemImage: "checkmark.seal.fill") }
        else if state.paused { Label("Zum Fortsetzen die App öffnen", systemImage: "hand.tap.fill") }
        else { Label("Ende \(state.end, style: .time)", systemImage: "flag.checkered") }
    }
}

struct SessionNextLabel: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        if !state.paused, let position = state.phasePosition(), position.index + 1 < state.phases.count {
            Label("Danach: " + state.phases[position.index + 1].title, systemImage: "arrow.turn.down.right").lineLimit(1)
        }
    }
}

struct SessionActivityClock: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        if state.isOver() { Text("0:00").monospacedDigit() }
        else if state.paused { Text(String(format: "%d:%02d", state.remaining / 60, state.remaining % 60)).monospacedDigit() }
        else { Text(timerInterval: state.start...state.end, countsDown: true, showsHours: false).monospacedDigit() }
    }
}
