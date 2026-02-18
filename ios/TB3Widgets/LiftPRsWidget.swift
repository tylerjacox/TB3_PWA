// TB3 iOS — Lift PRs Widget
// Shows current 1RM and working max per lift with color coding.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct LiftPRsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiftPRsEntry {
        LiftPRsEntry(date: Date(), lifts: LiftPRsEntry.placeholderLifts, unit: "lb")
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (LiftPRsEntry) -> Void) {
        let (lifts, unit) = Self.loadLifts()
        completion(LiftPRsEntry(date: Date(), lifts: lifts, unit: unit))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LiftPRsEntry>) -> Void) {
        let (lifts, unit) = Self.loadLifts()
        let entry = LiftPRsEntry(date: Date(), lifts: lifts, unit: unit)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static func loadLifts() -> ([WidgetLiftPR], String) {
        do {
            let container = try SharedContainer.makeModelContainer()
            let ctx = ModelContext(container)

            let profile = (try ctx.fetch(FetchDescriptor<PersistedProfile>()).first ?? PersistedProfile()).toSyncProfile()
            let maxTests = try ctx.fetch(FetchDescriptor<PersistedOneRepMaxTest>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )).map { $0.toSyncOneRepMaxTest() }

            let derived = WidgetDataHelper.deriveCurrentLifts(from: maxTests, profile: profile)

            let lifts = derived.map { entry in
                WidgetLiftPR(
                    name: entry.name,
                    oneRepMax: entry.oneRepMax,
                    workingMax: entry.workingMax,
                    isBodyweight: entry.isBodyweight
                )
            }

            return (lifts, profile.unit)
        } catch {
            return ([], "lb")
        }
    }
}

// MARK: - Entry

struct LiftPRsEntry: TimelineEntry {
    let date: Date
    let lifts: [WidgetLiftPR]
    let unit: String

    static let placeholderLifts: [WidgetLiftPR] = [
        WidgetLiftPR(name: "Squat", oneRepMax: 315, workingMax: 283.5, isBodyweight: false),
        WidgetLiftPR(name: "Bench", oneRepMax: 225, workingMax: 202.5, isBodyweight: false),
        WidgetLiftPR(name: "Deadlift", oneRepMax: 405, workingMax: 364.5, isBodyweight: false),
        WidgetLiftPR(name: "Military Press", oneRepMax: 155, workingMax: 139.5, isBodyweight: false),
        WidgetLiftPR(name: "Weighted Pull-up", oneRepMax: 90, workingMax: 81, isBodyweight: true),
    ]
}

struct WidgetLiftPR: Sendable {
    let name: String
    let oneRepMax: Double
    let workingMax: Double
    let isBodyweight: Bool
}

// MARK: - Views

struct LiftPRsSmallView: View {
    let lifts: [WidgetLiftPR]
    let unit: String

    var body: some View {
        if let lift = lifts.first {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.liftColor(for: lift.name))
                        .frame(width: 4, height: 20)
                    Text(lift.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1RM")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tb3Muted)
                        Text("\(formatWeight(lift.oneRepMax))")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        + Text(" \(unit)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tb3Muted)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Working")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tb3Muted)
                        Text("\(formatWeight(lift.workingMax))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tb3Accent)
                        + Text(" \(unit)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tb3Muted)
                    }
                }

                Spacer(minLength: 2)

                if lifts.count > 1 {
                    Text("+\(lifts.count - 1) more lifts")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.tb3Muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.system(size: 28))
                .foregroundStyle(Color.tb3Muted)
            Text("Set Your\nMaxes")
                .font(.system(size: 13))
                .foregroundStyle(Color.tb3Muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}

struct LiftPRsMediumView: View {
    let lifts: [WidgetLiftPR]
    let unit: String

    var body: some View {
        if !lifts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // Header
                Text("Current Maxes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tb3Muted)

                // Lift grid
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(lifts.prefix(5).enumerated()), id: \.offset) { _, lift in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.liftColor(for: lift.name))
                                .frame(width: 3, height: 28)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(shortName(lift.name))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.tb3Muted)
                                    .lineLimit(1)

                                HStack(spacing: 2) {
                                    Text(formatWeight(lift.oneRepMax))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("/")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.tb3Disabled)

                                    Text(formatWeight(lift.workingMax))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.tb3Accent)
                                }
                            }
                        }
                    }
                }
            }
            .padding(2)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.tb3Muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Your Maxes")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.tb3Muted)
                    Text("Open TB3 to enter your lifts")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tb3Disabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "Military Press": return "Mil. Press"
        case "Weighted Pull-up": return "Pull-up"
        default: return name
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}

// MARK: - Widget

struct LiftPRsWidget: Widget {
    let kind: String = "LiftPRsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiftPRsProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    LiftPRsWidgetEntryView(entry: entry)
                        .containerBackground(Color.tb3Background, for: .widget)
                } else {
                    LiftPRsWidgetEntryView(entry: entry)
                        .background(Color.tb3Background)
                }
            }
        }
        .configurationDisplayName("Lift PRs")
        .description("Your current 1RM and working max per lift.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LiftPRsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: LiftPRsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            LiftPRsSmallView(lifts: entry.lifts, unit: entry.unit)
        case .systemMedium:
            LiftPRsMediumView(lifts: entry.lifts, unit: entry.unit)
        default:
            LiftPRsSmallView(lifts: entry.lifts, unit: entry.unit)
        }
    }
}
