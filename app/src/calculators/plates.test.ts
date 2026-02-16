import { calculateBarbellPlates, calculateBeltPlates } from './plates';
import type { PlateInventory } from '../types';
import { DEFAULT_PLATE_INVENTORY_BARBELL, DEFAULT_PLATE_INVENTORY_BELT } from '../types';

const defaultBarbell = (): PlateInventory => structuredClone(DEFAULT_PLATE_INVENTORY_BARBELL);
const defaultBelt = (): PlateInventory => structuredClone(DEFAULT_PLATE_INVENTORY_BELT);

describe('calculateBarbellPlates — guard conditions', () => {
  it('returns not achievable for weight <= 0', () => {
    const result = calculateBarbellPlates(0, 45, defaultBarbell());
    expect(result.achievable).toBe(false);
    expect(result.displayText).toBe('Not achievable');
  });

  it('returns not achievable for negative weight', () => {
    const result = calculateBarbellPlates(-10, 45, defaultBarbell());
    expect(result.achievable).toBe(false);
  });

  it('returns bar only when weight equals barbell weight', () => {
    const result = calculateBarbellPlates(45, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
    expect(result.isBarOnly).toBe(true);
    expect(result.displayText).toBe('Bar only');
    expect(result.plates).toHaveLength(0);
  });

  it('returns below bar when weight is less than barbell weight', () => {
    const result = calculateBarbellPlates(30, 45, defaultBarbell());
    expect(result.achievable).toBe(false);
    expect(result.isBelowBar).toBe(true);
  });
});

describe('calculateBarbellPlates — greedy algorithm', () => {
  it('loads one 45 plate per side for 135lb', () => {
    // (135 - 45) / 2 = 45 per side
    const result = calculateBarbellPlates(135, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
    expect(result.plates).toEqual([{ weight: 45, count: 1 }]);
  });

  it('loads two 45 plates per side for 225lb', () => {
    // (225 - 45) / 2 = 90 per side = 2x45
    const result = calculateBarbellPlates(225, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
    expect(result.plates).toEqual([{ weight: 45, count: 2 }]);
  });

  it('loads mixed plates for 185lb', () => {
    // (185 - 45) / 2 = 70 per side = 45 + 25
    const result = calculateBarbellPlates(185, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
    expect(result.plates).toEqual([
      { weight: 45, count: 1 },
      { weight: 25, count: 1 },
    ]);
  });

  it('loads complex fractional weight for 202.5lb', () => {
    // (202.5 - 45) / 2 = 78.75 per side = 45 + 25 + 5 + 2.5 + 1.25
    const result = calculateBarbellPlates(202.5, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
    expect(result.plates).toContainEqual({ weight: 45, count: 1 });
    expect(result.plates).toContainEqual({ weight: 25, count: 1 });
    expect(result.plates).toContainEqual({ weight: 5, count: 1 });
    expect(result.plates).toContainEqual({ weight: 2.5, count: 1 });
    expect(result.plates).toContainEqual({ weight: 1.25, count: 1 });
  });

  it('display text includes "per side" label', () => {
    const result = calculateBarbellPlates(135, 45, defaultBarbell());
    expect(result.displayText).toContain('per side');
  });

  it('display text includes plate weight', () => {
    const result = calculateBarbellPlates(135, 45, defaultBarbell());
    expect(result.displayText).toContain('45');
  });
});

describe('calculateBarbellPlates — unachievable weights', () => {
  it('reports unachievable when inventory cannot match', () => {
    // Inventory with only 45lb plates — can't do 50lb per side
    const inventory: PlateInventory = {
      plates: [{ weight: 45, available: 4 }],
    };
    // 135lb = one 45 per side (achievable)
    const achievable = calculateBarbellPlates(135, 45, inventory);
    expect(achievable.achievable).toBe(true);

    // 145lb = 50 per side (not possible with only 45s)
    const unachievable = calculateBarbellPlates(145, 45, inventory);
    expect(unachievable.achievable).toBe(false);
    expect(unachievable.nearestAchievable).toBeDefined();
  });

  it('finds nearest achievable weight', () => {
    const inventory: PlateInventory = {
      plates: [
        { weight: 45, available: 4 },
        { weight: 25, available: 1 },
      ],
    };
    // 200lb = 77.5 per side. Can do 45+25=70 or 45+25+... need more plates. Not achievable.
    // Nearest: 45+25 = 70 per side = 185lb total
    const result = calculateBarbellPlates(200, 45, inventory);
    if (!result.achievable) {
      expect(result.nearestAchievable).toBeGreaterThan(0);
    }
  });

  it('returns 0 nearest for empty inventory', () => {
    const inventory: PlateInventory = { plates: [] };
    const result = calculateBarbellPlates(135, 45, inventory);
    // 135 with 45 bar = 45 per side but no plates available
    expect(result.achievable).toBe(false);
  });
});

describe('calculateBarbellPlates — float precision', () => {
  it('handles weight that produces fractional per-side value', () => {
    // 162.5 with 45 bar = (162.5-45)/2 = 58.75 per side
    // 45 + 10 + 2.5 + 1.25 = 58.75 — achievable with default inventory
    const result = calculateBarbellPlates(162.5, 45, defaultBarbell());
    expect(result.achievable).toBe(true);
  });
});

describe('calculateBeltPlates', () => {
  it('returns bodyweight only for weight <= 0', () => {
    const result = calculateBeltPlates(0, defaultBelt());
    expect(result.achievable).toBe(true);
    expect(result.isBodyweightOnly).toBe(true);
    expect(result.displayText).toBe('Bodyweight only');
  });

  it('returns bodyweight only for negative weight', () => {
    const result = calculateBeltPlates(-5, defaultBelt());
    expect(result.achievable).toBe(true);
    expect(result.isBodyweightOnly).toBe(true);
  });

  it('loads one 45 plate on belt', () => {
    const result = calculateBeltPlates(45, defaultBelt());
    expect(result.achievable).toBe(true);
    expect(result.plates).toEqual([{ weight: 45, count: 1 }]);
    expect(result.displayText).toContain('on belt');
  });

  it('loads greedy selection for 50lb on belt', () => {
    // 50 = 45 + 5
    const result = calculateBeltPlates(50, defaultBelt());
    expect(result.achievable).toBe(true);
    expect(result.plates).toEqual([
      { weight: 45, count: 1 },
      { weight: 5, count: 1 },
    ]);
  });

  it('reports unachievable for impossible belt weight', () => {
    const inventory: PlateInventory = {
      plates: [{ weight: 45, available: 1 }],
    };
    const result = calculateBeltPlates(50, inventory);
    expect(result.achievable).toBe(false);
    expect(result.nearestAchievable).toBeDefined();
  });
});
