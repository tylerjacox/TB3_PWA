# iOS Feature Evaluation

Comprehensive evaluation of features that could be implemented on the TB3 iOS app, based on analysis of the current codebase, existing ROADMAP, data models, backend capabilities, and iOS platform APIs.

---

## Current State Summary

### Already Implemented
| Feature | Status | Key Files |
|---|---|---|
| Full workout tracking (set-by-set) | Complete | `SessionViewModel.swift`, `SessionView.swift` |
| 7 TB templates with schedule pre-computation | Complete | `AllTemplates.swift`, `ScheduleGenerator.swift` |
| Visual plate loading (barbell + belt) | Complete | `PlateCalculator.swift`, `PlateDisplayView.swift` |
| 1RM calculator (Epley) + percentage tables | Complete | `OneRepMaxCalculator.swift` |
| Chromecast with 2-column layout | Complete | `CastService.swift`, `GCKCastSessionAdapter.swift` |
| Spotify integration (now playing, controls, likes) | Complete | `SpotifyService.swift`, `NowPlayingView.swift` |
| Strava integration (auto-share workouts) | Complete | `StravaService.swift` |
| WeatherKit (ambient temp per session) | Complete | `TB3WeatherService.swift` |
| Cloud sync (Cognito + DynamoDB) | Complete | `SyncService.swift`, `SyncCoordinator.swift` |
| Siri Shortcuts (3 intents) | Complete | `Intents/` directory |
| WidgetKit (4 widgets) | Complete | `TB3Widgets/` directory |
| Swift Charts (1RM progression) | Complete | `MaxChartView.swift` |
| Live Activities (lock screen + Dynamic Island) | Complete | `LiveActivityService.swift`, `TB3LiveActivity/` |
| Local notifications (rest timer, reminders, milestones) | Complete | `NotificationService.swift` |
| Haptics + audio tones + voice countdown | Complete | `FeedbackService.swift` |
| Swipe navigation between exercises | Complete | `SessionView.swift` |
| Calendar history view | Complete | `CalendarHistoryView.swift` |
| Data export/import (JSON) | Partial | `ExportImportService.swift` (Export/Import buttons are TODO in ProfileView) |

---

## Feature Evaluation

### Tier 1 — High Impact, Strong Fit

#### 1. HealthKit Integration
**What:** Write completed sessions as `HKWorkout` (type `.strengthTraining`) to Apple Health. Optionally read body weight for strength-to-weight ratios.

**Why it fits:**
- The app already records all the data HealthKit needs: duration (`startedAt`/`completedAt`), exercises, sets, reps, and weights (in `SyncSessionLog`)
- Session completion logic in `SessionViewModel.completeSession()` is already a natural hook point — it saves to history, posts to Strava, and ends the Live Activity, so adding a HealthKit write is a straightforward addition
- WeatherKit permission flow in `TB3WeatherService.swift` provides an existing pattern for requesting system permissions
- Complements (not replaces) the existing Strava integration — some users treat Apple Health as their single source of truth

**What it enables:**
- Completed workouts appear in Activity Rings and the Health app timeline
- Estimated calorie burn per strength session
- Body weight reading from Health could auto-populate a strength-to-bodyweight ratio (especially useful for Weighted Pull-up tracking, which already separates "added weight" from bodyweight)
- Third-party apps (like MyFitnessPal, fitness trackers) can see TB3 workouts

**Implementation scope:**
- HealthKit entitlement + `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
- New `HealthKitService` with `saveWorkout(session: SyncSessionLog)` method
- Call from `SessionViewModel.completeSession()` alongside existing Strava share
- Profile toggle: "Sync to Apple Health" (like the existing "Auto-Share Workouts" toggle for Strava)
- Optional: read `HKQuantityType.bodyMass` for dashboard stats

**Effort:** Medium — well-bounded, no backend changes needed

---

#### 2. Apple Watch Companion App
**What:** Minimal watchOS app for hands-free workout tracking during sessions.

**Why it fits:**
- The biggest UX friction point in the current app is physical: during heavy lifts, users must pick up their phone, unlock it, and tap "Complete Set." A watch button eliminates this entirely
- The existing `ActiveSessionState` model already serializes to JSON (it uses `UserDefaults` for crash persistence), making it transferable via Watch Connectivity
- `FeedbackService` already produces distinct haptic patterns for set complete, exercise complete, rest overtime, and session finish — these translate directly to the watch's Taptic Engine
- Live Activity already provides at-a-glance workout info on the lock screen; a Watch complication extends this to the wrist where it's genuinely useful mid-set

**What it shows on the watch:**
- Current exercise name + weight (from `ActiveSessionExercise`)
- Set progress: "Set 3/5" (from `SessionSet` array)
- Rest timer with overtime detection (from `TimerState`)
- "Complete Set" button — sends message to iPhone via `WCSession`
- Haptic tap when rest is over (replaces phone buzzing in your pocket)

**What it does NOT do (to limit scope):**
- No standalone mode (requires iPhone nearby)
- No onboarding, no 1RM entry, no template selection — all of that stays on the phone
- No independent data store — watch reads session state from the phone

**Implementation scope:**
- New watchOS target with WatchKit + Watch Connectivity
- `WatchSessionManager` on iOS side (sends `ActiveSessionState` on session start, state changes, and exercise navigation)
- Compact SwiftUI watch view: exercise label, weight, set dots, timer, "Complete Set" button
- Watch complications: next workout (from Shared Container / WidgetKit data), progress ring
- Bidirectional messaging: watch sends "completeSet" / "undo" actions back to iPhone

**Effort:** High — requires a new target, WatchKit layout, Watch Connectivity plumbing, and complication data providers. This is the single most impactful feature but also the largest build.

---

#### 3. Complete Export/Import Implementation
**What:** Wire up the existing `ExportImportService.swift` to the UI buttons in `ProfileView.swift` that are currently marked `// TODO: Phase 6`.

**Why it fits:**
- `ExportImportService.swift` already exists in the codebase with export/import logic
- The Profile UI already has "Export Data" and "Import Data" buttons — they just need to be connected
- The PRD specifies a 12-step validated import (already implemented in the web app and tested in `ValidationServiceTests`)
- Data resilience is a core PRD goal ("export/import to protect against iOS storage eviction")

**Effort:** Low — mostly wiring existing code to existing UI

---

### Tier 2 — Medium Impact, Good Fit

#### 4. Core Haptics — Richer Tactile Feedback
**What:** Replace basic `UIImpactFeedbackGenerator` calls with custom `CoreHaptics` patterns for distinct workout events.

**Why it fits:**
- `FeedbackService.swift` already defines 7 distinct feedback events (`setComplete`, `exerciseComplete`, `restComplete`, `sessionComplete`, `undo`, `error`, `swipeComplete`) with simple haptic calls
- The current implementation uses `UIImpactFeedbackGenerator` (light/medium) and `UINotificationFeedbackGenerator` — effective but generic
- CoreHaptics allows designing patterns that are physically distinguishable even when the phone is in a pocket or on a bench — critical during workouts

**Proposed patterns:**
- **Rest overtime approaching:** Escalating pulse pattern (frequency increases as rest timer approaches overtime) — users physically feel urgency without looking at the phone
- **Set complete:** Sharp double-tap (distinct from the single-tap exercise swipe)
- **Exercise complete:** Rising crescendo pattern (3 taps with increasing intensity)
- **Session complete:** Long satisfying buzz (celebration)

**Implementation scope:**
- New `HapticPatternProvider` that returns `CHHapticPattern` for each event
- Update `FeedbackService` to use `CHHapticEngine` when available, falling back to current `UIImpactFeedbackGenerator`
- Add escalating pattern to `timerTick()` when rest timer is within last 10 seconds

**Effort:** Low-Medium — the feedback events are already well-defined, this is enhancing their physical feel

---

#### 5. TipKit — Feature Discovery
**What:** Use Apple's TipKit framework for contextual in-app tips that teach users features they might not discover on their own.

**Why it fits:**
- The app has several non-obvious interactions: swipe left/right to navigate exercises, tap the timer to toggle rest/exercise phase, the percentage table in the Profile 1RM section
- New users complete onboarding and land on the Dashboard, but may not know about Chromecast, Spotify integration, Strava sharing, or Siri Shortcuts
- TipKit is lightweight (a few lines of code per tip) and integrates cleanly with SwiftUI

**Proposed tips:**
1. "Swipe left or right to switch exercises" — shown on first session, on the `SessionView`
2. "Connect Spotify for music controls during workouts" — shown in Profile when Spotify is not connected
3. "Say 'Hey Siri, start my workout' to jump straight in" — shown on Dashboard after first completed session
4. "Cast your workout to your TV" — shown in session view near the Cast button
5. "Set up Strava to auto-share completed workouts" — shown in Profile integrations section

**Effort:** Low — TipKit API is simple, tips are declarative

---

#### 6. Background App Refresh & BGTaskScheduler
**What:** Schedule periodic sync and widget refresh in the background.

**Why it fits:**
- Cloud sync currently only runs when the app is in the foreground (via `SyncCoordinator`)
- Widgets display stale data if the app hasn't been opened recently (they read from the shared App Group container, which is only refreshed on foreground)
- `BGTaskScheduler` could trigger a sync + widget reload on a periodic schedule (e.g., every 4 hours)

**Implementation scope:**
- Register a `BGAppRefreshTask` in the app delegate
- On trigger: run `SyncCoordinator.sync()` → update shared container → `WidgetCenter.shared.reloadAllTimelines()`
- Minimal battery impact since the actual sync is a single HTTPS round-trip to the API

**Effort:** Low

---

#### 7. Focus Filters — Workout Mode
**What:** Integrate with iOS Focus system so the app adapts when a "Workout" Focus is active.

**Why it fits:**
- App Intents are already implemented (`TB3/Intents/`), and Focus Filters use the same framework
- Could suppress non-essential UI elements during a workout (hide the tab bar, go full-screen session mode)
- Could auto-start Spotify polling when Workout Focus activates

**Effort:** Low — leverages existing AppIntents infrastructure

---

#### 8. Kilogram (kg) Unit Support
**What:** Add unit toggle (lb/kg) to the Profile settings and convert all weight displays and inputs accordingly.

**Why it fits:**
- The data model already has a `WeightUnit` enum (`Enums.swift:48-51`) with both `lb` and `kg` cases
- The `SyncProfile` already has a `unit` field (currently always "lb")
- The PRD explicitly notes: "All weights are in pounds (lb) for v1. The data model includes a `unit` field to support future kg conversion"
- This unlocks the app for international users

**Implementation scope:**
- Conversion helpers: `lbToKg()`, `kgToLb()`, `displayWeight(value:unit:)` applied at the view layer
- Plate inventory defaults for kg plates (20, 15, 10, 5, 2.5, 1.25 kg)
- Barbell weight default changes from 45 lb to 20 kg
- Rounding increment options: 2.5 kg / 5 kg (currently 2.5 lb / 5 lb)
- All stored data remains in lb internally — conversion happens at display and input boundaries only

**Effort:** Medium — touches many views but is mechanically straightforward

---

### Tier 3 — Lower Impact, Nice-to-Have

#### 9. StoreKit 2 — Monetization
**What:** In-app purchase framework for premium features if needed.

**Why it fits conditionally:**
- StoreKit 2 provides `SubscriptionStoreView` and `ProductView` that render natively in SwiftUI
- Could gate features like: advanced analytics, additional templates, cloud sync, Strava/Spotify integrations
- The current model is all-inclusive — monetization depends on the business decision

**Effort:** Medium — the framework is straightforward but defining what's free vs. premium is a product decision, not an engineering one

---

#### 10. Accessibility Enhancements
**What:** Comprehensive VoiceOver audit and Dynamic Type support review.

**Why it fits:**
- The PRD specifies WCAG 2.2 AA compliance, and the codebase already has some accessibility labels (e.g., `.accessibilityLabel("Program progress")` on the Dashboard)
- Session view has accessibility hints on the main action button ("Double tap to mark this set as complete")
- But there's room for improvement: plate display diagrams likely need descriptive labels, timer announcements for VoiceOver users, and Dynamic Type testing for large text sizes in the session view

**Implementation scope:**
- Audit all views with VoiceOver enabled
- Add `accessibilityLabel` / `accessibilityValue` to plate diagrams, timer display, set dots
- Test all views at the largest Dynamic Type size
- Add `accessibilityAdjustableAction` to weight/reps pickers for swipe-up/down adjustment

**Effort:** Low-Medium

---

#### 11. Session Notes / RPE Tracking
**What:** Allow users to add notes and a Rate of Perceived Exertion (RPE) score to each completed session.

**Why it fits:**
- `SyncSessionLog` already has a `notes: String` field (currently always empty string `""`)
- RPE (1-10 scale) is a standard strength training metric that helps track recovery and auto-regulate future sessions
- Could be collected on the session completion screen (a brief form before the session is saved)

**Implementation scope:**
- Add optional `rpe: Int?` field to `SyncSessionLog` (requires schema migration + backend sync update)
- Post-session sheet with notes text field and RPE slider (1-10)
- Display RPE in session history list and calendar view
- Include in Strava description if present

**Effort:** Medium — schema change ripples through sync layer

---

#### 12. Training Analytics Dashboard
**What:** Add a dedicated analytics tab or section showing training insights beyond the existing 1RM chart.

**Why it fits:**
- The app already stores rich session data: every set, rep, weight, duration, temperature, and timestamp
- Currently, the only analytics view is `MaxChartView` (1RM over time per lift)
- Users training for 6-12 weeks accumulate significant data that could surface patterns

**Possible analytics:**
- **Volume per session** (total sets x reps x weight) over time
- **Training frequency** (sessions per week, adherence to template schedule)
- **Rest time trends** (average rest between sets over time)
- **Completion rate** (completed vs partial sessions, percentage of sets completed)
- **Per-lift volume** breakdown (e.g., squat volume vs. bench volume)
- **Program comparison** (Operator cycle vs. previous Operator cycle)

**Implementation scope:**
- New `AnalyticsView` with SwiftUI Charts (already used in `MaxChartView`)
- Compute metrics from `sessionHistory` array — all data is already local
- No backend changes needed

**Effort:** Medium — data is available, this is primarily a UI/charting exercise

---

#### 13. iCloud Keychain / Passkeys for Auth
**What:** Support passkey authentication alongside the current email/password Cognito flow.

**Why it fits:**
- The current auth flow uses Cognito SRP (email + password), which works but adds friction
- Passkeys provide biometric authentication (Face ID / Touch ID) with no password to remember
- The auth infrastructure (`AuthService.swift`, `TokenManager.swift`) already handles token storage in the Keychain

**Caveat:** Requires backend Cognito configuration to support WebAuthn / passkeys. Not purely an iOS change.

**Effort:** High — spans iOS + backend + Cognito configuration

---

#### 14. Shortcuts Automation Triggers
**What:** Extend existing App Intents to support Shortcuts automation triggers (e.g., "When I arrive at the gym, start my workout").

**Why it fits:**
- Three App Intents already exist (`StartWorkoutIntent`, `NextWorkoutIntent`, `CurrentMaxesIntent`)
- Shortcuts automation can trigger intents based on location, time, NFC tag scan, or Focus activation
- Example: NFC tag on the gym locker → auto-launches today's session

**Effort:** Low — the intents exist; this is about documenting automation possibilities and potentially adding location-based parameters

---

### Not Recommended

| Feature | Reason |
|---|---|
| **CloudKit sync** | Already have a working AWS Cognito + DynamoDB sync backend. Adding CloudKit creates dual-sync complexity with no clear benefit. |
| **App Clips** | Users need the full app for ongoing tracking. A clip doesn't fit the use case — there's no "try before you install" scenario for a training tracker. |
| **Vision / CoreML** | No clear application. Form analysis from video is a different product category entirely. |
| **ARKit** | No practical use case for a rep/set tracker. |
| **CarPlay** | Workouts happen at the gym, not in the car. |

---

## Recommended Priority Order

Based on impact to users, alignment with existing architecture, and implementation feasibility:

| Priority | Feature | Impact | Effort | Rationale |
|---|---|---|---|---|
| 1 | Complete Export/Import (#3) | High | Low | Unfinished existing feature — buttons exist but are disconnected |
| 2 | HealthKit Integration (#1) | Very High | Medium | Most-requested iOS fitness app feature; data model is ready |
| 3 | Kilogram Unit Support (#8) | High | Medium | Unlocks international users; data model already supports it |
| 4 | Core Haptics (#4) | Medium | Low | Quick win — enhances gym UX where phone is often out of sight |
| 5 | TipKit (#5) | Medium | Low | Quick win — improves feature discoverability for new users |
| 6 | Background Sync (#6) | Medium | Low | Quick win — keeps widgets and data fresh |
| 7 | Training Analytics (#12) | Medium | Medium | Leverages existing data, adds retention value |
| 8 | Session Notes/RPE (#11) | Medium | Medium | Standard training feature, data field already exists |
| 9 | Accessibility Audit (#10) | Medium | Low-Medium | PRD compliance requirement |
| 10 | Apple Watch (#2) | Very High | High | Highest user impact but largest build — schedule after foundation features |
