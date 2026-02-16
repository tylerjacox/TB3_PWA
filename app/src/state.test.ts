import { getCurrentLifts } from './state';
import { makeAppData, makeMaxTest } from './__tests__/fixtures';

describe('getCurrentLifts', () => {
  it('returns empty array for empty maxTestHistory', () => {
    const data = makeAppData({ maxTestHistory: [] });
    expect(getCurrentLifts(data)).toEqual([]);
  });

  it('returns one entry for single lift test', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ liftName: 'Squat', weight: 300, reps: 5, date: '2025-01-01' }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts).toHaveLength(1);
    expect(lifts[0].name).toBe('Squat');
    expect(lifts[0].weight).toBe(300);
    expect(lifts[0].reps).toBe(5);
  });

  it('keeps only the most recent test per lift', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ id: 't1', liftName: 'Squat', weight: 250, date: '2025-01-01' }),
        makeMaxTest({ id: 't2', liftName: 'Squat', weight: 300, date: '2025-06-01' }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts).toHaveLength(1);
    expect(lifts[0].weight).toBe(300); // most recent
  });

  it('returns one entry per unique lift', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ id: 't1', liftName: 'Squat', weight: 300 }),
        makeMaxTest({ id: 't2', liftName: 'Bench', weight: 200 }),
        makeMaxTest({ id: 't3', liftName: 'Deadlift', weight: 400 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts).toHaveLength(3);
    const names = lifts.map((l) => l.name).sort();
    expect(names).toEqual(['Bench', 'Deadlift', 'Squat']);
  });

  it('applies training max (90%) when maxType is training', () => {
    const data = makeAppData({
      profile: { ...makeAppData().profile, maxType: 'training' },
      maxTestHistory: [
        makeMaxTest({ liftName: 'Squat', weight: 300, reps: 1 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    // 1RM for reps=1 is 300. Training max = 300 * 0.9 = 270
    expect(lifts[0].oneRepMax).toBe(300);
    expect(lifts[0].workingMax).toBeCloseTo(270, 1);
  });

  it('uses raw 1RM when maxType is true', () => {
    const data = makeAppData({
      profile: { ...makeAppData().profile, maxType: 'true' },
      maxTestHistory: [
        makeMaxTest({ liftName: 'Squat', weight: 300, reps: 1 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts[0].oneRepMax).toBe(300);
    expect(lifts[0].workingMax).toBe(300);
  });

  it('marks Weighted Pull-up as bodyweight', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ liftName: 'Weighted Pull-up', weight: 50, reps: 5 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts[0].isBodyweight).toBe(true);
  });

  it('marks non-pull-up lifts as not bodyweight', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ liftName: 'Squat', weight: 300, reps: 5 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    expect(lifts[0].isBodyweight).toBe(false);
  });

  it('calculates correct 1RM via Epley formula', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ liftName: 'Bench', weight: 200, reps: 5 }),
      ],
    });
    const lifts = getCurrentLifts(data);
    // 200 * (1 + 5/30) = 233.33
    expect(lifts[0].oneRepMax).toBeCloseTo(233.33, 1);
  });
});
