import type { ActiveProgram, DerivedLiftEntry, UserProfile, OneRepMaxTest, PlateInventory, AppData } from '../types';
import { createDefaultAppData, createDefaultProfile, DEFAULT_PLATE_INVENTORY_BARBELL, DEFAULT_PLATE_INVENTORY_BELT } from '../types';

export function makeProfile(overrides?: Partial<UserProfile>): UserProfile {
  return { ...createDefaultProfile(), ...overrides };
}

export function makeLift(overrides: Partial<DerivedLiftEntry> & { name: string }): DerivedLiftEntry {
  return {
    weight: 200,
    reps: 5,
    oneRepMax: 233.33,
    workingMax: 210,
    isBodyweight: false,
    testDate: '2025-01-01',
    ...overrides,
  };
}

export function makeProgram(overrides?: Partial<ActiveProgram>): ActiveProgram {
  return {
    templateId: 'operator',
    startDate: '2025-01-01',
    currentWeek: 1,
    currentSession: 1,
    liftSelections: {},
    lastModified: '2025-01-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makeMaxTest(overrides?: Partial<OneRepMaxTest>): OneRepMaxTest {
  return {
    id: 'test-1',
    date: '2025-01-01',
    liftName: 'Squat',
    weight: 300,
    reps: 5,
    calculatedMax: 350,
    maxType: 'training',
    workingMax: 315,
    lastModified: '2025-01-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makeInventory(plates?: { weight: number; available: number }[]): PlateInventory {
  return {
    plates: plates ?? structuredClone(DEFAULT_PLATE_INVENTORY_BARBELL.plates),
  };
}

export function makeBeltInventory(plates?: { weight: number; available: number }[]): PlateInventory {
  return {
    plates: plates ?? structuredClone(DEFAULT_PLATE_INVENTORY_BELT.plates),
  };
}

export function makeAppData(overrides?: Partial<AppData>): AppData {
  return { ...createDefaultAppData(), ...overrides };
}
