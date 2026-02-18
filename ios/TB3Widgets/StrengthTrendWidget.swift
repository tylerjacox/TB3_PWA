// TB3 iOS — Strength Trend Widget
// Shows 1RM progression over time as a multi-line chart.

import WidgetKit
import SwiftUI
import SwiftData
import Charts

// MARK: - Timeline Provider

struct StrengthTrendProvider: TimelineProvider {
    func placeholder(in context: Context) -> StrengthTrendEntry {
        StrengthTrendEntry(date: Date(), points: StrengthTrendEntry.placeholderPoints, unit: "lb")
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StrengthTrendEntry) -> Void) {
        let (points, unit) = Self.loadChartData()
        completion(StrengthTrendEntry(date: Date(), points: points, unit: unit))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StrengthTrendEntry>) -> Void) {
        let (points, unit) = Self.loadChartData()
        let entry = StrengthTrendEntry(date: Date(), points: points, unit: unit)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static func loadChartData() -> ([ChartPoint], String) {
        do {
            let container = try SharedContainer.makeModelContainer()
            let ctx = ModelContext(container)

            let profile = (try ctx.fetch(FetchDescriptor<PersistedProfile>()).first ?? PersistedProfile()).toSyncProfile()
            let maxTests = try ctx.fetch(FetchDescriptor<PersistedOneRepMaxTest>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )).map { $0.toSyncOneRepMaxTest() }

            // Filter to last 6 months
            let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
            let recentTests = maxTests.filter { test in
                guard let date = Date.fromISO8601(test.date) else { return false }
                return date >= sixMonthsAgo
            }

            guard !recentTests.isEmpty else { return ([], profile.unit) }

            let points = recentTests.compactMap { test -> ChartPoint? in
                guard let date = Date.fromISO8601(test.date) else { return nil }
                return ChartPoint(
                    date: date,
                    liftName: test.liftName,
                    oneRepMax: test.calculatedMax
                )
            }

            return (points, profile.unit)
        } catch {
            return ([], "lb")
        }
    }
}

// MARK: - Entry & Data

struct StrengthTrendEntry: TimelineEntry {
    let date: Date
    let points: [ChartPoint]
    let unit: String

    static let placeholderPoints: [ChartPoint] = {
        let cal = Calendar.current
        let now = Date()
        var pts: [ChartPoint] = []
        for i in stride(from: 5, through: 0, by: -1) {
            let d = cal.date(byAdding: .month, value: -i, to: now)!
            pts.append(ChartPoint(date: d, liftName: "Squat", oneRepMax: 275 + Double(5 - i) * 8))
            pts.append(ChartPoint(date: d, liftName: "Bench", oneRepMax: 195 + Double(5 - i) * 6))
            pts.append(ChartPoint(date: d, liftName: "Deadlift", oneRepMax: 335 + Double(5 - i) * 10))
        }
        return pts
    }()
}

struct ChartPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let liftName: String
    let oneRepMax: Double
}

// MARK: - Medium View (Multi-line chart)

struct StrengthTrendMediumView: View {
    let points: [ChartPoint]
    let unit: String

    var body: some View {
        if points.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strength Trend")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tb3Muted)

                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(by: .value("Lift", shortName(point.liftName)))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartForegroundStyleScale(domain: uniqueLifts.map { shortName($0) }, range: uniqueLifts.map { Color.liftColor(for: $0) })
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.tb3Disabled)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.tb3Disabled)
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 4) {
                    HStack(spacing: 8) {
                        ForEach(uniqueLifts, id: \.self) { lift in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.liftColor(for: lift))
                                    .frame(width: 5, height: 5)
                                Text(shortName(lift))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.tb3Muted)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(2)
        }
    }

    private var uniqueLifts: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for point in points {
            if seen.insert(point.liftName).inserted {
                result.append(point.liftName)
            }
        }
        return result
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.tb3Muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Test Your Maxes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.tb3Muted)
                Text("Chart shows 1RM over time")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tb3Disabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "Military Press": return "Press"
        case "Weighted Pull-up": return "Pull-up"
        default: return name
        }
    }
}

// MARK: - Small View (Single-lift sparkline)

struct StrengthTrendSmallView: View {
    let points: [ChartPoint]
    let unit: String

    var body: some View {
        if let liftData = primaryLiftData {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.liftColor(for: liftData.liftName))
                        .frame(width: 4, height: 16)
                    Text(liftData.liftName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatWeight(liftData.current))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tb3Muted)
                }

                // Sparkline
                Chart(liftData.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(Color.liftColor(for: liftData.liftName))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.liftColor(for: liftData.liftName).opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Trend indicator
                if let change = liftData.change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(change >= 0 ? "+" : "")\(formatWeight(change))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(change >= 0 ? Color.tb3Success : Color.tb3Error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        } else {
            emptyState
        }
    }

    private struct LiftSummary {
        let liftName: String
        let current: Double
        let change: Double?
        let points: [ChartPoint]
    }

    private var primaryLiftData: LiftSummary? {
        guard !points.isEmpty else { return nil }

        // Group by lift and find the most recently tested one
        var byLift: [String: [ChartPoint]] = [:]
        for p in points {
            byLift[p.liftName, default: []].append(p)
        }

        // Sort each lift's points by date
        for (key, val) in byLift {
            byLift[key] = val.sorted { $0.date < $1.date }
        }

        // Pick lift with most recent test
        guard let (liftName, liftPoints) = byLift.max(by: {
            ($0.value.last?.date ?? .distantPast) < ($1.value.last?.date ?? .distantPast)
        }), let last = liftPoints.last else { return nil }

        let change: Double? = liftPoints.count >= 2
            ? last.oneRepMax - liftPoints.first!.oneRepMax
            : nil

        return LiftSummary(
            liftName: liftName,
            current: last.oneRepMax,
            change: change,
            points: liftPoints
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.tb3Muted)
            Text("Test Your\nMaxes")
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

// MARK: - Widget

struct StrengthTrendWidget: Widget {
    let kind: String = "StrengthTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StrengthTrendProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    StrengthTrendEntryView(entry: entry)
                        .containerBackground(Color.tb3Background, for: .widget)
                } else {
                    StrengthTrendEntryView(entry: entry)
                        .background(Color.tb3Background)
                }
            }
        }
        .configurationDisplayName("Strength Trend")
        .description("Track your 1RM progression over time.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StrengthTrendEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StrengthTrendEntry

    var body: some View {
        switch family {
        case .systemSmall:
            StrengthTrendSmallView(points: entry.points, unit: entry.unit)
        case .systemMedium:
            StrengthTrendMediumView(points: entry.points, unit: entry.unit)
        default:
            StrengthTrendSmallView(points: entry.points, unit: entry.unit)
        }
    }
}
