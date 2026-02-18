// TB3 iOS — Intent Data Provider
// Standalone SwiftData access for App Intents (works even when AppState isn't initialized).

import Foundation
import SwiftData

@MainActor
enum IntentDataProvider {

    private static func makeContainer() throws -> ModelContainer {
        try SharedContainer.makeModelContainer()
    }

    // MARK: - Data Loading

    static func loadProfile() throws -> SyncProfile {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<PersistedProfile>()
        let profiles = try container.mainContext.fetch(descriptor)
        return (profiles.first ?? PersistedProfile()).toSyncProfile()
    }

    static func loadActiveProgram() throws -> SyncActiveProgram? {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<PersistedActiveProgram>()
        return try container.mainContext.fetch(descriptor).first?.toSyncActiveProgram()
    }

    static func loadMaxTestHistory() throws -> [SyncOneRepMaxTest] {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<PersistedOneRepMaxTest>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try container.mainContext.fetch(descriptor).map { $0.toSyncOneRepMaxTest() }
    }

    // MARK: - Derived State

    /// Derive current lifts from max test history (same logic as AppState.currentLifts)
    static func deriveCurrentLifts(from maxTests: [SyncOneRepMaxTest], profile: SyncProfile? = nil) -> [DerivedLiftEntry] {
        var latestByLift: [String: SyncOneRepMaxTest] = [:]
        for test in maxTests {
            if let existing = latestByLift[test.liftName] {
                if test.date > existing.date {
                    latestByLift[test.liftName] = test
                }
            } else {
                latestByLift[test.liftName] = test
            }
        }

        // Use profile's current maxType setting (matches PWA behavior)
        let maxType = (try? profile ?? loadProfile())?.maxType ?? "training"

        return latestByLift.values.map { test in
            let oneRepMax = OneRepMaxCalculator.calculateOneRepMax(weight: test.weight, reps: test.reps)
            let workingMax: Double
            if maxType == "training" {
                workingMax = OneRepMaxCalculator.calculateTrainingMax(oneRepMax: oneRepMax)
            } else {
                workingMax = oneRepMax
            }
            return DerivedLiftEntry(
                name: test.liftName,
                weight: test.weight,
                reps: test.reps,
                oneRepMax: oneRepMax,
                workingMax: workingMax,
                isBodyweight: test.liftName == LiftName.weightedPullUp.rawValue,
                testDate: test.date
            )
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Next Workout

    /// Resolve the next scheduled workout with full detail.
    static func getNextWorkoutInfo() throws -> NextWorkoutInfo? {
        guard let program = try loadActiveProgram() else { return nil }
        guard let template = Templates.get(id: program.templateId) else { return nil }

        // Program complete?
        if program.currentWeek > template.durationWeeks { return nil }

        let profile = try loadProfile()
        let maxTests = try loadMaxTestHistory()
        let lifts = deriveCurrentLifts(from: maxTests, profile: profile)

        let schedule = ScheduleGenerator.generateSchedule(
            program: program, lifts: lifts, profile: profile
        )

        let weekIndex = program.currentWeek - 1
        let sessionIndex = program.currentSession - 1
        guard weekIndex >= 0, weekIndex < schedule.weeks.count else { return nil }
        let week = schedule.weeks[weekIndex]
        guard sessionIndex >= 0, sessionIndex < week.sessions.count else { return nil }
        let session = week.sessions[sessionIndex]

        return NextWorkoutInfo(
            templateName: template.name,
            weekNumber: program.currentWeek,
            totalWeeks: template.durationWeeks,
            sessionNumber: program.currentSession,
            sessionsPerWeek: template.sessionsPerWeek,
            percentage: week.percentage,
            exercises: session.exercises,
            repsPerSet: week.repsPerSet,
            setsRange: week.setsRange,
            unit: profile.unit
        )
    }
}

// MARK: - NextWorkoutInfo

struct NextWorkoutInfo {
    let templateName: String
    let weekNumber: Int
    let totalWeeks: Int
    let sessionNumber: Int
    let sessionsPerWeek: Int
    let percentage: Int
    let exercises: [ComputedExercise]
    let repsPerSet: RepsPerSet
    let setsRange: [Int]
    let unit: String
}
