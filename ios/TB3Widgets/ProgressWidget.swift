// TB3 iOS — Program Progress Widget
// Shows a progress ring with current week/total and template name.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), info: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ProgressEntry) -> Void) {
        let info = Self.loadProgress()
        completion(ProgressEntry(date: Date(), info: info))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ProgressEntry>) -> Void) {
        let info = Self.loadProgress()
        let entry = ProgressEntry(date: Date(), info: info)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static func loadProgress() -> WidgetProgressInfo? {
        do {
            let container = try SharedContainer.makeModelContainer()
            let ctx = ModelContext(container)

            guard let persisted = try ctx.fetch(FetchDescriptor<PersistedActiveProgram>()).first else { return nil }
            let program = persisted.toSyncActiveProgram()
            guard let template = Templates.get(id: program.templateId) else { return nil }

            // Clamp week to valid range
            let currentWeek = min(program.currentWeek, template.durationWeeks)
            let isComplete = program.currentWeek > template.durationWeeks

            // Calculate total sessions completed
            let totalSessions = template.durationWeeks * template.sessionsPerWeek
            let completedSessions: Int
            if isComplete {
                completedSessions = totalSessions
            } else {
                completedSessions = (program.currentWeek - 1) * template.sessionsPerWeek + (program.currentSession - 1)
            }

            let progress = totalSessions > 0 ? Double(completedSessions) / Double(totalSessions) : 0

            return WidgetProgressInfo(
                templateName: template.name,
                currentWeek: currentWeek,
                totalWeeks: template.durationWeeks,
                currentSession: program.currentSession,
                sessionsPerWeek: template.sessionsPerWeek,
                progress: progress,
                isComplete: isComplete
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Entry

struct ProgressEntry: TimelineEntry {
    let date: Date
    let info: WidgetProgressInfo?
}

struct WidgetProgressInfo: Sendable {
    let templateName: String
    let currentWeek: Int
    let totalWeeks: Int
    let currentSession: Int
    let sessionsPerWeek: Int
    let progress: Double
    let isComplete: Bool

    static let placeholder = WidgetProgressInfo(
        templateName: "Operator",
        currentWeek: 3,
        totalWeeks: 6,
        currentSession: 2,
        sessionsPerWeek: 3,
        progress: 0.39,
        isComplete: false
    )
}

// MARK: - Views

struct ProgressSmallView: View {
    let info: WidgetProgressInfo?

    var body: some View {
        if let info {
            VStack(spacing: 4) {
                Text(info.templateName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.tb3Muted)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.tb3Border, lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: info.progress)
                        .stroke(
                            info.isComplete ? Color.tb3Success : Color.tb3Accent,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        if info.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.tb3Success)
                        } else {
                            Text("W\(info.currentWeek)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 70, height: 70)

                Spacer(minLength: 2)

                if info.isComplete {
                    Text("Complete!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.tb3Success)
                } else {
                    Text("of \(info.totalWeeks) weeks")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tb3Muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(2)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 28))
                .foregroundStyle(Color.tb3Muted)
            Text("No\nProgram")
                .font(.system(size: 13))
                .foregroundStyle(Color.tb3Muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProgressAccessoryView: View {
    let info: WidgetProgressInfo?

    var body: some View {
        if let info {
            Gauge(value: info.progress) {
                Text("TB3")
            } currentValueLabel: {
                if info.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                } else {
                    Text("W\(info.currentWeek)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Gauge(value: 0) {
                Text("TB3")
            } currentValueLabel: {
                Text("--")
                    .font(.system(size: 10))
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

// MARK: - Widget

struct ProgressWidget: Widget {
    let kind: String = "ProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    ProgressWidgetEntryView(entry: entry)
                        .containerBackground(Color.tb3Background, for: .widget)
                } else {
                    ProgressWidgetEntryView(entry: entry)
                        .background(Color.tb3Background)
                }
            }
        }
        .configurationDisplayName("Program Progress")
        .description("Track your training cycle progress.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ProgressWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ProgressEntry

    var body: some View {
        switch family {
        case .systemSmall:
            ProgressSmallView(info: entry.info)
        case .accessoryCircular:
            ProgressAccessoryView(info: entry.info)
        default:
            ProgressSmallView(info: entry.info)
        }
    }
}
