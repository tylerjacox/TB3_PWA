// TB3 iOS — App Shortcuts Provider
// Registers Siri phrases, Shortcuts app entries, and Action Button actions.

import AppIntents

struct TB3Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my \(.applicationName) workout",
                "Start \(.applicationName)",
                "Begin \(.applicationName) session",
                "Start training in \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )

        AppShortcut(
            intent: NextWorkoutIntent(),
            phrases: [
                "What's my next \(.applicationName) workout",
                "Show my next \(.applicationName) session",
                "What's next in \(.applicationName)",
            ],
            shortTitle: "Next Workout",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: CurrentMaxesIntent(),
            phrases: [
                "What are my \(.applicationName) maxes",
                "Show my \(.applicationName) lifts",
                "What are my current maxes in \(.applicationName)",
            ],
            shortTitle: "Current Maxes",
            systemImageName: "trophy"
        )
    }
}
