# iOS Performance Analysis — TB3 Tactical Barbell

Comprehensive review of the iOS codebase identifying performance bottlenecks, inefficiencies, and areas for optimization. Issues are ordered by impact.

---

## HIGH IMPACT

### 1. `currentLifts` recomputes on every access

**File:** `ios/TB3/State/AppState.swift:50-82`

`currentLifts` is a computed `var` on `@Observable AppState`. Every access iterates all `maxTestHistory`, groups by lift, calculates 1RM for each, sorts, and returns a new array. This runs during every SwiftUI body evaluation that reads the property.

Callers include `ProfileView.liftRow` (per lift row), `DashboardView` (via schedule generation), `isScheduleStale()`, and `regenerateScheduleIfNeeded()`.

**Fix:** Cache as a stored property. Invalidate only when `maxTestHistory` or `profile.maxType` changes:

```swift
private var _currentLifts: [DerivedLiftEntry]?

var currentLifts: [DerivedLiftEntry] {
    if let cached = _currentLifts { return cached }
    let result = computeCurrentLifts()
    _currentLifts = result
    return result
}

// Call when maxTestHistory or profile.maxType changes:
func invalidateCurrentLifts() { _currentLifts = nil }
```

---

### 2. Tab content destroyed and recreated on every tab switch

**File:** `ios/TB3/TB3App.swift:161`

```swift
tabContent
    .id(selectedTab)  // <-- forces full view destruction/recreation
```

Using `.id(selectedTab)` forces SwiftUI to tear down the entire view hierarchy for the current tab and build the new one from scratch. `DashboardView`, `ProgramView` (with full schedule rendering), `HistoryView` (with calendar and lists), and `ProfileView` (with Form) are all recreated on every tab switch.

**Fix:** Use a `ZStack` with conditional `opacity` or `isHidden` to preserve view state:

```swift
ZStack {
    DashboardView(...)
        .opacity(selectedTab == 0 ? 1 : 0)
        .allowsHitTesting(selectedTab == 0)
    ProgramView(...)
        .opacity(selectedTab == 1 ? 1 : 0)
        .allowsHitTesting(selectedTab == 1)
    // ...
}
```

Or keep `.id()` but accept the tradeoff if the transition animation is a priority. The current approach sacrifices tab switch performance for visual polish.

---

### 3. Full data reload after every sync cycle

**File:** `ios/TB3/Services/SyncCoordinator.swift:117` → `ios/TB3/State/AppState.swift:109-121`

After every sync, `appState.reloadFromStore(dataStore)` re-fetches ALL profiles, programs, sessions, and max tests from SwiftData and re-maps them into Codable structs. This includes JSON-decoding every session's `exercisesData` blob. Runs every 5 minutes, on foreground, and on network reconnect.

```swift
func reloadFromStore(_ store: DataStore) {
    // Re-fetches EVERYTHING, even if sync changed nothing
    sessionHistory = store.loadSessionHistory().map { $0.toSyncSessionLog() }
    maxTestHistory = store.loadMaxTestHistory().map { $0.toSyncOneRepMaxTest() }
    regenerateScheduleIfNeeded()
}
```

**Fix:** Track what `applyRemoteChanges()` actually modified (return a changeset) and selectively update `AppState`:

```swift
struct SyncChangeset {
    var profileChanged: Bool
    var programChanged: Bool
    var newSessionIds: [String]
    var newMaxTestIds: [String]
}
```

---

### 4. `getLocalChanges()` fetches ALL records to filter by date

**File:** `ios/TB3/Services/DataStore.swift:85-128`

Every sync cycle loads the entire session history and max test history into memory, then filters in Swift:

```swift
let allSessions = loadSessionHistory()  // Fetches ALL
let newSessions = allSessions.filter { ... }  // Then filters in memory
```

**Fix:** Use SwiftData `#Predicate` to filter at the database level:

```swift
func loadSessionsSince(_ sinceDate: Date) -> [PersistedSessionLog] {
    let sinceStr = sinceDate.iso8601
    let descriptor = FetchDescriptor<PersistedSessionLog>(
        predicate: #Predicate { $0.lastModified > sinceStr },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
}
```

---

## MEDIUM IMPACT

### 5. `CalendarHistoryView.sessionsByDay` recomputed every render

**File:** `ios/TB3/Views/History/CalendarHistoryView.swift:16-24`

This computed property iterates ALL sessions, parses ISO8601 date strings, and builds a dictionary on every body evaluation. The calendar view's body is re-evaluated on day selection, month change, and any `sessions` array change.

```swift
private var sessionsByDay: [DateComponents: [SyncSessionLog]] {
    var dict: [DateComponents: [SyncSessionLog]] = [:]
    for session in sessions {
        guard let date = Date.fromISO8601(session.date) else { continue }
        // ...
    }
    return dict
}
```

**Fix:** Precompute and cache:

```swift
@State private var sessionsByDay: [DateComponents: [SyncSessionLog]] = [:]

// In .onAppear or .onChange(of: sessions):
func rebuildSessionsByDay() { ... }
```

---

### 6. `AVAudioEngine` created per tone sequence

**File:** `ios/TB3/Services/FeedbackService.swift:64-111`

Every haptic event with tones (set complete, exercise complete, rest complete, session complete) creates a brand new `AVAudioEngine`, attaches source nodes, and schedules playback via `DispatchQueue.main.asyncAfter`. The old engine reference is overwritten, but its scheduled blocks may still be running.

**Fix:** Create one `AVAudioEngine` at init, reuse it, and detach/reattach source nodes as needed:

```swift
private lazy var audioEngine: AVAudioEngine = {
    let engine = AVAudioEngine()
    // Configure once
    return engine
}()
```

---

### 7. Redundant sorting of session history in views

**File:** `ios/TB3/Views/History/HistoryView.swift:46`

```swift
ForEach(appState.sessionHistory.sorted(by: { $0.date > $1.date }), id: \.id) { ... }
```

`sessionHistory` is already fetched sorted by date descending from `DataStore.loadSessionHistory()`. This creates a redundant O(n log n) sort on every body evaluation.

**Fix:** Remove the `.sorted()` call since the data is already in the correct order, or ensure sort order is maintained when appending new entries.

---

### 8. `ISO8601DateFormatter()` instantiated in hot paths instead of using cached formatters

**Files:**
- `ios/TB3/Services/DataStore.swift:28, 40`
- `ios/TB3/Models/PersistedProfile.swift:24`
- `ios/TB3/Services/ExportImportService.swift:19`
- `ios/TB3/Templates/ScheduleGenerator.swift:17, 113`
- `ios/TB3/Networking/TokenManager.swift:38`

The codebase has cached formatters in `Date+Formatting.swift` but many locations create new `ISO8601DateFormatter()` instances instead:

```swift
// DataStore.swift:28 — called on every profile save
profile.lastModified = ISO8601DateFormatter().string(from: Date())
```

**Fix:** Replace all instances with the existing `Date.iso8601Now()` or `Date().iso8601`:

```swift
profile.lastModified = Date.iso8601Now()
```

---

### 9. Full in-memory session and max test history with unbounded growth

**File:** `ios/TB3/State/AppState.swift:39-40`

```swift
var sessionHistory: [SyncSessionLog] = []
var maxTestHistory: [SyncOneRepMaxTest] = []
```

All records are loaded at launch and held in memory indefinitely. For active users, this grows without bound. Each `SyncSessionLog` contains nested exercise arrays with set data.

**Fix:** Keep only derived/summary data in AppState. Load full records on demand from SwiftData when the user navigates to History views. Store only `currentLifts` (derived from latest max test per lift) instead of the full `maxTestHistory`.

---

### 10. `UIImpactFeedbackGenerator` allocated per haptic event

**File:** `ios/TB3/Services/FeedbackService.swift:34-54`

```swift
private func vibrate(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let generator = UIImpactFeedbackGenerator(style: style)  // New allocation each call
    generator.impactOccurred()
}
```

Apple's documentation recommends creating generators once, storing them, and calling `prepare()` before `impactOccurred()`.

**Fix:**

```swift
private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
private let notificationGenerator = UINotificationFeedbackGenerator()

func prepareHaptics() {
    lightGenerator.prepare()
    mediumGenerator.prepare()
}
```

---

### 11. `WidgetCenter.shared.reloadAllTimelines()` called too frequently

**Files:**
- `ios/TB3/ViewModels/SessionViewModel.swift:513` (session complete)
- `ios/TB3/ViewModels/ProfileViewModel.swift:81` (1RM save)
- `ios/TB3/ViewModels/ProfileViewModel.swift:94` (max type change)
- `ios/TB3/Services/SyncCoordinator.swift:120` (every sync cycle)

Every profile tweak and sync cycle triggers a full widget timeline reload for ALL widget types.

**Fix:** Use `reloadTimelines(ofKind:)` for targeted reloads, and debounce:

```swift
private var widgetReloadTask: Task<Void, Never>?

func scheduleWidgetReload(kinds: [String]) {
    widgetReloadTask?.cancel()
    widgetReloadTask = Task {
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
```

---

### 12. `PersistedProfile` plate inventory decoded from JSON on every property access

**File:** `ios/TB3/Models/PersistedProfile.swift:32-39`

```swift
var plateInventoryBarbell: PlateInventory {
    get { (try? JSONDecoder().decode(PlateInventory.self, from: plateInventoryBarbellData)) ?? DEFAULT_PLATE_INVENTORY_BARBELL }
    set { plateInventoryBarbellData = (try? JSONEncoder().encode(newValue)) ?? Data() }
}
```

Every read of `plateInventoryBarbell` creates a new `JSONDecoder` and deserializes. During schedule generation, this is accessed per exercise.

**Fix:** Cache decoded values in transient (non-persisted) properties, or decode once when the profile is loaded.

---

## LOW IMPACT

### 13. `SessionViewModel` recreated on every session presentation

**File:** `ios/TB3/TB3App.swift:92-103`

```swift
.fullScreenCover(isPresented: ...) {
    SessionView(vm: SessionViewModel(  // New instance every presentation
        appState: appState, dataStore: dataStore, ...
    ))
}
```

**Fix:** Store the `SessionViewModel` in `@State` and reuse it, resetting state when a new session begins.

---

### 14. `VoicePickerRow.englishVoices` scans all system voices per render

**File:** `ios/TB3/Views/Profile/ProfileView.swift:572-586`

`AVSpeechSynthesisVoice.speechVoices()` returns potentially hundreds of voices and is filtered/sorted/mapped on every render.

**Fix:** Cache as a static property since the voice list doesn't change during app runtime.

---

### 15. `SpotifyNowPlaying` struct allocated even when unchanged

**File:** `ios/TB3/Services/SpotifyService.swift:232-244`

Every 10-second poll constructs a new `SpotifyNowPlaying` even when the same track is playing, just to compare it against the existing value.

**Fix:** Compare raw parsed values before constructing the struct:

```swift
if newTrackId == spotifyState.nowPlaying?.trackId &&
   newIsPlaying == spotifyState.nowPlaying?.isPlaying {
    return  // Skip allocation
}
```

---

### 16. `CastService` rebuilds full JSON payload every 5 seconds during active timer

**File:** `ios/TB3/Services/CastService.swift:88-107, 109-187`

The periodic sync timer calls `sendMessageImmediate()` every 5 seconds, which iterates all exercises, builds exercise summaries, constructs a dictionary, and serializes to JSON — even when only `elapsedMs` changed.

**Fix:** Cache the static parts of the payload and only update dynamic fields (timer elapsed, overtime status).

---

### 17. `DateFormatter` instances in `Date+Formatting.swift` not marked `nonisolated(unsafe)`

**File:** `ios/TB3/Extensions/Date+Formatting.swift:18-30`

The `ISO8601DateFormatter` instances are correctly marked `nonisolated(unsafe)`, but `shortDisplayFormatter` and `fullDisplayFormatter` are plain `let` constants. `DateFormatter` is not thread-safe. If accessed from a background thread (e.g., widget timeline provider), this could crash.

**Fix:** Mark with `nonisolated(unsafe)` or use `@Sendable`-safe alternatives.

---

### 18. `TB3WeatherService` creates a new `CLLocationManager` per session

**File:** `ios/TB3/ViewModels/SessionViewModel.swift:360-368`

```swift
let weatherService = TB3WeatherService()  // New CLLocationManager each time
```

**Fix:** Inject a single `TB3WeatherService` instance via the app setup, or make it a singleton.

---

### 19. `ProgramView.scheduleView` renders all weeks at once in a `ScrollView`

**File:** `ios/TB3/Views/Program/ProgramView.swift:91-101`

All weeks of the program schedule are rendered simultaneously inside a `ScrollView`. For a 12-week program, this means 12 `WeekScheduleView` instances with all their sessions and exercises are built upfront.

**Fix:** Use `LazyVStack` instead of `VStack` inside the `ScrollView` to defer rendering of off-screen weeks:

```swift
ScrollView {
    LazyVStack(spacing: 20) {
        // ...
    }
}
```

---

### 20. Session sets filtered repeatedly by `exerciseIndex`

**File:** `ios/TB3/ViewModels/SessionViewModel.swift:67-68`

```swift
var currentSets: [SessionSet] {
    guard let session else { return [] }
    return session.sets.filter { $0.exerciseIndex == session.currentExerciseIndex }
}
```

`currentSets` is a computed property accessed by `completedSetsCount`, `nextSetNumber`, `allSetsComplete`, and the view. Each access re-filters the full sets array.

Similarly, `LiveActivityService.buildContentState()` and `CastService.sendMessageImmediate()` also filter sets by exercise index.

**Fix:** Cache the filtered sets when `currentExerciseIndex` changes rather than re-filtering on every access.

---

## Summary

| Priority | Count | Key Theme |
|----------|-------|-----------|
| High | 4 | Redundant data loading, computed property recomputation, view recreation |
| Medium | 8 | Formatter allocation, in-memory growth, audio engine churn, widget reload spam |
| Low | 8 | Object allocation, JSON re-serialization, view rendering |

The highest-impact wins are:
1. Caching `currentLifts` instead of recomputing
2. Preserving tab views across switches (or accepting the tradeoff)
3. Selective reload after sync instead of full re-fetch
4. Using SwiftData predicates for sync filtering
