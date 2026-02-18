// TB3 iOS — Profile ViewModel

import Foundation
import AVFoundation
import WidgetKit

@MainActor @Observable
final class ProfileViewModel {
    // 1RM entry
    var expandedLift: String?
    var liftWeight: String = ""
    var liftReps: String = ""

    // Import/export feedback
    var exportSuccess = false
    var importError: String?
    var importSuccess = false

    // Delete confirmation
    var showDeleteConfirm = false

    private let appState: AppState
    let dataStore: DataStore
    private let authService: AuthService
    private let syncCoordinator: SyncCoordinator

    init(appState: AppState, dataStore: DataStore, authService: AuthService, syncCoordinator: SyncCoordinator) {
        self.appState = appState
        self.dataStore = dataStore
        self.authService = authService
        self.syncCoordinator = syncCoordinator
    }

    // MARK: - 1RM Entry

    func toggleLift(_ liftName: String) {
        if expandedLift == liftName {
            expandedLift = nil
        } else {
            expandedLift = liftName
            // Pre-fill with last saved weight/reps
            if let current = appState.currentLifts.first(where: { $0.name == liftName }) {
                liftWeight = current.weight.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(current.weight))" : String(format: "%.1f", current.weight)
                liftReps = "\(current.reps)"
            } else {
                liftWeight = ""
                liftReps = ""
            }
        }
    }

    func save1RM(liftName: String) {
        guard let weight = Double(liftWeight), weight >= 1, weight <= 1500,
              let reps = Int(liftReps), reps >= 1, reps <= 15 else { return }

        let dateStr = Date.iso8601Now()
        let maxType = appState.profile.maxType
        let calculatedMax = OneRepMaxCalculator.calculateOneRepMax(weight: weight, reps: reps)
        let workingMax = maxType == "true"
            ? OneRepMaxCalculator.calculateTrainingMax(oneRepMax: calculatedMax)
            : calculatedMax

        let test = SyncOneRepMaxTest(
            id: Date.generateId(),
            date: dateStr,
            liftName: liftName,
            weight: weight,
            reps: reps,
            calculatedMax: calculatedMax,
            maxType: maxType,
            workingMax: workingMax,
            lastModified: dateStr
        )

        appState.maxTestHistory.append(test)
        dataStore.addMaxTest(test)
        appState.regenerateScheduleIfNeeded()

        // Refresh widgets (Lift PRs + Next Workout weights)
        WidgetCenter.shared.reloadAllTimelines()

        expandedLift = nil
        liftWeight = ""
        liftReps = ""
    }

    // MARK: - Profile Updates

    func updateMaxType(_ value: String) {
        appState.profile.maxType = value
        saveProfile()
        appState.regenerateScheduleIfNeeded()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateRounding(_ value: Double) {
        appState.profile.roundingIncrement = value
        saveProfile()
        appState.regenerateScheduleIfNeeded()
    }

    func updateBarbellWeight(_ text: String) {
        guard let weight = Double(text), weight >= 15, weight <= 100 else { return }
        appState.profile.barbellWeight = weight
        saveProfile()
        appState.regenerateScheduleIfNeeded()
    }

    func updateRestTimer(_ text: String) {
        guard let seconds = Int(text), seconds >= 0, seconds <= 600 else { return }
        appState.profile.restTimerDefault = seconds
        saveProfile()
    }

    func updateSoundMode(_ mode: String) {
        appState.profile.soundMode = mode
        saveProfile()
    }

    func updateVoice(_ enabled: Bool) {
        appState.profile.voiceAnnouncements = enabled
        saveProfile()
    }

    func updateVoiceName(_ name: String?) {
        appState.profile.voiceName = name
        saveProfile()
    }

    func updateWorkoutReminders(_ enabled: Bool, notificationService: NotificationService?) {
        guard let notificationService else { return }
        Task {
            if enabled {
                let granted = await notificationService.requestPermission()
                guard granted else { return }

                // Schedule with current next workout info
                if let program = appState.activeProgram,
                   let template = Templates.get(id: program.templateId),
                   let schedule = appState.computedSchedule {
                    let weekIndex = program.currentWeek - 1
                    let sessionIndex = program.currentSession - 1
                    if weekIndex >= 0, weekIndex < schedule.weeks.count,
                       sessionIndex >= 0, sessionIndex < schedule.weeks[weekIndex].sessions.count {
                        let session = schedule.weeks[weekIndex].sessions[sessionIndex]
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
                }
            } else {
                notificationService.cancelWorkoutReminders()
            }
            appState.profile.workoutRemindersEnabled = enabled
            saveProfile()
        }
    }

    func updateRestTimerAlerts(_ enabled: Bool, notificationService: NotificationService?) {
        guard let notificationService else { return }
        Task {
            if enabled {
                let granted = await notificationService.requestPermission()
                guard granted else { return }
            }
            appState.profile.restTimerAlertsEnabled = enabled
            saveProfile()
        }
    }

    private var previewSynthesizer = AVSpeechSynthesizer()

    func previewVoice(_ voiceName: String?) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Three, two, one, Go")
        utterance.rate = 0.55
        if let voiceName, let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == voiceName }) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        previewSynthesizer.speak(utterance)
    }

    // MARK: - Sync

    func syncNow() {
        syncCoordinator.syncNow()
    }

    // MARK: - Sign Out

    func signOut() async {
        await authService.signOut()
    }

    // MARK: - Delete All Data

    func deleteAllData() {
        dataStore.clearAllData()
        appState.activeProgram = nil
        appState.computedSchedule = nil
        appState.activeSession = nil
        appState.sessionHistory = []
        appState.maxTestHistory = []
        appState.isFirstLaunch = true
    }

    // MARK: - Private

    private func saveProfile() {
        let profile = dataStore.loadProfile()
        profile.apply(from: appState.profile)
        dataStore.saveProfile(profile)
    }
}
