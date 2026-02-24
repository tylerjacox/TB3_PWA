// TB3 iOS — History View (session logs + max test history)

import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) var appState
    var stravaService: StravaService?
    @State private var selectedTab = 0
    @State private var sortedSessions: [SyncSessionLog] = []
    @State private var groupedMaxTests: [(lift: LiftName, tests: [SyncOneRepMaxTest])] = []

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "History")

            Picker("View", selection: $selectedTab) {
                Text("Calendar").tag(0)
                Text("Chart").tag(1)
                Text("Max Tests").tag(2)
                Text("Sessions").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            switch selectedTab {
            case 0:
                CalendarHistoryView(sessions: appState.sessionHistory)
            case 1:
                MaxChartView(maxTests: appState.maxTestHistory)
            case 2:
                maxTestList
            default:
                sessionList
            }
        }
        .background(Color.tb3Background)
        .onAppear {
            recomputeSortedSessions()
            recomputeGroupedMaxTests()
        }
        .onChange(of: appState.sessionHistory.count) { _, _ in
            recomputeSortedSessions()
        }
        .onChange(of: appState.maxTestHistory.count) { _, _ in
            recomputeGroupedMaxTests()
        }
    }

    private func recomputeSortedSessions() {
        sortedSessions = appState.sessionHistory.sorted { $0.date > $1.date }
    }

    private func recomputeGroupedMaxTests() {
        var dict: [String: [SyncOneRepMaxTest]] = [:]
        for test in appState.maxTestHistory {
            dict[test.liftName, default: []].append(test)
        }
        groupedMaxTests = LiftName.allCases.compactMap { lift in
            guard let tests = dict[lift.rawValue], !tests.isEmpty else { return nil }
            return (lift: lift, tests: tests.sorted { $0.date > $1.date })
        }
    }

    // MARK: - Sessions

    private var sessionList: some View {
        Group {
            if sortedSessions.isEmpty {
                emptyState("No sessions yet", icon: "figure.strengthtraining.traditional")
            } else {
                List {
                    ForEach(sortedSessions, id: \.id) { session in
                        SessionLogRow(session: session, stravaService: stravaService, stravaConnected: appState.stravaState.isConnected)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Max Tests

    private var maxTestList: some View {
        Group {
            if groupedMaxTests.isEmpty {
                emptyState("No max tests yet", icon: "chart.line.uptrend.xyaxis")
            } else {
                List {
                    ForEach(groupedMaxTests, id: \.lift.rawValue) { group in
                        Section(group.lift.displayName) {
                            ForEach(group.tests, id: \.id) { test in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(Int(test.weight)) lb \u{00D7} \(test.reps) reps")
                                            .font(.subheadline)
                                        Text("1RM: \(Int(test.calculatedMax)) lb (\(test.maxType))")
                                            .font(.caption)
                                            .foregroundStyle(Color.tb3Muted)
                                    }
                                    Spacer()
                                    if let date = Date.fromISO8601(test.date) {
                                        Text(date.shortDisplay)
                                            .font(.caption)
                                            .foregroundStyle(Color.tb3Disabled)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.tb3Muted)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.tb3Muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Log Row

struct SessionLogRow: View {
    let session: SyncSessionLog
    var stravaService: StravaService?
    var stravaConnected: Bool = false
    @State private var isExpanded = false
    @State private var isSharing = false
    @State private var shareResult: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.templateId.capitalized)
                            .font(.subheadline.bold())
                        Text("Week \(session.week) \u{2022} Session \(session.sessionNumber)")
                            .font(.caption)
                            .foregroundStyle(Color.tb3Muted)
                    }
                    Spacer()
                    if let date = Date.fromISO8601(session.date) {
                        Text(date.shortDisplay)
                            .font(.caption)
                            .foregroundStyle(Color.tb3Disabled)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.tb3Disabled)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName)
                            .font(.caption.bold())

                        let setsText = exercise.sets.enumerated().map { i, set in
                            "Set \(i+1): \(set.actualReps) reps"
                        }.joined(separator: ", ")
                        let weightText = "\(Int(exercise.targetWeight)) lb"

                        Text("\(weightText) — \(setsText)")
                            .font(.caption)
                            .foregroundStyle(Color.tb3Muted)
                    }
                    .padding(.leading, 12)
                }

                // Strava share button
                if stravaConnected, let stravaService {
                    HStack {
                        Spacer()
                        Button {
                            isSharing = true
                            shareResult = nil
                            Task {
                                await stravaService.shareActivity(session: session)
                                isSharing = false
                                shareResult = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isSharing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if shareResult == true {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.tb3Success)
                                } else {
                                    Image(systemName: "arrow.up.forward.circle")
                                        .foregroundStyle(Color(hex: 0xFC4C02))
                                }
                                Text(shareResult == true ? "Shared" : "Share to Strava")
                                    .font(.caption.bold())
                                    .foregroundStyle(shareResult == true ? Color.tb3Success : Color(hex: 0xFC4C02))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSharing || shareResult == true)
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                }
            }
        }
    }
}
