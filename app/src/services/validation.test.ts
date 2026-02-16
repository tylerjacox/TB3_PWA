import { validateAppData, validateImportData } from './validation';
import { CURRENT_SCHEMA_VERSION } from '../types';
import { makeAppData, makeMaxTest } from '../__tests__/fixtures';

describe('validateAppData', () => {
  it('returns ok for valid data', () => {
    const data = makeAppData();
    const result = validateAppData(data);
    expect(result.severity).toBe('ok');
    expect(result.errors).toHaveLength(0);
  });

  it('returns fatal for null data', () => {
    const result = validateAppData(null as any);
    expect(result.severity).toBe('fatal');
  });

  it('returns fatal for non-object data', () => {
    const result = validateAppData('string' as any);
    expect(result.severity).toBe('fatal');
  });

  it('returns fatal for missing profile', () => {
    const result = validateAppData({ sessionHistory: [], maxTestHistory: [] } as any);
    expect(result.severity).toBe('fatal');
  });

  it('returns recoverable for unknown template in activeProgram', () => {
    const data = makeAppData({
      activeProgram: {
        templateId: 'unknown-template' as any,
        startDate: '2025-01-01',
        currentWeek: 1,
        currentSession: 1,
        liftSelections: {},
        lastModified: '2025-01-01T00:00:00.000Z',
      },
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('recoverable');
    expect(result.errors.some((e) => e.includes('Unknown template'))).toBe(true);
  });

  it('returns warning for unknown lift name', () => {
    const data = makeAppData({
      maxTestHistory: [makeMaxTest({ liftName: 'Not A Real Lift' })],
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('warning');
    expect(result.errors.some((e) => e.includes('Unknown lift'))).toBe(true);
  });

  it('returns warning for weight out of range', () => {
    const data = makeAppData({
      maxTestHistory: [makeMaxTest({ weight: 2000 })],
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('warning');
    expect(result.errors.some((e) => e.includes('Weight out of range'))).toBe(true);
  });

  it('returns warning for reps out of range', () => {
    const data = makeAppData({
      maxTestHistory: [makeMaxTest({ reps: 20 })],
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('warning');
    expect(result.errors.some((e) => e.includes('Reps out of range'))).toBe(true);
  });

  it('returns warning for duplicate session IDs', () => {
    const data = makeAppData({
      sessionHistory: [
        { id: 'dup', date: '2025-01-01', templateId: 'operator', week: 1, sessionNumber: 1, status: 'completed', startedAt: '', completedAt: '', exercises: [], notes: '', lastModified: '' },
        { id: 'dup', date: '2025-01-02', templateId: 'operator', week: 1, sessionNumber: 2, status: 'completed', startedAt: '', completedAt: '', exercises: [], notes: '', lastModified: '' },
      ] as any,
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('warning');
    expect(result.errors.some((e) => e.includes('Duplicate session ID'))).toBe(true);
  });

  it('returns warning for duplicate max test IDs', () => {
    const data = makeAppData({
      maxTestHistory: [
        makeMaxTest({ id: 'dup-test' }),
        makeMaxTest({ id: 'dup-test', liftName: 'Bench' }),
      ],
    });
    const result = validateAppData(data);
    expect(result.severity).toBe('warning');
    expect(result.errors.some((e) => e.includes('Duplicate max test ID'))).toBe(true);
  });
});

describe('validateImportData', () => {
  const validImport = JSON.stringify({
    tb3_export: true,
    schemaVersion: CURRENT_SCHEMA_VERSION,
    profile: { maxType: 'training', roundingIncrement: 5 },
    sessionHistory: [],
    maxTestHistory: [],
  });

  it('rejects oversized files (>1MB)', () => {
    const big = 'x'.repeat(1_000_001);
    const result = validateImportData(big);
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('too large');
  });

  it('rejects invalid JSON', () => {
    const result = validateImportData('not json{{{');
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('parse');
  });

  it('rejects missing tb3_export sentinel', () => {
    const result = validateImportData(JSON.stringify({ schemaVersion: 3, profile: {} }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('TB3 backup');
  });

  it('rejects non-numeric schemaVersion', () => {
    const result = validateImportData(JSON.stringify({ tb3_export: true, schemaVersion: 'x' }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('version');
  });

  it('rejects future schema version', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION + 1,
      profile: {},
      sessionHistory: [],
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('newer version');
  });

  it('rejects __proto__ pollution', () => {
    // JSON.parse strips __proto__ at top level, so test with nested object
    // that has a "prototype" key (which JSON.parse preserves)
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [],
      maxTestHistory: [],
      nested: { prototype: { exploit: true } },
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('unsafe');
  });

  it('rejects nested prototype pollution', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: { constructor: {} },
      sessionHistory: [],
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('unsafe');
  });

  it('rejects missing profile', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      sessionHistory: [],
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('profile');
  });

  it('rejects missing sessionHistory', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('session');
  });

  it('rejects weight out of range in maxTestHistory', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [],
      maxTestHistory: [{ id: 't1', weight: 2000, reps: 5 }],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('Weight out of range');
  });

  it('rejects reps out of range', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [],
      maxTestHistory: [{ id: 't1', weight: 200, reps: 20 }],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('Reps out of range');
  });

  it('rejects session notes > 500 chars', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [{ id: 's1', notes: 'x'.repeat(501) }],
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('500 character');
  });

  it('rejects duplicate session IDs', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [{ id: 'dup' }, { id: 'dup' }],
      maxTestHistory: [],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('Duplicate session ID');
  });

  it('rejects duplicate max test IDs', () => {
    const result = validateImportData(JSON.stringify({
      tb3_export: true,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      profile: {},
      sessionHistory: [],
      maxTestHistory: [
        { id: 'dup', weight: 200, reps: 5 },
        { id: 'dup', weight: 300, reps: 3 },
      ],
    }));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.error).toContain('Duplicate max test ID');
  });

  it('accepts valid import data', () => {
    const result = validateImportData(validImport);
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.data.tb3_export).toBe(true);
    }
  });
});
