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
                    if appState.activeProgram == nil {
                        emptyState
                    } else if isProgramComplete {
                        completedState
                    } else {
                        activeState
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

    private var activeState: some View {
        VStack(spacing: 16) {
            // Program header
            if let program = appState.activeProgram,
               let template = Templates.get(id: program.templateId) {
                VStack(spacing: 8) {
                    Text(template.name)
                        .font(.title2.bold())

                    Text("Week \(program.currentWeek) of \(template.durationWeeks)")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)

                    // Progress bar
                    ProgressView(value: progressPercent)
                        .tint(Color.tb3Accent)
                }
            }

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

    // MARK: - Computed

    private var isProgramComplete: Bool {
        guard let program = appState.activeProgram,
              let template = Templates.get(id: program.templateId) else { return false }
        return program.currentWeek > template.durationWeeks
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
