import {
  ALL_TEMPLATES, OPERATOR, ZULU, FIGHTER, GLADIATOR,
  MASS_PROTOCOL, MASS_STRENGTH, GREY_MAN,
  ZULU_CLUSTER_PERCENTAGES, MASS_STRENGTH_DL_WEEKS,
  getTemplate, getTemplatesForDays,
} from './definitions';

describe('template definitions — structure', () => {
  it('has 7 templates total', () => {
    expect(ALL_TEMPLATES).toHaveLength(7);
  });

  it('Operator: 6 weeks, 3 sessions/week, hasSetRange, fixed lifts', () => {
    expect(OPERATOR.durationWeeks).toBe(6);
    expect(OPERATOR.sessionsPerWeek).toBe(3);
    expect(OPERATOR.hasSetRange).toBe(true);
    expect(OPERATOR.requiresLiftSelection).toBe(false);
    expect(OPERATOR.weeks).toHaveLength(6);
    expect(OPERATOR.sessionDefs).toHaveLength(3);
  });

  it('Operator session 3 has Deadlift instead of Weighted Pull-up', () => {
    const session3 = OPERATOR.sessionDefs.find((s) => s.sessionNumber === 3);
    expect(session3?.lifts).toContain('Deadlift');
    expect(session3?.lifts).not.toContain('Weighted Pull-up');
  });

  it('Zulu: 6 weeks, 4 sessions/week, requiresLiftSelection, A/B split', () => {
    expect(ZULU.durationWeeks).toBe(6);
    expect(ZULU.sessionsPerWeek).toBe(4);
    expect(ZULU.requiresLiftSelection).toBe(true);
    expect(ZULU.hasSetRange).toBe(false);
    expect(ZULU.liftSlots).toHaveLength(2);
    expect(ZULU.liftSlots![0].cluster).toBe('A');
    expect(ZULU.liftSlots![1].cluster).toBe('B');
  });

  it('Fighter: 6 weeks, 2 sessions/week, 2-3 lifts', () => {
    expect(FIGHTER.durationWeeks).toBe(6);
    expect(FIGHTER.sessionsPerWeek).toBe(2);
    expect(FIGHTER.requiresLiftSelection).toBe(true);
    expect(FIGHTER.hasSetRange).toBe(true);
    expect(FIGHTER.liftSlots![0].minLifts).toBe(2);
    expect(FIGHTER.liftSlots![0].maxLifts).toBe(3);
  });

  it('Gladiator: 6 weeks, 3 sessions/week, week 6 descending reps', () => {
    expect(GLADIATOR.durationWeeks).toBe(6);
    expect(GLADIATOR.sessionsPerWeek).toBe(3);
    const week6 = GLADIATOR.weeks.find((w) => w.weekNumber === 6);
    expect(week6?.repsPerSet).toEqual([3, 2, 1, 3, 2]);
    expect(week6?.percentage).toBe(95);
  });

  it('Mass Protocol: 6 weeks, 3 sessions/week, hideRestTimer', () => {
    expect(MASS_PROTOCOL.durationWeeks).toBe(6);
    expect(MASS_PROTOCOL.sessionsPerWeek).toBe(3);
    expect(MASS_PROTOCOL.hideRestTimer).toBe(true);
  });

  it('Mass Strength: 3 weeks, 4 sessions/week, session 4 is DL', () => {
    expect(MASS_STRENGTH.durationWeeks).toBe(3);
    expect(MASS_STRENGTH.sessionsPerWeek).toBe(4);
    expect(MASS_STRENGTH.requiresLiftSelection).toBe(false);
    const session4 = MASS_STRENGTH.sessionDefs.find((s) => s.sessionNumber === 4);
    expect(session4?.lifts).toEqual(['Deadlift']);
  });

  it('Grey Man: 12 weeks, 3 sessions/week', () => {
    expect(GREY_MAN.durationWeeks).toBe(12);
    expect(GREY_MAN.sessionsPerWeek).toBe(3);
    expect(GREY_MAN.weeks).toHaveLength(12);
  });

  it('Grey Man weeks 9 and 12 are at 95%', () => {
    const week9 = GREY_MAN.weeks.find((w) => w.weekNumber === 9);
    const week12 = GREY_MAN.weeks.find((w) => w.weekNumber === 12);
    expect(week9?.percentage).toBe(95);
    expect(week12?.percentage).toBe(95);
    expect(week9?.repsPerSet).toBe(1);
    expect(week12?.repsPerSet).toBe(1);
  });
});

describe('Zulu cluster percentages', () => {
  it('week 1: clusterOne=70, clusterTwo=75', () => {
    expect(ZULU_CLUSTER_PERCENTAGES[1]).toEqual({ clusterOne: 70, clusterTwo: 75 });
  });

  it('week 3: clusterOne=90, clusterTwo=90', () => {
    expect(ZULU_CLUSTER_PERCENTAGES[3]).toEqual({ clusterOne: 90, clusterTwo: 90 });
  });

  it('has entries for all 6 weeks', () => {
    for (let i = 1; i <= 6; i++) {
      expect(ZULU_CLUSTER_PERCENTAGES[i]).toBeDefined();
    }
  });
});

describe('Mass Strength DL weeks', () => {
  it('week 1: 4 sets of 5 reps', () => {
    expect(MASS_STRENGTH_DL_WEEKS[1]).toEqual({ sets: 4, reps: 5 });
  });

  it('week 3: 1 set of 3 reps', () => {
    expect(MASS_STRENGTH_DL_WEEKS[3]).toEqual({ sets: 1, reps: 3 });
  });
});

describe('getTemplate', () => {
  it('returns Operator for id "operator"', () => {
    expect(getTemplate('operator')).toBe(OPERATOR);
  });

  it('returns Grey Man for id "grey-man"', () => {
    expect(getTemplate('grey-man')).toBe(GREY_MAN);
  });

  it('returns undefined for unknown id', () => {
    expect(getTemplate('nonexistent' as any)).toBeUndefined();
  });
});

describe('getTemplatesForDays', () => {
  it('returns Fighter for 2 days', () => {
    const result = getTemplatesForDays(2);
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('fighter');
  });

  it('returns 4 templates for 3 days', () => {
    const result = getTemplatesForDays(3);
    expect(result).toHaveLength(4);
    const ids = result.map((t) => t.id);
    expect(ids).toContain('operator');
    expect(ids).toContain('gladiator');
    expect(ids).toContain('mass-protocol');
    expect(ids).toContain('grey-man');
  });

  it('returns Zulu for 4 days', () => {
    const result = getTemplatesForDays(4);
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('zulu');
  });

  it('returns all templates for other day counts', () => {
    expect(getTemplatesForDays(5)).toHaveLength(7);
    expect(getTemplatesForDays(1)).toHaveLength(7);
  });
});
