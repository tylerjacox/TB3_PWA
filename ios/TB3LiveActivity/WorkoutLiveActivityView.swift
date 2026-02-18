// TB3 iOS — Live Activity Views (lock screen + Dynamic Island)

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isBodyweight {
                        Text("BW")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(context.state.weight) lb")
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let startedAt = context.state.timerStartedAt {
                        let startDate = Date(timeIntervalSince1970: startedAt / 1000)
                        Text(startDate, style: .timer)
                            .font(.title.monospacedDigit().bold())
                            .foregroundStyle(timerColor(context.state))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Set \(context.state.completedSets + 1) / \(context.state.totalSets)")
                            .font(.subheadline.monospacedDigit().bold())

                        Spacer()

                        if let label = phaseLabel(context.state) {
                            Text(label)
                                .font(.caption.bold())
                                .foregroundStyle(timerColor(context.state))
                        }
                    }
                }
            } compactLeading: {
                if let startedAt = context.state.timerStartedAt {
                    let startDate = Date(timeIntervalSince1970: startedAt / 1000)
                    Label {
                        Text(startDate, style: .timer)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.body)
                    .foregroundStyle(timerColor(context.state))
                    .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(.body)
                }
            } compactTrailing: {
                Text("\(context.state.completedSets + 1)/\(context.state.totalSets)")
                    .font(.body.monospacedDigit().bold())
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .font(.caption)
            }
        }
    }

    private func timerColor(_ state: WorkoutActivityAttributes.ContentState) -> Color {
        switch state.timerPhase {
        case "rest": return state.isOvertime ? .red : .orange
        case "exercise": return .green
        default: return .primary
        }
    }

    private func phaseLabel(_ state: WorkoutActivityAttributes.ContentState) -> String? {
        switch state.timerPhase {
        case "rest": return state.isOvertime ? "REST (OVERTIME)" : "REST"
        case "exercise": return "EXERCISE"
        default: return nil
        }
    }
}

// MARK: - Lock Screen View

struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Top: Exercise name + weight
            HStack {
                Text(context.state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if context.state.isBodyweight {
                    Text("BW")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(context.state.weight) lb")
                        .font(.headline.monospacedDigit())
                }
            }

            // Middle: Set progress + timer
            HStack {
                Text("Set \(context.state.completedSets + 1) / \(context.state.totalSets)")
                    .font(.title2.monospacedDigit().bold())

                Spacer()

                if let startedAt = context.state.timerStartedAt {
                    let startDate = Date(timeIntervalSince1970: startedAt / 1000)
                    Text(startDate, style: .timer)
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(timerColor)
                }
            }

            // Bottom: Phase label + exercise position
            HStack {
                if let label = phaseLabel {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(timerColor)
                }

                Spacer()

                Text("Exercise \(context.state.exerciseIndex + 1) of \(context.attributes.totalExercises)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var timerColor: Color {
        switch context.state.timerPhase {
        case "rest": return context.state.isOvertime ? .red : .orange
        case "exercise": return .green
        default: return .primary
        }
    }

    private var phaseLabel: String? {
        switch context.state.timerPhase {
        case "rest": return context.state.isOvertime ? "REST (OVERTIME)" : "REST"
        case "exercise": return "EXERCISE"
        default: return nil
        }
    }
}
