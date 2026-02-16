// TB3 PWA — Core TypeScript Interfaces (PRD 7.1)

export const CURRENT_SCHEMA_VERSION = 1;

export const LIFT_NAMES = [
  'Squat',
  'Bench',
  'Deadlift',
  'Military Press',
  'Weighted Pull-up',
] as const;

export type LiftName = (typeof LIFT_NAMES)[number];

export const TEMPLATE_IDS = [
  'operator',
  'zulu',
  'fighter',
  'gladiator',
  'mass-protocol',
  'mass-strength',
  'grey-man',
] as const;

export type TemplateId = (typeof TEMPLATE_IDS)[number];

export interface AppData {
  schemaVersion: number;
  profile: UserProfile;
  activeProgram: ActiveProgram | null;
  computedSchedule: ComputedSchedule | null;
  activeSession: ActiveSessionState | null;
  sessionHistory: SessionLog[];
  maxTestHistory: OneRepMaxTest[];
  lastBackupDate: string | null;
  lastSyncedAt: string | null;
}

export interface UserProfile {
  maxType: 'true' | 'training';
  roundingIncrement: 2.5 | 5;
  barbellWeight: number;
  plateInventoryBarbell: PlateInventory;
  plateInventoryBelt: PlateInventory;
  restTimerDefault: number;
  soundMode: 'on' | 'off' | 'vibrate';
  theme: 'light' | 'dark' | 'system';
  unit: 'lb' | 'kg';
  lastModified: string;
}

export interface DerivedLiftEntry {
  name: string;
  weight: number;
  reps: number;
  oneRepMax: number;
  workingMax: number;
  isBodyweight: boolean;
  testDate: string;
}

export interface PlateInventory {
  plates: { weight: number; available: number }[];
}

export interface ActiveProgram {
  templateId: TemplateId;
  startDate: string;
  currentWeek: number;
  currentSession: number;
  liftSelections: Record<string, string[]>;
  lastModified: string;
}

export interface ComputedSchedule {
  computedAt: string;
  sourceHash: string;
  weeks: ComputedWeek[];
}

export interface ComputedWeek {
  weekNumber: number;
  percentage: number;
  setsRange: [number, number];
  repsPerSet: number | number[];
  sessions: ComputedSession[];
}

export interface ComputedSession {
  sessionNumber: number;
  type: 'strength' | 'endurance';
  exercises: ComputedExercise[];
  enduranceDuration?: string;
}

export interface ComputedExercise {
  liftName: string;
  targetWeight: number;
  plateBreakdown: string;
  plateBreakdownPerSide: { weight: number; count: number }[];
  achievable: boolean;
}

export interface ActiveSessionState {
  status: 'in_progress' | 'paused';
  templateId: string;
  programWeek: number;
  programSession: number;
  sessionType: 'strength' | 'endurance';
  startedAt: string;
  currentExerciseIndex: number;
  exercises: {
    liftName: string;
    targetWeight: number;
    targetSets: number;
    targetReps: number | number[];
    plateBreakdown: { weight: number; count: number }[];
  }[];
  sets: SessionSet[];
  weightOverrides: Record<number, number>;
  exerciseStartTimes: Record<number, string>;
  restTimerState: {
    running: boolean;
    targetEndTime: number | null;
  } | null;
  enduranceDuration?: string;
  enduranceStartedAt?: string;
  enduranceDurationActual?: number;
}

export interface SessionSet {
  exerciseIndex: number;
  setNumber: number;
  targetReps: number;
  actualReps: number | null;
  completed: boolean;
  completedAt: string | null;
}

export interface SessionLog {
  id: string;
  date: string;
  templateId: string;
  week: number;
  sessionNumber: number;
  status: 'completed' | 'partial' | 'skipped';
  startedAt: string;
  completedAt: string;
  exercises: ExerciseLog[];
  notes: string;
  durationMinutes?: number;
  durationSeconds?: number;
  lastModified: string;
}

export interface ExerciseLog {
  liftName: string;
  targetWeight: number;
  actualWeight: number;
  sets: {
    targetReps: number;
    actualReps: number;
    completed: boolean;
  }[];
  durationSeconds?: number;
}

export interface OneRepMaxTest {
  id: string;
  date: string;
  liftName: string;
  weight: number;
  reps: number;
  calculatedMax: number;
  maxType: 'true' | 'training';
  workingMax: number;
  lastModified: string;
}

// --- Default Factories ---

export const DEFAULT_PLATE_INVENTORY_BARBELL: PlateInventory = {
  plates: [
    { weight: 45, available: 4 },
    { weight: 35, available: 1 },
    { weight: 25, available: 1 },
    { weight: 10, available: 2 },
    { weight: 5, available: 1 },
    { weight: 2.5, available: 1 },
    { weight: 1.25, available: 1 },
  ],
};

export const DEFAULT_PLATE_INVENTORY_BELT: PlateInventory = {
  plates: [
    { weight: 45, available: 2 },
    { weight: 35, available: 1 },
    { weight: 25, available: 1 },
    { weight: 10, available: 2 },
    { weight: 5, available: 1 },
    { weight: 2.5, available: 1 },
    { weight: 1.25, available: 1 },
  ],
};

export function createDefaultProfile(): UserProfile {
  return {
    maxType: 'training',
    roundingIncrement: 2.5,
    barbellWeight: 45,
    plateInventoryBarbell: structuredClone(DEFAULT_PLATE_INVENTORY_BARBELL),
    plateInventoryBelt: structuredClone(DEFAULT_PLATE_INVENTORY_BELT),
    restTimerDefault: 120,
    soundMode: 'on',
    theme: 'dark',
    unit: 'lb',
    lastModified: new Date().toISOString(),
  };
}

export function createDefaultAppData(): AppData {
  return {
    schemaVersion: CURRENT_SCHEMA_VERSION,
    profile: createDefaultProfile(),
    activeProgram: null,
    computedSchedule: null,
    activeSession: null,
    sessionHistory: [],
    maxTestHistory: [],
    lastBackupDate: null,
    lastSyncedAt: null,
  };
}

export function generateId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return Date.now().toString(36) + Math.random().toString(36).slice(2);
}
