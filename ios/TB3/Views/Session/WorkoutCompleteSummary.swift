// TB3 iOS — Workout Completion Summary

import SwiftUI

struct WorkoutCompleteSummary: View {
    @Environment(AppState.self) var appState

    let sessionLog: SyncSessionLog
    let onDismiss: () -> Void

    @State private var showCheckmark = false
    @State private var showContent = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with share button
            HStack {
                Spacer()
                Button {
                    shareWorkout()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.tb3Press)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    celebrationHeader
                        .padding(.top, 16)

                    if showContent {
                        sessionInfoCard
                        exerciseCards
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }

            bottomBar
        }
        .background(Color.tb3Background)
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(items: [shareImage])
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showCheckmark = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showContent = true
                }
            }
        }
    }

    // MARK: - Celebration Header

    private var celebrationHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.tb3Success)
                .scaleEffect(showCheckmark ? 1.0 : 0.3)
                .opacity(showCheckmark ? 1 : 0)

            Text("Workout Complete")
                .font(.system(size: 28, weight: .bold))

            statusBadge
        }
    }

    private var statusBadge: some View {
        let isCompleted = sessionLog.status == "completed"
        return Text(isCompleted ? "COMPLETED" : "PARTIAL")
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isCompleted ? Color.tb3Success.opacity(0.2) : Color.tb3Accent.opacity(0.2))
            .foregroundStyle(isCompleted ? Color.tb3Success : Color.tb3Accent)
            .cornerRadius(8)
    }

    // MARK: - Session Info Card

    private var sessionInfoCard: some View {
        VStack(spacing: 12) {
            Text(templateDisplayName)
                .font(.title3.bold())

            Text("Week \(sessionLog.week) \u{2022} Session \(sessionLog.sessionNumber)")
                .font(.subheadline)
                .foregroundStyle(Color.tb3Muted)

            HStack(spacing: 16) {
                Label(durationText, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(Color.tb3Muted)

                if let temp = sessionLog.temperatureF {
                    Label("\(Int(temp))\u{00B0}F", systemImage: "thermometer.medium")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                }
            }

            if totalVolume > 0 {
                VStack(spacing: 2) {
                    Text("Total Volume")
                        .font(.caption)
                        .foregroundStyle(Color.tb3Muted)
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass")
                            .font(.subheadline)
                        Text("\(totalVolume.formatted()) lb")
                            .font(.title3.bold())
                    }
                    .foregroundStyle(Color.tb3Accent)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.tb3Card)
        .cornerRadius(12)
    }

    // MARK: - Exercise Cards

    private var exerciseCards: some View {
        VStack(spacing: 12) {
            ForEach(Array(sessionLog.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseCard(exercise)
            }
        }
    }

    private func exerciseCard(_ exercise: SyncExerciseLog) -> some View {
        let completedSets = exercise.sets.filter(\.completed).count
        let totalSets = exercise.sets.count
        let allDone = completedSets == totalSets
        let liftName = LiftName(rawValue: exercise.liftName)
        let isBodyweight = liftName?.isBodyweight ?? false
        let plateResult = plateResult(for: exercise, isBodyweight: isBodyweight)
        let totalReps = exercise.sets.filter(\.completed).reduce(0) { $0 + $1.actualReps }
        let exerciseVolume = Int(exercise.targetWeight) * totalReps

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(liftName?.displayName ?? exercise.liftName)
                    .font(.headline)

                Spacer()

                if exercise.targetWeight > 0 {
                    Text("\(Int(exercise.targetWeight)) lb")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.tb3Accent)
                }
            }

            HStack {
                Text("\(completedSets)/\(totalSets) sets")
                    .font(.subheadline.bold())
                    .foregroundStyle(allDone ? Color.tb3Success : Color.tb3Accent)

                if exerciseVolume > 0 {
                    Text("\u{2022}")
                        .foregroundStyle(Color.tb3Disabled)
                    Text("\(exerciseVolume.formatted()) lb volume")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                }

                if let duration = formatExerciseDuration(exercise.durationSeconds) {
                    Spacer()
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(Color.tb3Disabled)
                }
            }

            if !exercise.sets.isEmpty {
                let repsText = exercise.sets.enumerated().map { i, set in
                    "Set \(i + 1): \(set.actualReps) reps"
                }.joined(separator: "  \u{2022}  ")

                Text(repsText)
                    .font(.caption)
                    .foregroundStyle(Color.tb3Muted)
            }

            // Plate visualizer
            if let plateResult {
                PlateDisplayView(
                    result: plateResult,
                    isBodyweight: isBodyweight,
                    scale: 1.2
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.tb3Card)
        .cornerRadius(12)
    }

    // MARK: - Done Button

    private var bottomBar: some View {
        Button {
            onDismiss()
        } label: {
            Text("Done")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Color.beginSetGreen)
                .cornerRadius(12)
        }
        .buttonStyle(.tb3Press)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            Color.tb3Background
                .shadow(color: .black.opacity(0.3), radius: 8, y: -4)
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    // MARK: - Helpers

    private var templateDisplayName: String {
        sessionLog.templateId
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
        let profile = appState.profile
        if isBodyweight {
            return PlateCalculator.calculateBeltPlates(
                totalWeight: exercise.targetWeight,
                inventory: profile.plateInventoryBelt
            )
        } else {
            return PlateCalculator.calculateBarbellPlates(
                totalWeight: exercise.targetWeight,
                barbellWeight: profile.barbellWeight,
                inventory: profile.plateInventoryBarbell
            )
        }
    }

    private func shareWorkout() {
        let profile = appState.profile
        let card = WorkoutShareCard(
            sessionLog: sessionLog,
            barbellWeight: profile.barbellWeight,
            plateInventoryBarbell: profile.plateInventoryBarbell,
            plateInventoryBelt: profile.plateInventoryBelt
        )
        let renderer = ImageRenderer(content: card.frame(width: 390))
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }

    private func formatExerciseDuration(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }
}
