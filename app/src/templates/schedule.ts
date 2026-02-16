// Schedule Generator — transforms template + lifts + settings into ComputedSchedule
import type {
  ComputedSchedule, ComputedWeek, ComputedSession, ComputedExercise,
  ActiveProgram, DerivedLiftEntry, UserProfile,
} from '../types';
import type { TemplateDef } from './definitions';
import {
  getTemplate, ZULU_CLUSTER_PERCENTAGES, MASS_STRENGTH_DL_WEEKS,
} from './definitions';
import { calculatePercentageWeight } from '../calculators/oneRepMax';
import { calculateBarbellPlates, calculateBeltPlates } from '../calculators/plates';

export function generateSchedule(
  program: ActiveProgram,
  lifts: DerivedLiftEntry[],
  profile: UserProfile,
): ComputedSchedule {
  const template = getTemplate(program.templateId);
  if (!template) throw new Error(`Unknown template: ${program.templateId}`);

  const liftMap = new Map(lifts.map((l) => [l.name, l]));
  const weeks: ComputedWeek[] = [];

  for (const weekDef of template.weeks) {
    const sessions: ComputedSession[] = [];

    for (const sessionDef of template.sessionDefs) {
      // Determine lifts for this session
      const sessionLifts = resolveSessionLifts(sessionDef, template, program);

      // Determine percentage for this session
      let pct = weekDef.percentage;
      if (template.id === 'zulu') {
        const zuluPcts = ZULU_CLUSTER_PERCENTAGES[weekDef.weekNumber];
        if (zuluPcts) {
          // Sessions 1,2 = Cluster One; Sessions 3,4 = Cluster Two
          pct = sessionDef.sessionNumber <= 2 ? zuluPcts.clusterOne : zuluPcts.clusterTwo;
        }
      }

      // Determine sets/reps
      let setsRange = weekDef.setsRange;
      let repsPerSet = weekDef.repsPerSet;

      // Mass Strength deadlift day override
      if (template.id === 'mass-strength' && sessionDef.sessionNumber === 4) {
        const dlWeek = MASS_STRENGTH_DL_WEEKS[weekDef.weekNumber];
        if (dlWeek) {
          setsRange = [dlWeek.sets, dlWeek.sets];
          repsPerSet = dlWeek.reps;
        }
      }

      const exercises: ComputedExercise[] = sessionLifts.map((liftName) => {
        const lift = liftMap.get(liftName);
        if (!lift) {
          return {
            liftName,
            targetWeight: 0,
            plateBreakdown: `Set 1RM for ${liftName}`,
            plateBreakdownPerSide: [],
            achievable: false,
          };
        }

        const targetWeight = calculatePercentageWeight(
          lift.workingMax,
          pct,
          profile.roundingIncrement,
        );

        const plateResult = lift.isBodyweight
          ? calculateBeltPlates(targetWeight, profile.plateInventoryBelt)
          : calculateBarbellPlates(targetWeight, profile.barbellWeight, profile.plateInventoryBarbell);

        return {
          liftName,
          targetWeight,
          plateBreakdown: plateResult.displayText,
          plateBreakdownPerSide: plateResult.plates,
          achievable: plateResult.achievable,
        };
      });

      sessions.push({
        sessionNumber: sessionDef.sessionNumber,
        exercises,
      });
    }

    weeks.push({
      weekNumber: weekDef.weekNumber,
      percentage: weekDef.percentage,
      setsRange: weekDef.setsRange,
      repsPerSet: weekDef.repsPerSet,
      sessions,
    });
  }

  return {
    computedAt: new Date().toISOString(),
    sourceHash: computeSourceHash(program, lifts, profile),
    weeks,
  };
}

function resolveSessionLifts(
  sessionDef: TemplateDef['sessionDefs'][0],
  template: TemplateDef,
  program: ActiveProgram,
): string[] {
  if (sessionDef.liftSource === 'fixed' && sessionDef.lifts) {
    return sessionDef.lifts;
  }

  if (sessionDef.liftSource === 'cluster') {
    return program.liftSelections['cluster'] || template.liftSlots?.[0]?.defaults || [];
  }

  if (sessionDef.liftSource === 'A') {
    return program.liftSelections['A'] || template.liftSlots?.find((s) => s.cluster === 'A')?.defaults || [];
  }

  if (sessionDef.liftSource === 'B') {
    return program.liftSelections['B'] || template.liftSlots?.find((s) => s.cluster === 'B')?.defaults || [];
  }

  return sessionDef.lifts || [];
}

export function computeSourceHash(
  program: ActiveProgram,
  lifts: DerivedLiftEntry[],
  profile: UserProfile,
): string {
  const template = getTemplate(program.templateId);
  const data = JSON.stringify({
    templateId: program.templateId,
    liftSelections: program.liftSelections,
    lifts: lifts.map((l) => ({ name: l.name, workingMax: l.workingMax })),
    roundingIncrement: profile.roundingIncrement,
    barbellWeight: profile.barbellWeight,
    maxType: profile.maxType,
    plateInventoryBarbell: profile.plateInventoryBarbell,
    plateInventoryBelt: profile.plateInventoryBelt,
    // Include template structure so definition changes force recompute
    templateVersion: template ? {
      sessionsPerWeek: template.sessionsPerWeek,
      durationWeeks: template.durationWeeks,
      sessionDefs: template.sessionDefs.map((s) => ({ n: s.sessionNumber, lifts: s.lifts, src: s.liftSource })),
      weeks: template.weeks.map((w) => ({ pct: w.percentage, sets: w.setsRange, reps: w.repsPerSet })),
    } : null,
  });
  // Simple hash
  let hash = 0;
  for (let i = 0; i < data.length; i++) {
    const chr = data.charCodeAt(i);
    hash = ((hash << 5) - hash) + chr;
    hash |= 0;
  }
  return hash.toString(36);
}
