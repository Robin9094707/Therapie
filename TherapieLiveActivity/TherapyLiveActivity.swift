import SwiftUI
import WidgetKit
import ActivityKit

@main
struct TherapyLiveActivityBundle: WidgetBundle {
    var body: some Widget { TherapyLiveActivityWidget() }
}

struct TherapyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TherapyActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.state.paused ? "Therapiezeit · Pause" : "Therapiezeit", systemImage: context.state.paused ? "pause.circle" : "timer").font(.headline)
                    Spacer()
                    SessionActivityClock(state: context.state).font(.title2.monospacedDigit().bold())
                }
                if !context.state.paused {
                    ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false).tint(.indigo)
                    if !context.state.phases.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(context.state.phases.prefix(4).enumerated()), id: \.offset) { _, phase in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(phase.title).font(.caption2).lineLimit(1)
                                    ProgressView(timerInterval: phase.start...phase.end, countsDown: false).tint(.teal).labelsHidden()
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    HStack {
                        Text("Geplantes Ende").font(.caption)
                        Spacer()
                        Text(context.state.end, style: .time).font(.caption.monospacedDigit())
                    }
                } else { Text("Zum Fortsetzen die App öffnen.").font(.caption) }
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.indigo)
            .widgetURL(URL(string: "therapie://session"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Therapiezeit", systemImage: "timer").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { SessionActivityClock(state: context.state).font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if context.state.paused { Text("Pausiert · in der App fortsetzen").font(.caption) }
                        else {
                            ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false).tint(.indigo)
                            HStack { Text("Geplantes Ende"); Spacer(); Text(context.state.end, style: .time) }.font(.caption)
                        }
                        Link("Stunde öffnen", destination: URL(string: "therapie://session")!).font(.caption.bold())
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer").foregroundStyle(.indigo)
            } compactTrailing: {
                SessionActivityClock(state: context.state).font(.caption.monospacedDigit()).frame(width: 52)
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer").foregroundStyle(.indigo)
            }
            .widgetURL(URL(string: "therapie://session"))
            .keylineTint(.indigo)
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
