// Export/Import (PRD 7.5)
import { appData, updateAppData } from '../state';
import { validateImportData } from './validation';
import { migrateData } from './migrations';
import type { AppData } from '../types';
import { CURRENT_SCHEMA_VERSION, createDefaultAppData } from '../types';
import { APP_VERSION } from '../version';

export function exportAppData(): string {
  const data = appData.value;
  const exportObj = {
    tb3_export: true,
    exportedAt: new Date().toISOString(),
    appVersion: APP_VERSION,
    schemaVersion: data.schemaVersion,
    profile: data.profile,
    activeProgram: data.activeProgram,
    sessionHistory: data.sessionHistory,
    maxTestHistory: data.maxTestHistory,
  };
  return JSON.stringify(exportObj, null, 2);
}

export async function shareExport(): Promise<boolean> {
  const json = exportAppData();
  const blob = new Blob([json], { type: 'application/json' });
  const file = new File([blob], `tb3-backup-${new Date().toISOString().slice(0, 10)}.json`, {
    type: 'application/json',
  });

  // Try Web Share API
  if (navigator.share && navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'TB3 Backup' });
      await updateAppData((d) => ({ ...d, lastBackupDate: new Date().toISOString() }));
      return true;
    } catch { /* User cancelled share */ }
  }

  // Fallback: clipboard
  try {
    await navigator.clipboard.writeText(json);
    await updateAppData((d) => ({ ...d, lastBackupDate: new Date().toISOString() }));
    return true;
  } catch { /* Clipboard failed */ }

  // Last fallback: download link
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = file.name;
  a.click();
  URL.revokeObjectURL(url);
  await updateAppData((d) => ({ ...d, lastBackupDate: new Date().toISOString() }));
  return true;
}

export interface ImportResult {
  success: boolean;
  error?: string;
  preview?: {
    lifts: number;
    sessions: number;
    maxTests: number;
    lastDate?: string;
  };
  data?: any;
}

export function validateImport(raw: string): ImportResult {
  const result = validateImportData(raw);
  if (!result.valid) {
    return { success: false, error: result.error };
  }

  const data = result.data;

  // Step 7: Run migrations if needed
  let migrated = data;
  if (data.schemaVersion < CURRENT_SCHEMA_VERSION) {
    try {
      migrated = migrateData(data, CURRENT_SCHEMA_VERSION);
    } catch (e: any) {
      return { success: false, error: `Migration failed: ${e.message}` };
    }
  }

  return {
    success: true,
    preview: {
      lifts: new Set(migrated.maxTestHistory?.map((t: any) => t.liftName)).size,
      sessions: migrated.sessionHistory?.length || 0,
      maxTests: migrated.maxTestHistory?.length || 0,
      lastDate: migrated.maxTestHistory?.length
        ? migrated.maxTestHistory[migrated.maxTestHistory.length - 1].date
        : undefined,
    },
    data: migrated,
  };
}

export async function performImport(importedData: any): Promise<void> {
  const newData: AppData = {
    ...createDefaultAppData(),
    schemaVersion: CURRENT_SCHEMA_VERSION,
    profile: importedData.profile,
    activeProgram: importedData.activeProgram || null,
    computedSchedule: null, // Will be regenerated
    activeSession: null,
    sessionHistory: importedData.sessionHistory || [],
    maxTestHistory: importedData.maxTestHistory || [],
    lastBackupDate: null,
    lastSyncedAt: null,
  };

  await updateAppData(() => newData);
}

export function pickFile(): Promise<string> {
  return new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) {
        reject(new Error('No file selected'));
        return;
      }
      if (file.size > 1_000_000) {
        reject(new Error('File too large. Maximum size is 1MB.'));
        return;
      }
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsText(file);
    };
    input.click();
  });
}
