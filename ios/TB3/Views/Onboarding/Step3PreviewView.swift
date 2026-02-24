// TB3 iOS — Onboarding Step 3: Preview First Week

import SwiftUI

struct Step3PreviewView: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Week 1 Preview")
                    .font(.title2.bold())

                if let schedule = vm.previewSchedule, let firstWeek = schedule.weeks.first {
                    Text("\(vm.selectedTemplate?.name ?? "Program") — \(firstWeek.label)")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)

                    ForEach(Array(firstWeek.sessions.enumerated()), id: \.offset) { _, session in
                        sessionPreviewCard(session, week: firstWeek)
                    }
                } else {
                    Text("No preview available. Enter lift maxes to see weights and plates.")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding()
        }
    }

    private func sessionPreviewCard(_ session: ComputedSession, week: ComputedWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.label)
                .font(.headline)

            ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise, week: week)
            }
        }
        .padding()
        .background(Color.tb3Card)
        .cornerRadius(12)
    }

    private func exerciseRow(_ exercise: ComputedExercise, week: ComputedWeek) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName)
                    .font(.subheadline.bold())

                let setsText = formatSetsReps(week: week)
                Text(setsText)
                    .font(.caption)
                    .foregroundStyle(Color.tb3Muted)
            }

            Spacer()

            if exercise.targetWeight > 0 {
                Text("\(Int(exercise.targetWeight)) lb")
                    .font(.subheadline.monospaced())
                    .foregroundColor(.tb3Accent)
            }
        }
    }

    private func formatSetsReps(week: ComputedWeek) -> String {
        let repsStr: String
        switch week.repsPerSet {
        case .single(let r): repsStr = "\(r)"
        case .array(let arr): repsStr = arr.map(String.init).joined(separator: "-")
        }

        if let minSets = week.minSets, let maxSets = week.maxSets, minSets != maxSets {
            return "\(minSets)-\(maxSets) sets \u{00D7} \(repsStr) reps @ \(week.percentage)%"
        } else {
            let sets = week.maxSets ?? week.setsRange.last ?? 0
            return "\(sets) sets \u{00D7} \(repsStr) reps @ \(week.percentage)%"
        }
    }
}
