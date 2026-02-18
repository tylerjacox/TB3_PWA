# iOS-Native Enhancement Roadmap

iOS-native capabilities for the TB3 app, grouped by estimated impact.

---

## ✅ Completed

### 3. App Intents & Siri Shortcuts ✅

Three App Intents exposed to Siri, Shortcuts app, and Spotlight:

- **StartWorkoutIntent** — Launches today's scheduled session, mappable to Action Button
- **LogOneRepMaxIntent** — Record a new 1RM for any lift with parameters for lift, weight, reps
- **WhatsMyNextWorkoutIntent** — Returns schedule info via Siri dialog
- **Framework:** AppIntents
- **Files:** `TB3/Intents/StartWorkoutIntent.swift`, `LogOneRepMaxIntent.swift`, `WhatsMyNextWorkoutIntent.swift`, `IntentDataProvider.swift`

### 5. WidgetKit (Home Screen, Lock Screen) ✅

Four home screen widgets with shared App Group data access:

- **Next Workout Widget** (small + medium) — Template, week/session, exercises with target weights
- **Lift PRs Widget** (small + medium) — Current 1RM and working max per lift with color bars
- **Progress Widget** (small + accessoryCircular) — Completion ring with week counter
- **Strength Trend Widget** (small + medium) — Multi-line 1RM chart (SwiftUI Charts) over 6 months
- **Framework:** WidgetKit + App Groups (`group.com.tb3.app`)
- **Files:** `TB3Widgets/` directory (5 widget files + WidgetDataHelper), `TB3/Services/SharedContainer.swift`
- **Data:** Shared via `ModelConfiguration(url:)` pointing to App Group container; one-time migration from default store

### 6. Swift Charts — Progress Visualization ✅

Native `MaxChartView` with per-lift line charts and time range filtering (Day/Week/Month/Year/All). Strength Trend widget also uses SwiftUI Charts for compact 1RM sparklines.

---

## What's Already Used

- SwiftData, SwiftUI, Keychain, UserDefaults, FileManager
- AVAudioEngine (tones), AVSpeechSynthesizer (voice countdowns)
- UIImpactFeedbackGenerator / UINotificationFeedbackGenerator (haptics)
- NWPathMonitor (network detection)
- ASWebAuthenticationSession (OAuth for Cognito + Strava)
- GoogleCast SDK (Chromecast)
- AppIntents (Siri Shortcuts)
- WidgetKit + App Groups (home screen widgets)
- SwiftUI Charts (1RM progression)

---

## Tier 1 — High Impact

### 1. Live Activities & Dynamic Island

Show active workout state on the lock screen and Dynamic Island without opening the app.

- Rest timer countdown visible at a glance (fits the "count up, overtime alert" model)
- Current exercise name, set progress (e.g. "Bench — Set 3/5")
- Tap Dynamic Island to jump back into session
- Works even when phone is locked/pocketed
- **Framework:** ActivityKit, requires a Widget Extension target
- **Status:** Extension target scaffolded (`TB3LiveActivity/`), basic implementation in place

### 2. HealthKit Integration

Write completed sessions as `HKWorkout` (type `.strengthTraining`) to Apple Health.

- Duration, estimated calories, heart rate (if available)
- Appears in Activity Rings and Health app history
- Could also read body weight from Health for strength-to-weight ratios
- Complements Strava (some users prefer Health as single source of truth)
- **Framework:** HealthKit, requires entitlement + user permission

### 4. Apple Watch Companion

Minimal watchOS app for hands-free workout tracking.

- Display current exercise, set count, weight, and rest timer on wrist
- Haptic tap when rest period ends (more reliable than phone in pocket)
- "Complete Set" button on wrist — no need to touch phone
- Watch complications showing next workout or streak
- **Framework:** WatchKit + Watch Connectivity, separate target
- **Effort:** High — this is a significant build

---

## Tier 2 — Medium Impact

### 7. Core Haptics — Richer Tactile Feedback

Go beyond basic UIImpactFeedbackGenerator to custom haptic patterns.

- Distinct patterns for: set complete, exercise complete, rest overtime, session finish
- Escalating pulses as rest timer approaches overtime
- Subtle confirmation haptic when swiping between exercises
- **Framework:** CoreHaptics (already partially used, can be expanded)

---

## Tier 3 — Nice-to-Have / Polish

### 8. TipKit — Feature Discovery

Contextual tips for onboarding and feature education.

- "Swipe left/right to navigate exercises"
- "Tap the timer to toggle rest/exercise phase"
- Sequential tip groups (iOS 18+) to avoid overwhelming new users
- **Framework:** TipKit

### 9. Focus Filters — Workout Mode

Integrate with iOS Focus system.

- When user activates a "Workout" Focus, TB3 can filter UI to session-only mode
- Suppress non-essential notifications during workout
- **Framework:** AppIntents (Focus filter intents)

### 10. Background App Refresh & BGTaskScheduler

Schedule periodic sync in the background.

- Sync data even when app isn't open (currently only syncs on foreground)
- Refresh widgets with latest data
- **Framework:** BackgroundTasks

### 11. Local Notifications

Timer-based reminders and workout prompts.

- "You have a workout scheduled today" morning reminder
- Missed workout nudges (configurable)
- **Framework:** UserNotifications

### 12. StoreKit 2 — Monetization (only if applicable)

Modern in-app purchase framework if premium features are planned.

- Subscription or one-time unlock for advanced templates, analytics, etc.
- Built-in SwiftUI views: `SubscriptionStoreView`, `ProductView`
- **Framework:** StoreKit

---

## Not Recommended

- **CloudKit** — Already have a working AWS sync backend; adding CloudKit creates dual-sync complexity
- **App Clips** — Users need the full app for ongoing tracking; clips don't fit the use case
- **Vision / CoreML** — No clear application for a workout tracker

---

## Summary

| # | Feature | Impact | Effort | Status |
|---|---------|--------|--------|--------|
| 1 | Live Activities | Very High | Medium | Scaffolded |
| 2 | HealthKit | Very High | Medium | Not started |
| 3 | App Intents / Siri | Very High | Medium | ✅ Done |
| 4 | Apple Watch | Very High | High | Not started |
| 5 | WidgetKit | High | Medium | ✅ Done (4 widgets) |
| 6 | Swift Charts | High | Low | ✅ Done |
| 7 | Core Haptics | Medium | Low | Partial |
| 8 | TipKit | Medium | Low | Not started |
| 9 | Focus Filters | Low | Low | Not started |
| 10 | Background Sync | Medium | Low | Not started |
| 11 | Notifications | Medium | Low | Not started |
| 12 | StoreKit 2 | Conditional | Medium | Not started |
