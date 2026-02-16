import { migrateData } from './migrations';

describe('migrateData', () => {
  it('v1 → v2: adds voiceAnnouncements to profile', () => {
    const v1 = { schemaVersion: 1, profile: { maxType: 'training' } };
    const result = migrateData(v1, 2);
    expect(result.schemaVersion).toBe(2);
    expect(result.profile.voiceAnnouncements).toBe(false);
  });

  it('v1 → v2: preserves existing voiceAnnouncements', () => {
    const v1 = { schemaVersion: 1, profile: { maxType: 'training', voiceAnnouncements: true } };
    const result = migrateData(v1, 2);
    expect(result.profile.voiceAnnouncements).toBe(true);
  });

  it('v2 → v3: adds voiceName to profile', () => {
    const v2 = { schemaVersion: 2, profile: { maxType: 'training', voiceAnnouncements: false } };
    const result = migrateData(v2, 3);
    expect(result.schemaVersion).toBe(3);
    expect(result.profile.voiceName).toBeNull();
  });

  it('v2 → v3: preserves existing voiceName', () => {
    const v2 = { schemaVersion: 2, profile: { voiceName: 'Samantha' } };
    const result = migrateData(v2, 3);
    expect(result.profile.voiceName).toBe('Samantha');
  });

  it('v1 → v3: chains both migrations', () => {
    const v1 = { schemaVersion: 1, profile: { maxType: 'training' } };
    const result = migrateData(v1, 3);
    expect(result.schemaVersion).toBe(3);
    expect(result.profile.voiceAnnouncements).toBe(false);
    expect(result.profile.voiceName).toBeNull();
  });

  it('data at target version returns unchanged', () => {
    const v3 = { schemaVersion: 3, profile: { voiceAnnouncements: true, voiceName: 'Alex' } };
    const result = migrateData(v3, 3);
    expect(result.schemaVersion).toBe(3);
    expect(result.profile.voiceName).toBe('Alex');
  });

  it('throws for missing migration step', () => {
    const v3 = { schemaVersion: 3, profile: {} };
    expect(() => migrateData(v3, 5)).toThrow('No migration from v3 to v4');
  });

  it('handles data without schemaVersion (defaults to 1)', () => {
    const noVersion = { profile: { maxType: 'training' } };
    const result = migrateData(noVersion, 3);
    expect(result.schemaVersion).toBe(3);
  });
});
