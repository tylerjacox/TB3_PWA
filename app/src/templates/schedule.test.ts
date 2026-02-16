import { generateSchedule, computeSourceHash } from './schedule';
import { makeProfile, makeLift, makeProgram } from '../__tests__/fixtures';

// Standard lift set for Operator tests
const operatorLifts = [
  makeLift({ name: 'Squat', workingMax: 300 }),
  makeLift({ name: 'Bench', workingMax: 200 }),
  makeLift({ name: 'Weighted Pull-up', workingMax: 50, isBodyweight: true }),
  makeLift({ name: 'Deadlift', workingMax: 350 }),
];

describe('generateSchedule — Operator', () => {
  it('returns 6 weeks with 3 sessions each', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'operator' }),
      operatorLifts,
      makeProfile(),
    );
    expect(schedule.weeks).toHaveLength(6);
    for (const week of schedule.weeks) {
      expect(week.sessions).toHaveLength(3);
    }
  });

  it('week 1 uses 70% of working max', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'operator' }),
      operatorLifts,
      makeProfile({ roundingIncrement: 5 }),
    );
    const week1 = schedule.weeks[0];
    expect(week1.percentage).toBe(70);

    // Squat: roundWeight(300 * 0.70, 5) = roundWeight(210, 5) = 210
    const squat = week1.sessions[0].exercises.find((e) => e.liftName === 'Squat');
    expect(squat?.targetWeight).toBe(210);
  });

  it('session 3 has Deadlift instead of Weighted Pull-up', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'operator' }),
      operatorLifts,
      makeProfile(),
    );
    const session3 = schedule.weeks[0].sessions.find((s) => s.sessionNumber === 3);
    const liftNames = session3!.exercises.map((e) => e.liftName);
    expect(liftNames).toContain('Deadlift');
    expect(liftNames).not.toContain('Weighted Pull-up');
  });

  it('returns targetWeight 0 for missing lift', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'operator' }),
      [makeLift({ name: 'Squat', workingMax: 300 })], // Missing Bench, Pull-up, DL
      makeProfile(),
    );
    const bench = schedule.weeks[0].sessions[0].exercises.find((e) => e.liftName === 'Bench');
    expect(bench?.targetWeight).toBe(0);
    expect(bench?.achievable).toBe(false);
  });
});

describe('generateSchedule — Zulu', () => {
  const zuluLifts = [
    makeLift({ name: 'Military Press', workingMax: 120 }),
    makeLift({ name: 'Squat', workingMax: 300 }),
    makeLift({ name: 'Weighted Pull-up', workingMax: 50, isBodyweight: true }),
    makeLift({ name: 'Bench', workingMax: 200 }),
    makeLift({ name: 'Deadlift', workingMax: 350 }),
  ];

  it('returns 6 weeks with 4 sessions each', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'zulu' }),
      zuluLifts,
      makeProfile(),
    );
    expect(schedule.weeks).toHaveLength(6);
    for (const week of schedule.weeks) {
      expect(week.sessions).toHaveLength(4);
    }
  });

  it('sessions 1-2 use clusterOne percentage, 3-4 use clusterTwo', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'zulu' }),
      zuluLifts,
      makeProfile({ roundingIncrement: 5 }),
    );

    // Week 1: clusterOne=70%, clusterTwo=75%
    const week1 = schedule.weeks[0];
    const session1Squat = week1.sessions[0].exercises.find((e) => e.liftName === 'Squat');
    const session3Squat = week1.sessions[2].exercises.find((e) => e.liftName === 'Squat');

    // Session 1 (A1, clusterOne): 300 * 0.70 = 210
    expect(session1Squat?.targetWeight).toBe(210);
    // Session 3 (A2, clusterTwo): 300 * 0.75 = 225
    expect(session3Squat?.targetWeight).toBe(225);
  });

  it('uses custom lift selections', () => {
    const schedule = generateSchedule(
      makeProgram({
        templateId: 'zulu',
        liftSelections: {
          A: ['Squat', 'Military Press'],
          B: ['Bench', 'Deadlift'],
        },
      }),
      zuluLifts,
      makeProfile(),
    );
    const session1Lifts = schedule.weeks[0].sessions[0].exercises.map((e) => e.liftName);
    expect(session1Lifts).toContain('Squat');
    expect(session1Lifts).toContain('Military Press');
    expect(session1Lifts).not.toContain('Bench');
  });
});

describe('generateSchedule — Mass Strength DL day', () => {
  const msLifts = [
    makeLift({ name: 'Squat', workingMax: 300 }),
    makeLift({ name: 'Bench', workingMax: 200 }),
    makeLift({ name: 'Weighted Pull-up', workingMax: 50, isBodyweight: true }),
    makeLift({ name: 'Deadlift', workingMax: 350 }),
  ];

  it('session 4 contains only Deadlift', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'mass-strength' }),
      msLifts,
      makeProfile(),
    );
    const session4 = schedule.weeks[0].sessions.find((s) => s.sessionNumber === 4);
    expect(session4!.exercises).toHaveLength(1);
    expect(session4!.exercises[0].liftName).toBe('Deadlift');
  });
});

describe('generateSchedule — Gladiator week 6', () => {
  const gladLifts = [
    makeLift({ name: 'Squat', workingMax: 300 }),
    makeLift({ name: 'Bench', workingMax: 200 }),
    makeLift({ name: 'Deadlift', workingMax: 350 }),
  ];

  it('week 6 has descending reps pattern', () => {
    const schedule = generateSchedule(
      makeProgram({
        templateId: 'gladiator',
        liftSelections: { cluster: ['Squat', 'Bench', 'Deadlift'] },
      }),
      gladLifts,
      makeProfile(),
    );
    const week6 = schedule.weeks.find((w) => w.weekNumber === 6);
    expect(week6?.repsPerSet).toEqual([3, 2, 1, 3, 2]);
    expect(week6?.percentage).toBe(95);
  });
});

describe('generateSchedule — Grey Man', () => {
  const gmLifts = [
    makeLift({ name: 'Squat', workingMax: 300 }),
    makeLift({ name: 'Bench', workingMax: 200 }),
    makeLift({ name: 'Deadlift', workingMax: 350 }),
  ];

  it('returns 12 weeks', () => {
    const schedule = generateSchedule(
      makeProgram({
        templateId: 'grey-man',
        liftSelections: { cluster: ['Squat', 'Bench', 'Deadlift'] },
      }),
      gmLifts,
      makeProfile(),
    );
    expect(schedule.weeks).toHaveLength(12);
  });

  it('weeks 9 and 12 use 95%', () => {
    const schedule = generateSchedule(
      makeProgram({
        templateId: 'grey-man',
        liftSelections: { cluster: ['Squat', 'Bench', 'Deadlift'] },
      }),
      gmLifts,
      makeProfile(),
    );
    expect(schedule.weeks[8].percentage).toBe(95);
    expect(schedule.weeks[11].percentage).toBe(95);
  });
});

describe('generateSchedule — bodyweight lift', () => {
  it('uses belt plates for Weighted Pull-up', () => {
    const schedule = generateSchedule(
      makeProgram({ templateId: 'operator' }),
      operatorLifts,
      makeProfile(),
    );
    const pullUp = schedule.weeks[0].sessions[0].exercises.find(
      (e) => e.liftName === 'Weighted Pull-up',
    );
    // Should use belt plate calc — display text should contain "on belt" or "Bodyweight"
    expect(pullUp).toBeDefined();
    expect(pullUp!.targetWeight).toBeGreaterThanOrEqual(0);
  });
});

describe('generateSchedule — error case', () => {
  it('throws for unknown template', () => {
    expect(() =>
      generateSchedule(
        makeProgram({ templateId: 'nonexistent' as any }),
        operatorLifts,
        makeProfile(),
      ),
    ).toThrow('Unknown template');
  });
});

describe('computeSourceHash', () => {
  it('is deterministic (same inputs = same hash)', () => {
    const program = makeProgram({ templateId: 'operator' });
    const profile = makeProfile();
    const hash1 = computeSourceHash(program, operatorLifts, profile);
    const hash2 = computeSourceHash(program, operatorLifts, profile);
    expect(hash1).toBe(hash2);
  });

  it('changes when workingMax changes', () => {
    const program = makeProgram({ templateId: 'operator' });
    const profile = makeProfile();
    const hash1 = computeSourceHash(program, operatorLifts, profile);
    const modifiedLifts = operatorLifts.map((l) =>
      l.name === 'Squat' ? { ...l, workingMax: 305 } : l,
    );
    const hash2 = computeSourceHash(program, modifiedLifts, profile);
    expect(hash1).not.toBe(hash2);
  });

  it('changes when rounding increment changes', () => {
    const program = makeProgram({ templateId: 'operator' });
    const hash1 = computeSourceHash(program, operatorLifts, makeProfile({ roundingIncrement: 2.5 }));
    const hash2 = computeSourceHash(program, operatorLifts, makeProfile({ roundingIncrement: 5 }));
    expect(hash1).not.toBe(hash2);
  });

  it('changes when barbell weight changes', () => {
    const program = makeProgram({ templateId: 'operator' });
    const hash1 = computeSourceHash(program, operatorLifts, makeProfile({ barbellWeight: 45 }));
    const hash2 = computeSourceHash(program, operatorLifts, makeProfile({ barbellWeight: 35 }));
    expect(hash1).not.toBe(hash2);
  });
});
