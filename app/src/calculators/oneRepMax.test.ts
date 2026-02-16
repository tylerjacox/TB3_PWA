import {
  calculateOneRepMax,
  calculateTrainingMax,
  roundWeight,
  calculatePercentageWeight,
  calculatePercentageTable,
} from './oneRepMax';

describe('calculateOneRepMax', () => {
  it('returns weight unchanged when reps = 1', () => {
    expect(calculateOneRepMax(300, 1)).toBe(300);
  });

  it('returns 0 when reps <= 0', () => {
    expect(calculateOneRepMax(200, 0)).toBe(0);
    expect(calculateOneRepMax(200, -1)).toBe(0);
  });

  it('returns 0 when weight <= 0', () => {
    expect(calculateOneRepMax(0, 5)).toBe(0);
    expect(calculateOneRepMax(-100, 5)).toBe(0);
  });

  it('calculates Epley formula correctly for 200lb x 5', () => {
    // 200 * (1 + 5/30) = 200 * 1.1667 = 233.33...
    expect(calculateOneRepMax(200, 5)).toBeCloseTo(233.33, 1);
  });

  it('calculates Epley formula correctly for 135lb x 10', () => {
    // 135 * (1 + 10/30) = 135 * 1.3333 = 180
    expect(calculateOneRepMax(135, 10)).toBeCloseTo(180, 1);
  });

  it('handles high rep ranges', () => {
    // 100 * (1 + 15/30) = 100 * 1.5 = 150
    expect(calculateOneRepMax(100, 15)).toBeCloseTo(150, 1);
  });
});

describe('calculateTrainingMax', () => {
  it('returns 90% of input', () => {
    expect(calculateTrainingMax(300)).toBeCloseTo(270, 2);
  });

  it('returns 0 for 0 input', () => {
    expect(calculateTrainingMax(0)).toBe(0);
  });

  it('handles fractional results', () => {
    expect(calculateTrainingMax(233.33)).toBeCloseTo(210, 0);
  });
});

describe('roundWeight', () => {
  it('rounds down to nearest 5', () => {
    expect(roundWeight(212, 5)).toBe(210);
  });

  it('rounds up to nearest 5', () => {
    expect(roundWeight(213, 5)).toBe(215);
  });

  it('rounds to nearest 2.5', () => {
    expect(roundWeight(212, 2.5)).toBe(212.5);
  });

  it('returns exact value when already on increment', () => {
    expect(roundWeight(200, 5)).toBe(200);
    expect(roundWeight(212.5, 2.5)).toBe(212.5);
  });

  it('rounds 0 to 0', () => {
    expect(roundWeight(0, 5)).toBe(0);
  });
});

describe('calculatePercentageWeight', () => {
  it('calculates 70% of 200 with 5lb rounding', () => {
    // 200 * 0.70 = 140 → round to 5 = 140
    expect(calculatePercentageWeight(200, 70, 5)).toBe(140);
  });

  it('calculates 90% of 315 with 2.5lb rounding', () => {
    // 315 * 0.90 = 283.5 → round to 2.5 = 283.75? No, Math.round(283.5/2.5)*2.5 = Math.round(113.4)*2.5 = 113*2.5 = 282.5
    expect(calculatePercentageWeight(315, 90, 2.5)).toBe(282.5);
  });

  it('calculates 100% correctly', () => {
    expect(calculatePercentageWeight(200, 100, 5)).toBe(200);
  });
});

describe('calculatePercentageTable', () => {
  it('returns exactly 8 rows', () => {
    const table = calculatePercentageTable(200, 5);
    expect(table).toHaveLength(8);
  });

  it('covers percentages from 65 to 100', () => {
    const table = calculatePercentageTable(200, 5);
    expect(table.map((r) => r.percentage)).toEqual([65, 70, 75, 80, 85, 90, 95, 100]);
  });

  it('each row weight matches calculatePercentageWeight', () => {
    const table = calculatePercentageTable(300, 2.5);
    for (const row of table) {
      expect(row.weight).toBe(calculatePercentageWeight(300, row.percentage, 2.5));
    }
  });

  it('handles 0 workingMax', () => {
    const table = calculatePercentageTable(0, 5);
    expect(table.every((r) => r.weight === 0)).toBe(true);
  });
});
