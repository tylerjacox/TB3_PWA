import { useState, useEffect } from 'preact/hooks';
import { appData, updateAppData, currentLifts } from '../state';
import { LIFT_NAMES, generateId } from '../types';
import type { OneRepMaxTest } from '../types';
import { calculateOneRepMax, calculateTrainingMax } from '../calculators/oneRepMax';
import { PercentageTable } from '../components/PercentageTable';
import { PlateInventoryEditor } from '../components/PlateInventoryEditor';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { shareExport, pickFile, validateImport, performImport } from '../services/exportImport';
import { isSpeechAvailable, getAvailableVoices, speakTest } from '../services/feedback';
import { signOut, authState } from '../services/auth';
import { clearAllData } from '../services/storage';
import { navigate } from '../router';
import { syncState, performSync } from '../services/sync';
import { APP_VERSION } from '../version';

export function Profile() {
  const profile = appData.value.profile;
  const lifts = currentLifts.value;
  const [expandedLift, setExpandedLift] = useState<string | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [importError, setImportError] = useState('');
  const [importSuccess, setImportSuccess] = useState('');
  const [exportSuccess, setExportSuccess] = useState('');

  async function handle1RMEntry(liftName: string, weight: string, reps: string) {
    const w = parseFloat(weight);
    const r = parseInt(reps, 10);
    if (!w || w < 1 || w > 1500 || !r || r < 1 || r > 15) return;

    const oneRepMax = calculateOneRepMax(w, r);
    const workingMax = profile.maxType === 'training' ? calculateTrainingMax(oneRepMax) : oneRepMax;

    const test: OneRepMaxTest = {
      id: generateId(),
      date: new Date().toISOString(),
      liftName,
      weight: w,
      reps: r,
      calculatedMax: Math.round(oneRepMax * 100) / 100,
      maxType: profile.maxType,
      workingMax: Math.round(workingMax * 100) / 100,
      lastModified: new Date().toISOString(),
    };

    await updateAppData((d) => ({
      ...d,
      maxTestHistory: [...d.maxTestHistory, test],
    }));
  }

  async function handleExport() {
    const result = await shareExport();
    if (result) setExportSuccess('Data exported successfully.');
    setTimeout(() => setExportSuccess(''), 3000);
  }

  async function handleImport() {
    setImportError('');
    setImportSuccess('');
    try {
      const raw = await pickFile();
      const result = validateImport(raw);
      if (!result.success) {
        setImportError(result.error || 'Import failed.');
        return;
      }
      // Confirmation is implicit from file selection
      if (result.data) {
        await performImport(result.data);
        setImportSuccess(`Imported ${result.preview?.sessions || 0} sessions, ${result.preview?.lifts || 0} lifts.`);
      }
    } catch (e: any) {
      setImportError(e.message || 'Import failed.');
    }
  }

  async function handleDeleteAll() {
    await clearAllData();
    window.location.reload();
  }

  async function handleSignOut() {
    await signOut();
  }

  return (
    <div class="screen">
      <div class="screen-header">
        <h1>Profile</h1>
        {authState.value.user?.email && (
          <p style={{ fontSize: 14, color: 'var(--muted)', marginTop: 2 }}>
            {authState.value.user.email}
          </p>
        )}
      </div>

      {/* 1RM Entry */}
      <div class="settings-group">
        <div class="settings-group-title">Your Lifts</div>
        {LIFT_NAMES.map((name) => {
          const lift = lifts.find((l) => l.name === name);
          const isExpanded = expandedLift === name;
          return (
            <LiftEntry
              key={name}
              name={name}
              lift={lift}
              expanded={isExpanded}
              onToggle={() => setExpandedLift(isExpanded ? null : name)}
              onSave={(w, r) => handle1RMEntry(name, w, r)}
              profile={profile}
            />
          );
        })}
      </div>

      {/* Settings */}
      <div class="settings-group">
        <div class="settings-group-title">Settings</div>

        <div class="settings-row">
          <span class="settings-row-label">Max Type</span>
          <div class="toggle-group" role="radiogroup" aria-label="Max type">
            <button
              class={`toggle-option${profile.maxType === 'training' ? ' active' : ''}`}
              role="radio"
              aria-checked={profile.maxType === 'training'}
              onClick={() => updateAppData((d) => ({
                ...d,
                profile: { ...d.profile, maxType: 'training', lastModified: new Date().toISOString() },
              }))}
            >
              Training
            </button>
            <button
              class={`toggle-option${profile.maxType === 'true' ? ' active' : ''}`}
              role="radio"
              aria-checked={profile.maxType === 'true'}
              onClick={() => updateAppData((d) => ({
                ...d,
                profile: { ...d.profile, maxType: 'true', lastModified: new Date().toISOString() },
              }))}
            >
              True
            </button>
          </div>
        </div>

        <div class="settings-row">
          <span class="settings-row-label">Rounding</span>
          <div class="toggle-group" role="radiogroup" aria-label="Rounding increment">
            <button
              class={`toggle-option${profile.roundingIncrement === 2.5 ? ' active' : ''}`}
              role="radio"
              aria-checked={profile.roundingIncrement === 2.5}
              onClick={() => updateAppData((d) => ({
                ...d,
                profile: { ...d.profile, roundingIncrement: 2.5, lastModified: new Date().toISOString() },
              }))}
            >
              2.5 lb
            </button>
            <button
              class={`toggle-option${profile.roundingIncrement === 5 ? ' active' : ''}`}
              role="radio"
              aria-checked={profile.roundingIncrement === 5}
              onClick={() => updateAppData((d) => ({
                ...d,
                profile: { ...d.profile, roundingIncrement: 5, lastModified: new Date().toISOString() },
              }))}
            >
              5 lb
            </button>
          </div>
        </div>

        <div class="settings-row">
          <span class="settings-row-label">Barbell Weight</span>
          <div class="field" style={{ width: 100, marginBottom: 0 }}>
            <input
              type="text"
              inputMode="decimal"
              value={profile.barbellWeight}
              onBlur={(e) => {
                const v = parseFloat((e.target as HTMLInputElement).value);
                if (v >= 15 && v <= 100) {
                  updateAppData((d) => ({
                    ...d,
                    profile: { ...d.profile, barbellWeight: v, lastModified: new Date().toISOString() },
                  }));
                }
              }}
              aria-label="Barbell weight in pounds"
              style={{ textAlign: 'right' }}
            />
          </div>
        </div>

        <div class="settings-row">
          <span class="settings-row-label">Rest Timer</span>
          <div class="field" style={{ width: 100, marginBottom: 0 }}>
            <input
              type="text"
              inputMode="numeric"
              value={profile.restTimerDefault}
              onBlur={(e) => {
                const v = parseInt((e.target as HTMLInputElement).value, 10);
                if (v >= 0 && v <= 600) {
                  updateAppData((d) => ({
                    ...d,
                    profile: { ...d.profile, restTimerDefault: v, lastModified: new Date().toISOString() },
                  }));
                }
              }}
              aria-label="Rest timer default in seconds"
              style={{ textAlign: 'right' }}
            />
          </div>
        </div>

        <div class="settings-row">
          <span class="settings-row-label">Sound</span>
          <div class="toggle-group" role="radiogroup" aria-label="Sound mode">
            {(['on', 'vibrate', 'off'] as const).map((m) => (
              <button
                key={m}
                class={`toggle-option${profile.soundMode === m ? ' active' : ''}`}
                role="radio"
                aria-checked={profile.soundMode === m}
                onClick={() => updateAppData((d) => ({
                  ...d,
                  profile: { ...d.profile, soundMode: m, lastModified: new Date().toISOString() },
                }))}
              >
                {m === 'on' ? 'On' : m === 'vibrate' ? 'Vibrate' : 'Off'}
              </button>
            ))}
          </div>
        </div>

        {isSpeechAvailable() && <VoiceSettings profile={profile} />}
      </div>

      {/* Plate Inventory */}
      <div class="settings-group">
        <PlateInventoryEditor
          inventory={profile.plateInventoryBarbell}
          label="Barbell Plates (per side)"
          onChange={(inv) => updateAppData((d) => ({
            ...d,
            profile: { ...d.profile, plateInventoryBarbell: inv, lastModified: new Date().toISOString() },
          }))}
        />
      </div>

      <div class="settings-group">
        <PlateInventoryEditor
          inventory={profile.plateInventoryBelt}
          label="Belt Plates (total)"
          onChange={(inv) => updateAppData((d) => ({
            ...d,
            profile: { ...d.profile, plateInventoryBelt: inv, lastModified: new Date().toISOString() },
          }))}
        />
      </div>

      {/* Sync */}
      <div class="settings-group">
        <div class="settings-group-title">Sync</div>
        <div style={{ fontSize: 13, color: 'var(--muted)', lineHeight: 1.6 }}>
          <div>Status: {syncState.value.isSyncing ? 'Syncing...' : 'Idle'}</div>
          <div>Last synced: {syncState.value.lastSyncedAt ? new Date(syncState.value.lastSyncedAt).toLocaleString() : 'Never'}</div>
          <div>Sessions: {appData.value.sessionHistory.length}</div>
          {syncState.value.error && <div style={{ color: 'var(--danger)' }}>Error: {syncState.value.error}</div>}
        </div>
        <button
          class="btn btn-secondary"
          style={{ width: '100%', marginTop: 8 }}
          onClick={() => performSync()}
          disabled={syncState.value.isSyncing}
        >
          {syncState.value.isSyncing ? 'Syncing...' : 'Sync Now'}
        </button>
      </div>

      {/* Data */}
      <div class="settings-group">
        <div class="settings-group-title">Data</div>

        {exportSuccess && <p class="auth-success" role="status">{exportSuccess}</p>}
        <button class="btn btn-secondary" style={{ width: '100%', marginBottom: 8 }} onClick={handleExport}>
          Export Data
        </button>

        {importError && <p class="auth-error" role="alert">{importError}</p>}
        {importSuccess && <p class="auth-success" role="status">{importSuccess}</p>}
        <button class="btn btn-secondary" style={{ width: '100%', marginBottom: 8 }} onClick={handleImport}>
          Import Data
        </button>

        <button class="btn btn-ghost" style={{ width: '100%', marginBottom: 8 }} onClick={handleSignOut}>
          Sign Out
        </button>

        <button class="btn btn-danger" style={{ width: '100%' }} onClick={() => setShowDeleteConfirm(true)}>
          Delete All Data
        </button>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">About</div>
        <p style={{ fontSize: 14, color: 'var(--muted)', lineHeight: 1.4 }}>
          Your training data is stored locally on your device and synced to the cloud when signed in.
          Data is only accessible to you.
        </p>
        <p style={{ fontSize: 13, color: 'var(--muted)', marginTop: 8 }}>
          <span class="tb3-brand">TB3</span> v{APP_VERSION}
        </p>
      </div>

      {showDeleteConfirm && (
        <ConfirmDialog
          title="Delete All Data"
          message="This will permanently delete all your training data, settings, and history. This cannot be undone."
          confirmLabel="Delete Everything"
          danger
          onConfirm={handleDeleteAll}
          onCancel={() => setShowDeleteConfirm(false)}
        />
      )}
    </div>
  );
}

function VoiceSettings({ profile }: { profile: any }) {
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([]);

  useEffect(() => {
    setVoices(getAvailableVoices());
    const onChanged = () => setVoices(getAvailableVoices());
    speechSynthesis.addEventListener('voiceschanged', onChanged);
    return () => speechSynthesis.removeEventListener('voiceschanged', onChanged);
  }, []);

  return (
    <>
      <div class="settings-row">
        <span class="settings-row-label">Voice Countdown</span>
        <div class="toggle-group" role="radiogroup" aria-label="Voice countdown announcements">
          <button
            class={`toggle-option${profile.voiceAnnouncements ? ' active' : ''}`}
            role="radio"
            aria-checked={profile.voiceAnnouncements}
            onClick={() => updateAppData((d) => ({
              ...d,
              profile: { ...d.profile, voiceAnnouncements: true, lastModified: new Date().toISOString() },
            }))}
          >
            On
          </button>
          <button
            class={`toggle-option${!profile.voiceAnnouncements ? ' active' : ''}`}
            role="radio"
            aria-checked={!profile.voiceAnnouncements}
            onClick={() => updateAppData((d) => ({
              ...d,
              profile: { ...d.profile, voiceAnnouncements: false, lastModified: new Date().toISOString() },
            }))}
          >
            Off
          </button>
        </div>
      </div>
      {profile.voiceAnnouncements && voices.length > 0 && (
        <div class="settings-row" style={{ flexWrap: 'wrap', gap: 8 }}>
          <span class="settings-row-label">Voice</span>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <div class="field" style={{ marginBottom: 0 }}>
              <select
                value={profile.voiceName ?? ''}
                onChange={(e) => {
                  const val = (e.target as HTMLSelectElement).value || null;
                  updateAppData((d) => ({
                    ...d,
                    profile: { ...d.profile, voiceName: val, lastModified: new Date().toISOString() },
                  }));
                }}
                aria-label="Select voice"
              >
                <option value="">Default</option>
                {voices.map((v) => (
                  <option key={v.name} value={v.name}>{v.name}</option>
                ))}
              </select>
            </div>
            <button
              class="btn btn-secondary"
              style={{ whiteSpace: 'nowrap' }}
              onClick={() => speakTest('5, 4, 3, 2, 1. Go!', profile.voiceName)}
            >
              Test
            </button>
          </div>
        </div>
      )}
    </>
  );
}

function LiftEntry({
  name,
  lift,
  expanded,
  onToggle,
  onSave,
  profile,
}: {
  name: string;
  lift: any;
  expanded: boolean;
  onToggle: () => void;
  onSave: (w: string, r: string) => void;
  profile: any;
}) {
  const [weight, setWeight] = useState('');
  const [reps, setReps] = useState('');

  return (
    <div style={{ borderBottom: '1px solid var(--border)' }}>
      <button
        class="settings-row"
        onClick={onToggle}
        style={{ width: '100%', background: 'none', border: 'none', color: 'inherit' }}
        aria-expanded={expanded}
      >
        <span class="settings-row-label">{name}</span>
        <span class="settings-row-value">
          {lift ? `${Math.round(lift.workingMax)} lb` : 'Not set'}
        </span>
      </button>
      {expanded && (
        <div style={{ padding: '0 0 16px' }}>
          <fieldset>
            <legend>{name} — enter a recent heavy set</legend>
            <div style={{ display: 'flex', gap: 8 }}>
              <div class="field" style={{ flex: 1 }}>
                <label>Weight (lb)</label>
                <input
                  type="text"
                  inputMode="decimal"
                  value={weight}
                  onInput={(e) => setWeight((e.target as HTMLInputElement).value)}
                  placeholder={lift ? String(lift.weight) : '0'}
                />
              </div>
              <div class="field" style={{ flex: 1 }}>
                <label>Reps</label>
                <input
                  type="text"
                  inputMode="numeric"
                  value={reps}
                  onInput={(e) => setReps((e.target as HTMLInputElement).value)}
                  placeholder={lift ? String(lift.reps) : '0'}
                />
              </div>
            </div>
            <button
              class="btn btn-primary"
              style={{ marginTop: 8 }}
              onClick={() => {
                onSave(weight, reps);
                setWeight('');
                setReps('');
              }}
              disabled={!weight || !reps}
            >
              Save
            </button>
          </fieldset>
          {lift && (
            <div style={{ marginTop: 12 }}>
              <div style={{ fontSize: 14, color: 'var(--muted)', marginBottom: 8 }}>
                1RM: {Math.round(lift.oneRepMax)} lb | Working Max: {Math.round(lift.workingMax)} lb
              </div>
              <PercentageTable
                workingMax={lift.workingMax}
                roundingIncrement={profile.roundingIncrement}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
