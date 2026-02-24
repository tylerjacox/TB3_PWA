// TB3 iOS — Workout Share Card (rendered to image for sharing)
// All colors hardcoded — ImageRenderer doesn't propagate SwiftUI environment.

import SwiftUI

struct WorkoutShareCard: View {
    let sessionLog: SyncSessionLog
    let barbellWeight: Double
    let plateInventoryBarbell: PlateInventory
    let plateInventoryBelt: PlateInventory

    // Hardcoded TB3 theme colors (must match Color extensions)
    private let bgColor = Color(red: 0, green: 0, blue: 0)
    private let cardColor = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    private let accentColor = Color(red: 1.0, green: 0.584, blue: 0) // #FF9500
    private let successColor = Color(red: 0.196, green: 0.843, blue: 0.294) // #32D74B
    private let mutedColor = Color(white: 0.55)
    private let disabledColor = Color(white: 0.35)

    var body: some View {
        VStack(spacing: 16) {
            // Brand header
            HStack {
                Text("TB3")
                    .font(.caption.bold())
                    .foregroundStyle(mutedColor)
                Spacer()
            }

            // Celebration header
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(successColor)

                Text("Workout Complete")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                statusBadge
            }

            // Session info
            VStack(spacing: 8) {
                Text(templateDisplayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Week \(sessionLog.week) \u{2022} Session \(sessionLog.sessionNumber)")
                    .font(.subheadline)
                    .foregroundStyle(mutedColor)

                HStack(spacing: 16) {
                    Label(durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(mutedColor)

                    if let temp = sessionLog.temperatureF {
                        Label("\(Int(temp))\u{00B0}F", systemImage: "thermometer.medium")
                            .font(.caption)
                            .foregroundStyle(mutedColor)
                    }
                }

                if totalVolume > 0 {
                    VStack(spacing: 2) {
                        Text("Total Volume")
                            .font(.caption)
                            .foregroundStyle(mutedColor)
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass")
                                .font(.subheadline)
                            Text("\(totalVolume.formatted()) lb")
                                .font(.title3.bold())
                        }
                        .foregroundStyle(accentColor)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(cardColor)
            .cornerRadius(12)

            // Exercise cards
            VStack(spacing: 8) {
                ForEach(Array(sessionLog.exercises.enumerated()), id: \.offset) { _, exercise in
                    exerciseRow(exercise)
                }
            }

            // Footer
            Text("tb3app")
                .font(.caption2)
                .foregroundStyle(disabledColor)
                .padding(.top, 4)
        }
        .padding(20)
        .background(bgColor)
    }

    // MARK: - Components

    private var statusBadge: some View {
        let isCompleted = sessionLog.status == "completed"
        return Text(isCompleted ? "COMPLETED" : "PARTIAL")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(isCompleted ? successColor.opacity(0.2) : accentColor.opacity(0.2))
            .foregroundStyle(isCompleted ? successColor : accentColor)
            .cornerRadius(6)
    }

    private func exerciseRow(_ exercise: SyncExerciseLog) -> some View {
        let completedSets = exercise.sets.filter(\.completed).count
        let totalSets = exercise.sets.count
        let allDone = completedSets == totalSets
        let liftName = LiftName(rawValue: exercise.liftName)
        let isBodyweight = liftName?.isBodyweight ?? false
        let plateResult = plateResult(for: exercise, isBodyweight: isBodyweight)
        let totalReps = exercise.sets.filter(\.completed).reduce(0) { $0 + $1.actualReps }
        let exerciseVolume = Int(exercise.targetWeight) * totalReps

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(liftName?.displayName ?? exercise.liftName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Spacer()

                if exercise.targetWeight > 0 {
                    Text("\(Int(exercise.targetWeight)) lb")
                        .font(.subheadline.bold())
                        .foregroundStyle(accentColor)
                }
            }

            HStack {
                Text("\(completedSets)/\(totalSets) sets")
                    .font(.caption.bold())
                    .foregroundStyle(allDone ? successColor : accentColor)

                if exerciseVolume > 0 {
                    Text("\u{2022}")
                        .foregroundStyle(disabledColor)
                    Text("\(exerciseVolume.formatted()) lb")
                        .foregroundStyle(mutedColor)
                }

                Spacer()
            }
            .font(.caption)

            if !exercise.sets.isEmpty {
                let repsText = exercise.sets.enumerated().map { i, set in
                    "S\(i + 1): \(set.actualReps)"
                }.joined(separator: "  \u{2022}  ")

                Text(repsText)
                    .font(.caption2)
                    .foregroundStyle(mutedColor)
            }

            // Plate visualizer
            if let plateResult {
                PlateDisplayView(
                    result: plateResult,
                    isBodyweight: isBodyweight,
                    scale: 1.0
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardColor)
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private var templateDisplayName: String {
        Templates.get(id: sessionLog.templateId)?.name ?? sessionLog.templateId
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var durationText: String {
        guard let start = Date.fromISO8601(sessionLog.startedAt),
              let end = Date.fromISO8601(sessionLog.completedAt) else { return "--" }
        let seconds = Int(end.timeIntervalSince(start))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }

    private var totalVolume: Int {
        sessionLog.exercises.reduce(0) { total, exercise in
            let completedReps = exercise.sets.filter(\.completed).reduce(0) { $0 + $1.actualReps }
            return total + Int(exercise.targetWeight) * completedReps
        }
    }

    private func plateResult(for exercise: SyncExerciseLog, isBodyweight: Bool) -> PlateResult? {
        guard exercise.targetWeight > 0 else { return nil }
        if isBodyweight {
            return PlateCalculator.calculateBeltPlates(
                totalWeight: exercise.targetWeight,
                inventory: plateInventoryBelt
            )
        } else {
            return PlateCalculator.calculateBarbellPlates(
                totalWeight: exercise.targetWeight,
                barbellWeight: barbellWeight,
                inventory: plateInventoryBarbell
            )
        }
    }
}
