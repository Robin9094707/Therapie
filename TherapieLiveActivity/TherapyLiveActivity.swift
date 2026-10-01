import SwiftUI
import WidgetKit
import ActivityKit

@main
struct TherapyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TherapyLiveActivityWidget()
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(context.state.paused ? "Therapiezeit · Pause" : "Therapiezeit", systemImage: context.state.paused ? "pause.circle" : "timer").font(.subheadline.weight(.semibold))
                    Spacer()
                    SessionActivityClock(state: context.state).font(.title3.monospacedDigit().bold())
                }
                SessionActivityPhaseHeading(state: context.state, isStale: context.isStale)
                if !context.state.paused && context.state.phases.count <= 8 { ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false).tint(.indigo).labelsHidden() }
                SessionActivityPhasePlan(state: context.state)
                if context.state.paused { Text("Zum Fortsetzen die App öffnen.").font(.caption) }
                else if context.state.phases.count <= 8 {
                    HStack { Text("Geplantes Ende"); Spacer(); Text(context.state.end, style: .time).monospacedDigit() }.font(.caption2)
                }
            }
            .padding(12)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.indigo)
            .widgetURL(URL(string: "therapie://session"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Therapiezeit", systemImage: "timer").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { SessionActivityClock(state: context.state).font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        SessionActivityPhaseHeading(state: context.state, isStale: context.isStale)
                        SessionActivityPhasePlan(state: context.state)
                        Link(context.state.paused ? "Pausiert · Stunde öffnen" : "Stunde öffnen", destination: URL(string: "therapie://session")!).font(.caption.bold())
                    }
                }
            } compactLeading: {
                if !context.isStale, let phase = context.state.currentPhase() {
                    Text(phase.title).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 88).accessibilityLabel(phase.title)
                } else { Image(systemName: context.state.paused ? "pause.fill" : "timer").foregroundStyle(.indigo) }
            } compactTrailing: {
                if !context.isStale, let phase = context.state.currentPhase() { SessionActivityPhaseClock(state: context.state, phase: phase).font(.caption.monospacedDigit()).frame(width: 52).accessibilityLabel("Abschnitt: verbleibende Zeit") }
                else { SessionActivityClock(state: context.state).font(.caption.monospacedDigit()).frame(width: 52) }
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer").foregroundStyle(.indigo)
            }
            .widgetURL(URL(string: "therapie://session"))
            .keylineTint(.indigo)
        }
    }
}
struct SessionActivityPhaseHeading: View {
    let state: TherapyActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        if !isStale, let phase = state.currentPhase() {
            HStack(spacing: 8) {
                Text((state.paused ? "Pausiert: " : "Jetzt: ") + phase.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                SessionActivityPhaseClock(state: state, phase: phase).font(.subheadline.monospacedDigit().bold()).frame(width: 54, alignment: .trailing).accessibilityLabel("Restzeit dieses Abschnitts")
            }
        } else if !state.phases.isEmpty {
            Text("Dein Zeitplan · Restzeit / Ende je Abschnitt").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct SessionActivityPhasePlan: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        let phases = Array(state.phases.prefix(12))
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(0..<((phases.count + 3) / 4), id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        if index < phases.count {
                            let phase = phases[index]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phase.title).font(.caption2.weight(.medium)).lineLimit(1)
                                if state.paused {
                                    let clock = state.referenceDate ?? state.end.addingTimeInterval(-Double(state.remaining))
                                    ProgressView(value: max(0, min(1, clock.timeIntervalSince(phase.start) / max(1, phase.end.timeIntervalSince(phase.start))))).tint(.teal).labelsHidden()
                                } else { ProgressView(timerInterval: phase.start...phase.end, countsDown: false).tint(.teal).labelsHidden() }
                                HStack(spacing: 2) { SessionActivityPhaseClock(state: state, phase: phase).frame(width: 36, alignment: .leading); Text("/"); Text(phase.end, style: .time) }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).accessibilityLabel("Restzeit und geplantes Ende von " + phase.title)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                    }
                }
            }
        }
    }
}
struct SessionActivityClock: View {
    let state: TherapyActivityAttributes.ContentState
    var body: some View {
        if state.paused { Text(String(format: "%d:%02d", state.remaining / 60, state.remaining % 60)).monospacedDigit() }
        else { Text(timerInterval: state.start...state.end, countsDown: true, showsHours: false).monospacedDigit() }
    }
}

struct SessionActivityPhaseClock: View {
    let state: TherapyActivityAttributes.ContentState
    let phase: TherapyActivityAttributes.Phase
    var body: some View {
        if state.paused {
            let clock = state.referenceDate ?? state.end.addingTimeInterval(-Double(state.remaining))
            let seconds = Int(ceil(max(0, min(phase.end.timeIntervalSince(phase.start), phase.end.timeIntervalSince(clock)))))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
        } else { Text(timerInterval: phase.start...phase.end, countsDown: true, showsHours: false).multilineTextAlignment(.trailing) }
    }
}
