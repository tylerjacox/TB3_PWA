// TB3 iOS — Schedule Generator (mirrors templates/schedule.ts)
// Transforms template + lifts + settings into ComputedSchedule.

import Foundation

enum ScheduleGenerator {

    /// Generate a full computed schedule from program state
    static func generateSchedule(
        program: SyncActiveProgram,
        lifts: [DerivedLiftEntry],
        profile: SyncProfile
    ) -> ComputedSchedule {
        guard let templateId = TemplateId(rawValue: program.templateId),
              let template = Templates.get(id: templateId) else {
            return ComputedSchedule(
                computedAt: Date.iso8601Now(),
                sourceHash: "",
                weeks: []
            )
        }

        let liftMap = Dictionary(lifts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var weeks: [ComputedWeek] = []

        for weekDef in template.weeks {
            var sessions: [ComputedSession] = []

            for sessionDef in template.sessionDefs {
                // Determine lifts for this session
                let sessionLifts = resolveSessionLifts(
                    sessionDef: sessionDef,
                    template: template,
                    program: program
                )

                // Determine percentage for this session
                var pct = weekDef.percentage
                if template.id == .zulu {
                    if let zuluPcts = Templates.zuluClusterPercentages[weekDef.weekNumber] {
                        pct = sessionDef.sessionNumber <= 2 ? zuluPcts.clusterOne : zuluPcts.clusterTwo
                    }
                }

                // Determine sets/reps
                var setsRange = weekDef.setsRange
                var repsPerSet = weekDef.repsPerSet

                // Mass Strength deadlift day override
                if template.id == .massStrength && sessionDef.sessionNumber == 4 {
                    if let dlWeek = Templates.massStrengthDLWeeks[weekDef.weekNumber] {
                        setsRange = [dlWeek.sets, dlWeek.sets]
                        repsPerSet = .single(dlWeek.reps)
                    }
                }

                let exercises: [ComputedExercise] = sessionLifts.map { liftName in
                    guard let lift = liftMap[liftName] else {
                        return ComputedExercise(
                            liftName: liftName,
                            targetWeight: 0,
                            plateBreakdown: "Set 1RM for \(liftName)",
                            plates: [],
                            isBodyweight: liftName == LiftName.weightedPullUp.rawValue,
                            achievable: false
                        )
                    }

                    let roundingIncrement = profile.roundingIncrement
                    let targetWeight = OneRepMaxCalculator.calculatePercentageWeight(
                        workingMax: lift.workingMax,
                        percentage: pct,
                        roundingIncrement: roundingIncrement
                    )

                    let plateResult: PlateResult
                    if lift.isBodyweight {
                        let beltInventory = profile.plateInventoryBelt
                        plateResult = PlateCalculator.calculateBeltPlates(totalWeight: targetWeight, inventory: beltInventory)
                    } else {
                        let barbellInventory = profile.plateInventoryBarbell
                        plateResult = PlateCalculator.calculateBarbellPlates(
                            totalWeight: targetWeight,
                            barbellWeight: profile.barbellWeight,
                            inventory: barbellInventory
                        )
                    }

                    return ComputedExercise(
                        liftName: liftName,
                        targetWeight: targetWeight,
                        plateBreakdown: plateResult.displayText,
                        plates: plateResult.plates,
                        isBodyweight: lift.isBodyweight,
                        achievable: plateResult.achievable
                    )
                }

                sessions.append(ComputedSession(sessionNumber: sessionDef.sessionNumber, exercises: exercises))
            }

            weeks.append(ComputedWeek(
                weekNumber: weekDef.weekNumber,
                percentage: weekDef.percentage,
                setsRange: weekDef.setsRange,
                repsPerSet: weekDef.repsPerSet,
                sessions: sessions
            ))
        }

        return ComputedSchedule(
            computedAt: Date.iso8601Now(),
            sourceHash: computeSourceHash(program: program, lifts: lifts, profile: profile),
            weeks: weeks
        )
    }

    // MARK: - Resolve Session Lifts

    private static func resolveSessionLifts(
        sessionDef: SessionDef,
        template: TemplateDef,
        program: SyncActiveProgram
    ) -> [String] {
        if sessionDef.liftSource == .fixed, let lifts = sessionDef.lifts {
            return lifts
        }

        if sessionDef.liftSource == .cluster {
            return program.liftSelections["cluster"] ?? template.liftSlots?.first?.defaults ?? []
        }

        if sessionDef.liftSource == .a {
            return program.liftSelections["A"] ?? template.liftSlots?.first(where: { $0.cluster == "A" })?.defaults ?? []
        }

        if sessionDef.liftSource == .b {
            return program.liftSelections["B"] ?? template.liftSlots?.first(where: { $0.cluster == "B" })?.defaults ?? []
        }

        return sessionDef.lifts ?? []
    }

    // MARK: - Source Hash (staleness detection)

    static func computeSourceHash(
        program: SyncActiveProgram,
        lifts: [DerivedLiftEntry],
        profile: SyncProfile
    ) -> String {
        // Build a deterministic string from all inputs that affect the schedule
        var parts: [String] = []
        parts.append("t:\(program.templateId)")
        parts.append("ls:\(program.liftSelections.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.joined(separator: ","))" }.joined(separator: ";"))")
        parts.append("lifts:\(lifts.sorted(by: { $0.name < $1.name }).map { "\($0.name):\($0.workingMax)" }.joined(separator: ","))")
        parts.append("ri:\(profile.roundingIncrement)")
        parts.append("bw:\(profile.barbellWeight)")
        parts.append("mt:\(profile.maxType)")

        let data = parts.joined(separator: "|")

        // Simple hash matching the PWA's algorithm
        var hash: Int32 = 0
        for char in data.unicodeScalars {
            let chr = Int32(char.value)
            hash = ((hash << 5) &- hash) &+ chr
        }
        return String(hash, radix: 36)
    }
}
