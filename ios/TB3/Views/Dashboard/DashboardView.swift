// TB3 iOS — Dashboard View

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) var appState
    var onNavigateToProgram: () -> Void = {}
    var onNavigateToProfile: () -> Void = {}
    var onStartWorkout: (([ComputedExercise], ComputedWeek, SyncActiveProgram) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Dashboard")

            ScrollView {
                VStack(spacing: 20) {
                    switch trainingStatus {
                    case .noProgram:
                        emptyState
                    case .workoutDay:
                        activeState
                    case .restDay(let resumeDate, let reason):
                        restDayState(resumeDate: resumeDate, reason: reason)
                    case .deloadWeek(let endsDate):
                        deloadState(endsDate: endsDate)
                    case .programComplete:
                        completedState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)

            Image(systemName: "dumbbell")
                .font(.system(size: 60))
                .foregroundStyle(Color.tb3Muted)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            Text("No Active Program")
                .font(.title2.bold())

            Text("Choose a training template to get started.")
                .font(.subheadline)
                .foregroundStyle(Color.tb3Muted)

            Button("Choose a Template") {
                onNavigateToProgram()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Program Complete

    private var completedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tb3Accent)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            Text("Program Complete!")
                .font(.title2.bold())

            Text("Great work! Retest your maxes and start a new cycle.")
                .font(.subheadline)
                .foregroundStyle(Color.tb3Muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Retest 1RM") {
                    onNavigateToProfile()
                }
                .buttonStyle(.bordered)

                Button("New Template") {
                    onNavigateToProgram()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Active Program

    @ViewBuilder
    private var programHeader: some View {
        if let program = appState.activeProgram,
           let template = Templates.get(id: program.templateId) {
            VStack(spacing: 8) {
                Text(template.name)
                    .font(.title2.bold())

                Text("Week \(min(program.currentWeek, template.durationWeeks)) of \(template.durationWeeks)")
                    .font(.subheadline)
                    .foregroundStyle(Color.tb3Muted)

                ProgressView(value: progressPercent)
                    .tint(Color.tb3Accent)
                    .accessibilityLabel("Program progress, \(Int(progressPercent * 100))% complete")
            }
        }
    }

    private var activeState: some View {
        VStack(spacing: 16) {
            programHeader

            // Return to workout banner
            if appState.activeSession != nil {
                returnToWorkoutBanner
            }

            // Next session preview
            if let (session, week) = currentSessionData {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Next Session")
                        .font(.headline)

                    SessionPreviewCard(session: session, week: week)
                }

                Button {
                    if let program = appState.activeProgram {
                        if appState.activeSession != nil {
                            // Resume existing session
                            appState.isSessionPresented = true
                        } else {
                            onStartWorkout?(session.exercises, week, program)
                        }
                    }
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Double tap to begin workout session")
            }

        }
    }

    private var returnToWorkoutBanner: some View {
        Button {
            appState.isSessionPresented = true
        } label: {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                Text("Workout in Progress")
                    .fontWeight(.semibold)
                Spacer()
                Text("Return")
                    .font(.subheadline)
                Image(systemName: "chevron.right")
            }
            .padding()
            .background(Color.tb3Accent.opacity(0.15))
            .foregroundStyle(Color.tb3Accent)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest Day State

    private func restDayState(resumeDate: Date, reason: RestReason) -> some View {
        VStack(spacing: 16) {
            // Program header (same as active)
            programHeader

            // Return to workout banner (in case there's an active session)
            if appState.activeSession != nil {
                returnToWorkoutBanner
            }

            // Rest day card
            VStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.tb3Muted)

                Text("Rest Day")
                    .font(.title2.bold())

                let daysLeft = TrainingDayCalculator.daysUntilNextWorkout(resumeDate: resumeDate)
                Text(daysLeft <= 1
                    ? "Back to training tomorrow"
                    : "Next session in \(daysLeft) days")
                    .font(.subheadline)
                    .foregroundStyle(Color.tb3Muted)

                Text(reason == .endOfWeek
                    ? "Extra recovery between training weeks"
                    : "Recover before your next session")
                    .font(.caption)
                    .foregroundStyle(Color.tb3Disabled)
            }
            .padding(.vertical, 8)

            // Next session preview (read-only)
            if let (session, week) = currentSessionData {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Up Next")
                        .font(.headline)
                        .foregroundStyle(Color.tb3Muted)

                    SessionPreviewCard(session: session, week: week)
                }

                // Train Anyway button (secondary)
                Button {
                    if let program = appState.activeProgram {
                        if appState.activeSession != nil {
                            appState.isSessionPresented = true
                        } else {
                            onStartWorkout?(session.exercises, week, program)
                        }
                    }
                } label: {
                    Label("Train Anyway", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Deload State

    private func deloadState(endsDate: Date) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 60))
                .foregroundStyle(Color.tb3Accent)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            Text("Deload Week")
                .font(.title2.bold())

            let daysLeft = TrainingDayCalculator.daysRemainingInDeload(endsDate: endsDate)
            Text(daysLeft <= 1
                ? "Recovery period ends tomorrow"
                : "\(daysLeft) days of recovery remaining")
                .font(.subheadline)
                .foregroundStyle(Color.tb3Muted)

            Text("Focus on recovery and mobility.\nRetest your maxes when you're ready.")
                .font(.subheadline)
                .foregroundStyle(Color.tb3Disabled)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Retest 1RM") {
                    onNavigateToProfile()
                }
                .buttonStyle(.bordered)

                Button("New Template") {
                    onNavigateToProgram()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Computed

    private var trainingStatus: TrainingDayStatus {
        guard let program = appState.activeProgram else { return .noProgram }
        let template = Templates.get(id: program.templateId)
        return TrainingDayCalculator.status(
            program: program,
            template: template,
            sessionHistory: appState.sessionHistory
        )
    }

    private var progressPercent: Double {
        guard let program = appState.activeProgram,
              let template = Templates.get(id: program.templateId) else { return 0 }
        let totalSessions = template.durationWeeks * template.sessionsPerWeek
        let completedSessions = (program.currentWeek - 1) * template.sessionsPerWeek + (program.currentSession - 1)
        return totalSessions > 0 ? Double(completedSessions) / Double(totalSessions) : 0
    }

    private var currentSessionData: (ComputedSession, ComputedWeek)? {
        guard let program = appState.activeProgram,
              let schedule = appState.computedSchedule else { return nil }
        let weekIndex = program.currentWeek - 1
        let sessionIndex = program.currentSession - 1
        guard weekIndex >= 0, weekIndex < schedule.weeks.count else { return nil }
        let week = schedule.weeks[weekIndex]
        guard sessionIndex >= 0, sessionIndex < week.sessions.count else { return nil }
        return (week.sessions[sessionIndex], week)
    }

}
