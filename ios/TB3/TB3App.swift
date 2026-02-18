// TB3 iOS — App Entry Point (mirrors main.tsx + app.tsx)

import SwiftUI
import SwiftData

@main
struct TB3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var appState = AppState()

    let sharedModelContainer: ModelContainer

    init() {
        // Navigation bar: TB3 dark theme (used by Profile NavigationStack for push navigation)
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color.tb3Background)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance

        // Migrate existing SwiftData store to shared App Group container (one-time)
        SharedContainer.migrateIfNeeded()

        // Create shared ModelContainer for App Group (widgets + main app share data)
        do {
            sharedModelContainer = try SharedContainer.makeModelContainer()
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootView: View {
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase

    @State private var dataStore: DataStore?
    @State private var authService: AuthService?
    @State private var syncCoordinator: SyncCoordinator?
    @State private var feedbackService = FeedbackService()
    @State private var liveActivityService = LiveActivityService()
    @State private var castService: CastService?
    @State private var castAdapter: GCKCastSessionAdapter?
    @State private var stravaService: StravaService?
    @State private var notificationService = NotificationService()
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            Color.tb3Background.ignoresSafeArea()

            if appState.isLoading {
                LoadingView()
            } else if !appState.authState.isAuthenticated {
                if let authService {
                    AuthFlowView(authService: authService)
                } else {
                    LoadingView()
                }
            } else if appState.isFirstLaunch {
                if let dataStore {
                    OnboardingContainerView(appState: appState, dataStore: dataStore)
                } else {
                    LoadingView()
                }
            } else {
                mainTabView
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.isSessionPresented },
            set: { appState.isSessionPresented = $0 }
        )) {
            if let dataStore {
                SessionView(vm: SessionViewModel(
                    appState: appState,
                    dataStore: dataStore,
                    feedback: feedbackService,
                    castService: castService,
                    stravaService: stravaService,
                    liveActivityService: liveActivityService,
                    notificationService: notificationService
                ))
                .environment(appState)
            }
        }
        .tint(Color.tb3Accent)
        .preferredColorScheme(.dark)
        .task { await setup() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                syncCoordinator?.onForeground()
                handleIntentFlags()
                // Cancel rest timer notification on return to foreground
                if appState.profile.restTimerAlertsEnabled {
                    notificationService.cancelRestTimerAlert()
                }
            case .background:
                // Schedule rest timer notification if in rest phase
                if appState.profile.restTimerAlertsEnabled,
                   let session = appState.activeSession,
                   let timer = session.timerState,
                   timer.phase == .rest,
                   let restDuration = timer.restDurationSeconds {
                    notificationService.scheduleRestTimerAlert(
                        restDurationSeconds: restDuration,
                        timerStartedAtMs: timer.startedAt
                    )
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tb3IntentFired)) { _ in
            // Intent's perform() posts this AFTER setting UserDefaults flags,
            // solving the timing race where scenePhase fires before flags are set.
            handleIntentFlags()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tb3NotificationTapped)) { _ in
            if appState.activeSession != nil {
                appState.isSessionPresented = true
            }
        }
        .onChange(of: appState.profile.soundMode) { _, _ in configureFeedback() }
        .onChange(of: appState.profile.voiceAnnouncements) { _, _ in configureFeedback() }
        .onChange(of: appState.profile.voiceName) { _, _ in configureFeedback() }
        .onChange(of: appState.castState.connected) { _, _ in configureFeedback() }
        .onChange(of: appState.activeSession) { oldVal, newVal in
            // Send idle message when workout ends
            if newVal == nil && oldVal != nil {
                castService?.sendSessionState(nil)
                liveActivityService.endActivity()
            }
        }
    }

    // MARK: - Main Tab View

    private var mainTabView: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.easeInOut(duration: 0.15), value: selectedTab)

            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            DashboardView(
                onNavigateToProgram: { selectedTab = 1 },
                onNavigateToProfile: { selectedTab = 3 },
                onStartWorkout: { exercises, week, program in
                    if let dataStore {
                        let sessionVM = SessionViewModel(appState: appState, dataStore: dataStore, feedback: feedbackService, castService: castService, stravaService: stravaService, liveActivityService: liveActivityService, notificationService: notificationService)
                        sessionVM.startSession(exercises: exercises, week: week, program: program)
                    }
                }
            )
        case 1:
            if let dataStore {
                ProgramView(dataStore: dataStore)
            }
        case 2:
            HistoryView(stravaService: stravaService)
        case 3:
            if let dataStore, let authService, let syncCoordinator {
                ProfileView(vm: ProfileViewModel(
                    appState: appState,
                    dataStore: dataStore,
                    authService: authService,
                    syncCoordinator: syncCoordinator
                ), stravaService: stravaService, notificationService: notificationService)
            }
        default:
            EmptyView()
        }
    }

    private func configureFeedback() {
        feedbackService.configure(
            soundMode: appState.profile.soundMode,
            voiceEnabled: appState.profile.voiceAnnouncements,
            voiceName: appState.profile.voiceName,
            castConnected: appState.castState.connected
        )
    }

    // MARK: - Setup

    private func setup() async {
        let store = DataStore(modelContext: modelContext)
        let tokenManager = TokenManager()
        let auth = AuthService(authState: appState.authState)
        let apiClient = APIClient(tokenManager: tokenManager)
        let syncService = SyncService(apiClient: apiClient)
        let coordinator = SyncCoordinator(
            syncService: syncService,
            dataStore: store,
            authState: appState.authState,
            syncState: appState.syncState,
            appState: appState
        )

        self.dataStore = store
        self.authService = auth
        self.syncCoordinator = coordinator

        // Load data from SwiftData
        appState.loadInitialData(store)

        // Restart Live Activity for crash-recovered session
        if let activeSession = appState.activeSession {
            liveActivityService.startActivity(session: activeSession)
        }

        // Configure feedback from profile settings
        configureFeedback()

        // Cast setup
        let cast = CastService(castState: appState.castState)
        let adapter = GCKCastSessionAdapter(castService: cast, castState: appState.castState)
        adapter.onRequestSendState = { [weak cast] in
            cast?.sendSessionStateImmediate(appState.activeSession)
        }
        adapter.start()
        self.castService = cast
        self.castAdapter = adapter

        // Strava setup
        let stravaTokenManager = StravaTokenManager()
        let strava = StravaService(stravaState: appState.stravaState, tokenManager: stravaTokenManager)
        await strava.restoreConnection()
        self.stravaService = strava

        // Initialize auth (check stored tokens, refresh)
        await auth.initAuth()

        // Start periodic sync if authenticated
        if appState.authState.isAuthenticated {
            coordinator.start()
            await coordinator.performSync()
        }

        // Register App Shortcuts with Siri
        TB3Shortcuts.updateAppShortcutParameters()

        // Notifications: check authorization and reschedule reminders if enabled
        await notificationService.checkAuthorization()
        if appState.profile.workoutRemindersEnabled {
            scheduleWorkoutRemindersFromCurrentProgram()
        }

        // Check for Siri intent flags (cold launch from shortcut)
        handleIntentFlags()
    }

    // MARK: - Notification Helpers

    private func scheduleWorkoutRemindersFromCurrentProgram() {
        guard let program = appState.activeProgram,
              let template = Templates.get(id: program.templateId),
              let schedule = appState.computedSchedule else {
            notificationService.cancelWorkoutReminders()
            return
        }

        let weekIndex = program.currentWeek - 1
        let sessionIndex = program.currentSession - 1
        guard weekIndex >= 0, weekIndex < schedule.weeks.count else {
            notificationService.cancelWorkoutReminders()
            return
        }
        let week = schedule.weeks[weekIndex]
        guard sessionIndex >= 0, sessionIndex < week.sessions.count else {
            notificationService.cancelWorkoutReminders()
            return
        }
        let session = week.sessions[sessionIndex]
        let exerciseNames = session.exercises.map {
            LiftName(rawValue: $0.liftName)?.displayName ?? $0.liftName
        }

        notificationService.scheduleWorkoutReminders(
            templateName: template.name,
            weekNumber: program.currentWeek,
            sessionNumber: program.currentSession,
            exercises: exerciseNames
        )
    }

    // MARK: - App Intent Flag Handling

    private func handleIntentFlags() {
        // Start new workout from Siri intent
        if UserDefaults.standard.bool(forKey: "tb3_intent_start_workout") {
            UserDefaults.standard.removeObject(forKey: "tb3_intent_start_workout")

            guard let dataStore,
                  let program = appState.activeProgram,
                  let schedule = appState.computedSchedule,
                  appState.activeSession == nil else { return }

            let weekIndex = program.currentWeek - 1
            let sessionIndex = program.currentSession - 1
            guard weekIndex >= 0, weekIndex < schedule.weeks.count else { return }
            let week = schedule.weeks[weekIndex]
            guard sessionIndex >= 0, sessionIndex < week.sessions.count else { return }
            let session = week.sessions[sessionIndex]

            let sessionVM = SessionViewModel(
                appState: appState,
                dataStore: dataStore,
                feedback: feedbackService,
                castService: castService,
                stravaService: stravaService,
                liveActivityService: liveActivityService,
                notificationService: notificationService
            )
            sessionVM.startSession(exercises: session.exercises, week: week, program: program)
        }

        // Resume existing workout from Siri intent
        if UserDefaults.standard.bool(forKey: "tb3_intent_resume_session") {
            UserDefaults.standard.removeObject(forKey: "tb3_intent_resume_session")
            if appState.activeSession != nil {
                appState.isSessionPresented = true
            }
        }
    }
}
