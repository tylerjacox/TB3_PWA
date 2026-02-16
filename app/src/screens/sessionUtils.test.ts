import { formatTimerDisplay, getRestDuration } from './sessionUtils';

describe('formatTimerDisplay', () => {
  it('formats 0ms as "0:00"', () => {
    expect(formatTimerDisplay(0)).toBe('0:00');
  });

  it('formats 1000ms as "0:01"', () => {
    expect(formatTimerDisplay(1000)).toBe('0:01');
  });

  it('formats 60000ms (1 minute) as "1:00"', () => {
    expect(formatTimerDisplay(60000)).toBe('1:00');
  });

  it('formats 90000ms (1.5 minutes) as "1:30"', () => {
    expect(formatTimerDisplay(90000)).toBe('1:30');
  });

  it('formats 3661000ms (61 minutes 1 second) as "61:01"', () => {
    expect(formatTimerDisplay(3661000)).toBe('61:01');
  });

  it('formats 599000ms (9:59) correctly', () => {
    expect(formatTimerDisplay(599000)).toBe('9:59');
  });

  it('truncates sub-second values (floor)', () => {
    expect(formatTimerDisplay(1999)).toBe('0:01');
  });
});

describe('getRestDuration', () => {
  it('returns profile default when > 0', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 150 },
      computedSchedule: null,
      activeProgram: null,
    });
    expect(result).toBe(150);
  });

  it('returns 120 when no schedule and default is 0', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 0 },
      computedSchedule: null,
      activeProgram: null,
    });
    expect(result).toBe(120);
  });

  it('returns 180 for >= 90% week', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 0 },
      computedSchedule: {
        weeks: [{ weekNumber: 1, percentage: 90 }],
      },
      activeProgram: { currentWeek: 1 },
    });
    expect(result).toBe(180);
  });

  it('returns 120 for >= 70% and < 90% week', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 0 },
      computedSchedule: {
        weeks: [{ weekNumber: 1, percentage: 80 }],
      },
      activeProgram: { currentWeek: 1 },
    });
    expect(result).toBe(120);
  });

  it('returns 90 for < 70% week', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 0 },
      computedSchedule: {
        weeks: [{ weekNumber: 1, percentage: 65 }],
      },
      activeProgram: { currentWeek: 1 },
    });
    expect(result).toBe(90);
  });

  it('returns 120 when week not found in schedule', () => {
    const result = getRestDuration({
      profile: { restTimerDefault: 0 },
      computedSchedule: {
        weeks: [{ weekNumber: 2, percentage: 80 }],
      },
      activeProgram: { currentWeek: 1 }, // week 1 not in schedule
    });
    expect(result).toBe(120);
  });
});
