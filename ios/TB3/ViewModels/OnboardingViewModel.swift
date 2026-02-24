// TB3 iOS — Onboarding ViewModel

import Foundation

@MainActor @Observable
final class OnboardingViewModel {
    var step = 1 // 1-4

    // Step 1: Lift entries
    struct LiftInput {
        var weight: String = ""
        var reps: String = ""
    }
    var liftInputs: [String: LiftInput] = {
        var inputs: [String: LiftInput] = [:]
        for lift in LiftName.allCases {
            inputs[lift.rawValue] = LiftInput()
        }
        return inputs
    }()

    // Step 2: Template selection + lift selection
    var dayFilter: Int? = nil
    var selectedTemplateId: String?
    var liftSelections: [String: [String]] = [:]

    // Step 3: Preview
    var previewSchedule: ComputedSchedule?

    // Step 4: Start date
    var startDate = Date()

    private let appState: AppState
    private let dataStore: DataStore

    init(appState: AppState, dataStore: DataStore) {
        self.appState = appState
        self.dataStore = dataStore
    }

    var selectedTemplate: TemplateDef? {
        guard let id = selectedTemplateId else { return nil }
        return Templates.get(id: id)
    }

    var filteredTemplates: [TemplateDef] {
        guard let days = dayFilter else { return Templates.all }
        return Templates.getForDays(days)
    }

    var canContinue: Bool {
        switch step {
        case 1: return true // lifts are optional
        case 2: return selectedTemplateId != nil
        case 3: return true
        case 4: return true
        default: return false
        }
    }

    // MARK: - Navigation

    func next() {
        switch step {
        case 1:
            saveLiftInputs()
            step = 2
        case 2:
            step = 3
            generatePreview()
        case 3:
            step = 4
        case 4:
            finish()
        default:
            break
        }
    }

    func back() {
        if step > 1 { step -= 1 }
    }

    // MARK: - Step 1: Save Lifts

    private func saveLiftInputs() {
        let dateStr = Date.iso8601Now()

        for (liftName, input) in liftInputs {
            guard let weight = Double(input.weight), weight >= 1, weight <= 1500,
                  let reps = Int(input.reps), reps >= 1, reps <= 15 else { continue }

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
        }
        appState.recomputeCurrentLifts()
    }

    // MARK: - Step 2: Lift Selection

    func toggleLift(slotLabel: String, liftName: String, minLifts: Int, maxLifts: Int) {
        var current = liftSelections[slotLabel] ?? []
        if current.contains(liftName) {
            if current.count > minLifts {
                current.removeAll { $0 == liftName }
            }
        } else {
            if current.count < maxLifts {
                current.append(liftName)
            }
        }
        liftSelections[slotLabel] = current
    }

    func isLiftSelected(_ liftName: String, slotLabel: String) -> Bool {
        liftSelections[slotLabel]?.contains(liftName) ?? false
    }

    // MARK: - Step 3: Preview

    private func generatePreview() {
        guard let template = selectedTemplate else { return }

        let resolvedSelections = resolveLiftSelections(template: template)

        let program = SyncActiveProgram(
            templateId: template.id.rawValue,
            startDate: startDate.iso8601,
            currentWeek: 1,
            currentSession: 1,
            liftSelections: resolvedSelections,
            lastModified: Date.iso8601Now()
        )

        previewSchedule = ScheduleGenerator.generateSchedule(
            program: program,
            lifts: appState.currentLifts,
            profile: appState.profile
        )
    }

    // MARK: - Step 4: Finish

    private func finish() {
        guard let template = selectedTemplate else { return }

        let resolvedSelections = resolveLiftSelections(template: template)
        let dateStr = startDate.iso8601

        let program = dataStore.createActiveProgram(
            templateId: template.id.rawValue,
            startDate: dateStr,
            liftSelections: resolvedSelections
        )

        appState.activeProgram = program.toSyncActiveProgram()
        appState.isFirstLaunch = false
        appState.regenerateScheduleIfNeeded()
    }

    // MARK: - Helpers

    private func resolveLiftSelections(template: TemplateDef) -> [String: [String]] {
        var resolved: [String: [String]] = [:]
        guard let slots = template.liftSlots else { return resolved }
        for slot in slots {
            if let userSelection = liftSelections[slot.cluster], !userSelection.isEmpty {
                resolved[slot.cluster] = userSelection
            } else {
                resolved[slot.cluster] = slot.defaults
            }
        }
        return resolved
    }
}
