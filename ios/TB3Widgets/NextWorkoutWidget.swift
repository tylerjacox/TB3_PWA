// TB3 iOS — Next Workout Widget
// Shows upcoming session: template, week/day, exercises + weights.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: Date(), info: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextWorkoutEntry) -> Void) {
        let entry = NextWorkoutEntry(date: Date(), info: Self.loadNextWorkout())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = NextWorkoutEntry(date: Date(), info: Self.loadNextWorkout())
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static func loadNextWorkout() -> WidgetWorkoutInfo? {
        do {
            let container = try SharedContainer.makeModelContainer()
            let ctx = ModelContext(container)

            guard let persisted = try ctx.fetch(FetchDescriptor<PersistedActiveProgram>()).first else { return nil }
            let program = persisted.toSyncActiveProgram()
            guard let template = Templates.get(id: program.templateId) else { return nil }

            // Program complete or in deload?
            if program.currentWeek > template.durationWeeks { return nil }

            let profile = (try ctx.fetch(FetchDescriptor<PersistedProfile>()).first ?? PersistedProfile()).toSyncProfile()
            let maxTests = try ctx.fetch(FetchDescriptor<PersistedOneRepMaxTest>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )).map { $0.toSyncOneRepMaxTest() }
            let lifts = WidgetDataHelper.deriveCurrentLifts(from: maxTests, profile: profile)

            let schedule = ScheduleGenerator.generateSchedule(program: program, lifts: lifts, profile: profile)

            let weekIndex = program.currentWeek - 1
            let sessionIndex = program.currentSession - 1
            guard weekIndex >= 0, weekIndex < schedule.weeks.count else { return nil }
            let week = schedule.weeks[weekIndex]
            guard sessionIndex >= 0, sessionIndex < week.sessions.count else { return nil }
            let session = week.sessions[sessionIndex]

            // Compute rest day status from session history
            let sessionLogs = try ctx.fetch(FetchDescriptor<PersistedSessionLog>()).map { $0.toSyncSessionLog() }
            let trainingStatus = TrainingDayCalculator.status(
                program: program,
                template: template,
                sessionHistory: sessionLogs
            )
            let isRestDay: Bool
            let restDaysRemaining: Int
            if case .restDay(let resumeDate, _) = trainingStatus {
                isRestDay = true
                restDaysRemaining = TrainingDayCalculator.daysUntilNextWorkout(resumeDate: resumeDate)
            } else {
                isRestDay = false
                restDaysRemaining = 0
            }

            return WidgetWorkoutInfo(
                templateName: template.name,
                weekNumber: program.currentWeek,
                totalWeeks: template.durationWeeks,
                sessionNumber: program.currentSession,
                sessionsPerWeek: template.sessionsPerWeek,
                percentage: week.percentage,
                exercises: session.exercises.map { ex in
                    WidgetExercise(liftName: ex.liftName, targetWeight: ex.targetWeight, isBodyweight: ex.isBodyweight)
                },
                repsPerSet: week.repsPerSet,
                setsRange: week.setsRange,
                unit: profile.unit,
                isRestDay: isRestDay,
                restDaysRemaining: restDaysRemaining
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Entry

struct NextWorkoutEntry: TimelineEntry {
    let date: Date
    let info: WidgetWorkoutInfo?
}

// MARK: - Data Models

struct WidgetWorkoutInfo: Sendable {
    let templateName: String
    let weekNumber: Int
    let totalWeeks: Int
    let sessionNumber: Int
    let sessionsPerWeek: Int
    let percentage: Int
    let exercises: [WidgetExercise]
    let repsPerSet: RepsPerSet
    let setsRange: [Int]
    let unit: String
    let isRestDay: Bool
    let restDaysRemaining: Int  // 0 = workout day

    static let placeholder = WidgetWorkoutInfo(
        templateName: "Operator",
        weekNumber: 3,
        totalWeeks: 6,
        sessionNumber: 1,
        sessionsPerWeek: 3,
        percentage: 90,
        exercises: [
            WidgetExercise(liftName: "Squat", targetWeight: 225, isBodyweight: false),
            WidgetExercise(liftName: "Bench", targetWeight: 185, isBodyweight: false),
            WidgetExercise(liftName: "Deadlift", targetWeight: 275, isBodyweight: false),
        ],
        repsPerSet: .single(3),
        setsRange: [3, 4],
        unit: "lb",
        isRestDay: false,
        restDaysRemaining: 0
    )
}

struct WidgetExercise: Sendable {
    let liftName: String
    let targetWeight: Double
    let isBodyweight: Bool
}

// MARK: - Views

struct NextWorkoutSmallView: View {
    let info: WidgetWorkoutInfo?

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.templateName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if info.isRestDay {
                        Spacer()
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tb3Muted)
                    }
                }

                if info.isRestDay {
                    Text("Rest Day")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.tb3Muted)
                } else {
                    Text("Week \(info.weekNumber) \u{00B7} Day \(info.sessionNumber)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tb3Muted)
                }

                Spacer(minLength: 2)

                if info.isRestDay {
                    Text(info.restDaysRemaining <= 1
                        ? "Back tomorrow"
                        : "Back in \(info.restDaysRemaining) days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.tb3Muted)
                } else {
                    // Percentage badge
                    HStack(spacing: 4) {
                        Text("\(info.percentage)%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tb3Accent)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(repsLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.tb3Muted)
                            Text(setsLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.tb3Muted)
                        }
                    }
                }

                Spacer(minLength: 2)

                // Exercise count
                Text("\(info.exercises.count) exercises")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tb3Muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        } else {
            emptyState
        }
    }

    private var repsLabel: String {
        switch info!.repsPerSet {
        case .single(let r): return "\(r) reps"
        case .array(let arr): return arr.map(String.init).joined(separator: ",") + " reps"
        }
    }

    private var setsLabel: String {
        if info!.setsRange.count == 2, info!.setsRange[0] != info!.setsRange[1] {
            return "\(info!.setsRange[0])-\(info!.setsRange[1]) sets"
        }
        return "\(info!.setsRange.first ?? 3) sets"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.system(size: 28))
                .foregroundStyle(Color.tb3Muted)
            Text("No Active\nProgram")
                .font(.system(size: 13))
                .foregroundStyle(Color.tb3Muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NextWorkoutMediumView: View {
    let info: WidgetWorkoutInfo?

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.templateName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        if info.isRestDay {
                            HStack(spacing: 4) {
                                Image(systemName: "bed.double.fill")
                                    .font(.system(size: 10))
                                Text("Rest Day")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.tb3Muted)
                        } else {
                            Text("Week \(info.weekNumber) \u{00B7} Day \(info.sessionNumber)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.tb3Muted)
                        }
                    }
                    Spacer()
                    if info.isRestDay {
                        Text(info.restDaysRemaining <= 1
                            ? "Back tomorrow"
                            : "Back in \(info.restDaysRemaining)d")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.tb3Muted)
                    } else {
                        Text("\(info.percentage)%")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tb3Accent)
                    }
                }

                Divider()
                    .background(Color.tb3Border)

                // Exercise list (dimmed on rest days)
                ForEach(Array(info.exercises.prefix(4).enumerated()), id: \.offset) { _, exercise in
                    HStack {
                        Circle()
                            .fill(Color.liftColor(for: exercise.liftName))
                            .frame(width: 6, height: 6)
                            .opacity(info.isRestDay ? 0.5 : 1)
                        Text(exercise.liftName)
                            .font(.system(size: 12))
                            .foregroundStyle(info.isRestDay ? Color.tb3Disabled : .white)
                            .lineLimit(1)
                        Spacer()
                        if exercise.isBodyweight {
                            Text("BW+\(formatWeight(exercise.targetWeight))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(info.isRestDay ? Color.tb3Disabled : Color.tb3Accent)
                        } else {
                            Text("\(formatWeight(exercise.targetWeight)) \(info.unit)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(info.isRestDay ? Color.tb3Disabled : Color.tb3Accent)
                        }
                    }
                }

                if info.exercises.count > 4 {
                    Text("+\(info.exercises.count - 4) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.tb3Muted)
                }
            }
            .padding(2)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.tb3Muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Active Program")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.tb3Muted)
                    Text("Open TB3 to start training")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tb3Disabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}

// MARK: - Widget

struct NextWorkoutWidget: Widget {
    let kind: String = "NextWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextWorkoutProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    NextWorkoutWidgetEntryView(entry: entry)
                        .containerBackground(Color.tb3Background, for: .widget)
                } else {
                    NextWorkoutWidgetEntryView(entry: entry)
                        .background(Color.tb3Background)
                }
            }
        }
        .configurationDisplayName("Next Workout")
        .description("See your upcoming workout at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextWorkoutWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextWorkoutEntry

    var body: some View {
        switch family {
        case .systemSmall:
            NextWorkoutSmallView(info: entry.info)
        case .systemMedium:
            NextWorkoutMediumView(info: entry.info)
        default:
            NextWorkoutSmallView(info: entry.info)
        }
    }
}
