// TB3 iOS — Session Preview Card (shows exercises for a session)

import SwiftUI

struct SessionPreviewCard: View {
    let session: ComputedSession
    let week: ComputedWeek
    var compact: Bool = false
    var onTap: (() -> Void)?

    @Environment(AppState.self) var appState

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.label)
                    .font(.headline)
                if onTap != nil {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.tb3Disabled)
                }
            }

            ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise)
            }

            // Sets/reps info
            let setsReps = formatWeekSetsReps()
            Text(setsReps)
                .font(.caption)
                .foregroundStyle(Color.tb3Muted)
        }
        .padding()
        .background(Color.tb3Card)
        .cornerRadius(12)
    }

    private func exerciseRow(_ exercise: ComputedExercise) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName)
                    .font(.subheadline)

                Spacer()

                if exercise.targetWeight > 0 {
                    Text("\(Int(exercise.targetWeight)) lb")
                        .font(.subheadline.monospaced().bold())
                        .foregroundColor(.tb3Accent)
                } else if exercise.liftName == LiftName.weightedPullUp.rawValue {
                    Text("BW")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                }
            }

            if !compact, !exercise.plates.isEmpty {
                let isBodyweight = exercise.liftName == LiftName.weightedPullUp.rawValue
                PlateDisplayView(
                    result: PlateResult(
                        plates: exercise.plates,
                        displayText: "",
                        achievable: true,
                        isBarOnly: false,
                        isBodyweightOnly: false,
                        isBelowBar: false
                    ),
                    isBodyweight: isBodyweight
                )
            }
        }
    }

    private func formatWeekSetsReps() -> String {
        let percentage = "\(week.percentage)%"

        let repsStr: String
        switch week.repsPerSet {
        case .single(let r):
            repsStr = "\(r)"
        case .array(let arr):
            repsStr = arr.map { "\($0)" }.joined(separator: ",")
        }

        if let minSets = week.minSets, let maxSets = week.maxSets, minSets != maxSets {
            return "\(minSets)-\(maxSets)X\(repsStr) @ \(percentage)"
        } else if let maxSets = week.maxSets {
            return "\(maxSets)X\(repsStr) @ \(percentage)"
        }
        return "@ \(percentage)"
    }
}
