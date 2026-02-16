import { signal, effect } from '@preact/signals';
import { appData } from '../state';
import type { ActiveSessionState, UserProfile } from '../types';

// --- Cast State ---

export const castState = signal<{
  available: boolean;
  connected: boolean;
  loading: boolean;
  deviceName: string | null;
}>({
  available: false,
  connected: false,
  loading: false,
  deviceName: null,
});

const CAST_APP_ID = '6BA96B8F';
const CAST_NAMESPACE = 'urn:x-cast:com.tb3.workout';

let sdkLoaded = false;
let sdkLoading = false;

// --- SDK Injection (lazy, like auth.ts pattern) ---

export function initCast(): void {
  if (sdkLoaded || sdkLoading) return;

  // Cast SDK only works in Chrome-based browsers
  if (!('chrome' in window) || /Firefox|Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent)) {
    return;
  }

  sdkLoading = true;
  castState.value = { ...castState.value, loading: true };

  window.__onGCastApiAvailable = (isAvailable: boolean) => {
    sdkLoading = false;
    sdkLoaded = true;

    if (!isAvailable) {
      castState.value = { available: false, connected: false, loading: false, deviceName: null };
      return;
    }

    const ctx = cast.framework.CastContext.getInstance();
    ctx.setOptions({
      receiverApplicationId: CAST_APP_ID,
      autoJoinPolicy: chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED,
    });

    ctx.addEventListener(
      cast.framework.CastContextEventType.SESSION_STATE_CHANGED,
      onSessionStateChanged,
    );

    castState.value = { available: true, connected: false, loading: false, deviceName: null };
  };

  const script = document.createElement('script');
  script.src = 'https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1';
  script.async = true;
  document.head.appendChild(script);
}

function onSessionStateChanged(event: any) {
  const state = event.sessionState;
  const { SESSION_STARTED, SESSION_RESUMED, SESSION_ENDED, SESSION_START_FAILED } = cast.framework.SessionState;

  if (state === SESSION_STARTED || state === SESSION_RESUMED) {
    const session = cast.framework.CastContext.getInstance().getCurrentSession();
    const name = session?.getSessionObj().receiver.friendlyName ?? null;
    castState.value = { available: true, connected: true, loading: false, deviceName: name };
    // Send current state immediately on connect
    sendState();
  } else if (state === SESSION_ENDED || state === SESSION_START_FAILED) {
    castState.value = { ...castState.value, connected: false, loading: false, deviceName: null };
  }
}

// --- Message Building ---

function buildMessage(session: ActiveSessionState, profile: UserProfile): string {
  const { exercises, sets, currentExerciseIndex, weightOverrides, restTimerState } = session;
  const currentEx = exercises[currentExerciseIndex];
  const exSets = sets.filter((s) => s.exerciseIndex === currentExerciseIndex);
  const completedSets = exSets.filter((s) => s.completed).length;
  const nextSet = exSets.find((s) => !s.completed);
  const displayWeight = weightOverrides[currentExerciseIndex] ?? currentEx.targetWeight;

  // Build plate breakdown string
  const plateParts = currentEx.plateBreakdown
    .filter((p) => p.count > 0)
    .map((p) => `${p.weight}${p.count > 1 ? `x${p.count}` : ''}`);

  // Exercises summary
  const exercisesSummary = exercises.map((ex, i) => {
    const exS = sets.filter((s) => s.exerciseIndex === i);
    const done = exS.filter((s) => s.completed).length;
    return { name: ex.liftName, completedSets: done, totalSets: exS.length };
  });

  const payload = {
    exerciseName: currentEx.liftName,
    weight: displayWeight,
    unit: profile.unit,
    plateBreakdown: plateParts.join(' + '),
    currentSetNumber: completedSets + 1,
    totalSets: exSets.length,
    completedSets,
    targetReps: nextSet
      ? nextSet.targetReps
      : (exSets[exSets.length - 1]?.targetReps ?? 0),
    restTimer: restTimerState?.running
      ? {
          running: true,
          targetEndTime: restTimerState.targetEndTime,
          serverTimeNow: Date.now(),
        }
      : { running: false, targetEndTime: null, serverTimeNow: Date.now() },
    exercises: exercisesSummary,
    currentExerciseIndex,
    week: session.programWeek,
    session: session.programSession,
    templateId: session.templateId,
  };

  return JSON.stringify(payload);
}

function sendState(): void {
  if (!castState.value.connected) return;

  const data = appData.value;
  const session = data.activeSession;

  const castSession = cast.framework.CastContext.getInstance().getCurrentSession();
  if (!castSession) return;

  if (!session) {
    // Send idle message
    castSession.sendMessage(CAST_NAMESPACE, JSON.stringify({ idle: true })).catch(() => {});
    return;
  }

  const message = buildMessage(session, data.profile);
  castSession.sendMessage(CAST_NAMESPACE, message).catch(() => {});
}

// --- Reactive Sync ---

export function initCastSync(): void {
  effect(() => {
    // Access reactive values to subscribe
    const data = appData.value;
    const cs = castState.value;

    if (!cs.connected || !data.activeSession) return;

    sendState();
  });
}

// --- User Actions ---

export function requestCast(): void {
  if (!sdkLoaded) return;
  cast.framework.CastContext.getInstance().requestSession().catch(() => {});
}

export function stopCast(): void {
  if (!sdkLoaded) return;
  cast.framework.CastContext.getInstance().endCurrentSession(true);
  castState.value = { ...castState.value, connected: false, deviceName: null };
}
