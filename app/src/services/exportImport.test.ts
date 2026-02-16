import { validateImport } from './exportImport';
import { CURRENT_SCHEMA_VERSION } from '../types';

describe('validateImport', () => {
  it('returns error for invalid JSON', () => {
    const result = validateImport('not json');
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  it('returns error for missing sentinel', () => {
    const result = validateImport(JSON.stringify({ schemaVersion: 3, profile: {} }));
    expect(result.success).toBe(false);
  });

  it('returns preview with correct counts for valid import', () => {
    const raw = JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: { maxType: 'training' },
      sessionHistory: [
        { id: 's1', notes: '' },
        { id: 's2', notes: '' },
      ],
      maxTestHistory: [
        { id: 't1', liftName: 'Squat', weight: 300, reps: 5, date: '2025-01-01' },
        { id: 't2', liftName: 'Bench', weight: 200, reps: 5, date: '2025-01-01' },
        { id: 't3', liftName: 'Squat', weight: 310, reps: 5, date: '2025-02-01' },
      ],
    });
    const result = validateImport(raw);
    expect(result.success).toBe(true);
    expect(result.preview?.sessions).toBe(2);
    expect(result.preview?.maxTests).toBe(3);
    expect(result.preview?.lifts).toBe(2); // unique: Squat, Bench
  });

  it('migrates old schema versions before returning preview', () => {
    const raw = JSON.stringify({
      tb3_export: true,
      schemaVersion: 1,
      profile: { maxType: 'training' },
      sessionHistory: [],
      maxTestHistory: [],
    });
    const result = validateImport(raw);
    expect(result.success).toBe(true);
    // After migration v1→v3, profile should have voiceAnnouncements and voiceName
    expect(result.data.schemaVersion).toBe(CURRENT_SCHEMA_VERSION);
    expect(result.data.profile.voiceAnnouncements).toBe(false);
    expect(result.data.profile.voiceName).toBeNull();
  });

  it('migrates schema version 0 (defaults to v1 internally)', () => {
    // migrateData treats schemaVersion 0 as v1 (via || 1 fallback)
    const raw = JSON.stringify({
      tb3_export: true,
      schemaVersion: 0,
      profile: { maxType: 'training' },
      sessionHistory: [],
      maxTestHistory: [],
    });
    const result = validateImport(raw);
    expect(result.success).toBe(true);
    expect(result.data.schemaVersion).toBe(CURRENT_SCHEMA_VERSION);
  });

  it('handles current schema version without migration', () => {
    const raw = JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: { maxType: 'training', voiceAnnouncements: true, voiceName: 'Alex' },
      sessionHistory: [],
      maxTestHistory: [],
    });
    const result = validateImport(raw);
    expect(result.success).toBe(true);
    expect(result.data.profile.voiceName).toBe('Alex');
  });
});
