import { useState, useEffect, useRef } from 'preact/hooks';
import { appData, updateAppData, currentLifts } from '../state';
import type { ActiveSessionState, SessionLog, SessionSet, ExerciseLog, ComputedExercise } from '../types';
import { generateId } from '../types';
import { getTemplate } from '../templates/definitions';
import { navigate } from '../router';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { IconMore, IconChevronLeft, IconChevronRight, IconCheck, IconClose } from '../components/Icons';
import { CastButton } from '../components/CastButton';
import { PlateDisplay } from '../components/PlateDisplay';
import { calculateBarbellPlates, calculateBeltPlates } from '../calculators/plates';
import {
  feedbackSetComplete, feedbackExerciseComplete, feedbackRestComplete,
  feedbackUndo, feedbackSessionComplete, feedbackVoiceMilestone,
} from '../services/feedback';

export function Session() {
  const data = appData.value;
  const { activeSession, activeProgram, computedSchedule } = data;
  const profile = data.profile;

  // If no active session, try to create one
  if (!activeSession && activeProgram && computedSchedule) {
    return <PreSessionSetup />;
  }

  if (!activeSession) {
    return (
      <div class="screen" style={{ padding: '48px 16px', textAlign: 'center' }}>
        <p style={{ color: 'var(--muted)' }}>No active program. Start one from the Program tab.</p>
        <button class="btn btn-primary" style={{ marginTop: 16 }} onClick={() => navigate('program')}>
          Go to Program
        </button>
      </div>
    );
  }

  // Check for stale session (>24h)
  const sessionAge = Date.now() - new Date(activeSession.startedAt).getTime();
  if (sessionAge > 24 * 60 * 60 * 1000 && activeSession.status === 'paused') {
    return <StaleSessionPrompt session={activeSession} />;
  }

  return <StrengthSessionView session={activeSession} />;
}

// --- Pre-Session Setup ---
function PreSessionSetup() {
  const data = appData.value;
  const { activeProgram, computedSchedule } = data;
  const template = getTemplate(activeProgram!.templateId);

  const currentWeek = computedSchedule!.weeks.find(
    (w) => w.weekNumber === activeProgram!.currentWeek,
  );
  const currentSessionDef = currentWeek?.sessions.find(
    (s) => s.sessionNumber === activeProgram!.currentSession,
  );

  if (!currentWeek || !currentSessionDef || !template) {
    return <div class="screen"><p>Session data not found.</p></div>;
  }

  const hasSetRange = template.hasSetRange && currentWeek.setsRange[0] !== currentWeek.setsRange[1];
  const targetSets = currentWeek.setsRange[1]; // always start with max

  function startSession() {
    const exercises = currentSessionDef!.exercises.map((ex) => {
      const reps = currentWeek!.repsPerSet;
      return {
        liftName: ex.liftName,
        targetWeight: ex.targetWeight,
        targetSets,
        targetReps: reps,
        plateBreakdown: ex.plateBreakdownPerSide,
      };
    });

    // Generate sets
    const sets: SessionSet[] = [];
    for (let ei = 0; ei < exercises.length; ei++) {
      const ex = exercises[ei];
      for (let si = 0; si < ex.targetSets; si++) {
        const targetReps = Array.isArray(ex.targetReps)
          ? ex.targetReps[si] ?? ex.targetReps[0]
          : ex.targetReps;
        sets.push({
          exerciseIndex: ei,
          setNumber: si + 1,
          targetReps,
          actualReps: null,
          completed: false,
          completedAt: null,
        });
      }
    }

    const now = new Date().toISOString();
    const session: ActiveSessionState = {
      status: 'in_progress',
      templateId: activeProgram!.templateId,
      programWeek: activeProgram!.currentWeek,
      programSession: activeProgram!.currentSession,
      startedAt: now,
      currentExerciseIndex: 0,
      exercises,
      sets,
      ...(hasSetRange ? { setsRange: currentWeek!.setsRange } : {}),
      weightOverrides: {},
      exerciseStartTimes: { 0: now },
      timerState: null,
    };

    updateAppData((d) => ({ ...d, activeSession: session }));
  }

  return (
    <div class="screen" style={{ textAlign: 'center', paddingTop: 32 }}>
      <h2 style={{ fontSize: 22, marginBottom: 4 }}>
        Week {activeProgram!.currentWeek} — Session {activeProgram!.currentSession}
      </h2>
      <p style={{ color: 'var(--muted)', marginBottom: 24 }}>
        {currentWeek.percentage}% — {currentWeek.setsRange[0] === currentWeek.setsRange[1]
          ? currentWeek.setsRange[0]
          : `${currentWeek.setsRange[0]}-${currentWeek.setsRange[1]}`}x
        {Array.isArray(currentWeek.repsPerSet) ? currentWeek.repsPerSet.join(',') : currentWeek.repsPerSet}
      </p>

      {/* Session exercises preview */}
      {currentSessionDef.exercises.map((ex, i) => (
        <div key={i} class="card" style={{ textAlign: 'left' }}>
          <div class="exercise-name">{ex.liftName}</div>
          <div style={{ fontSize: 24, fontWeight: 700 }}>
            {ex.targetWeight > 0 ? `${ex.targetWeight} lb` : 'Not set'}
          </div>
          <div style={{ fontSize: 13, color: 'var(--muted)' }}>{ex.plateBreakdown}</div>
        </div>
      ))}

      <button class="btn btn-primary btn-large" style={{ marginTop: 16 }} onClick={startSession}>
        Start Session
      </button>
      <button class="btn btn-ghost" style={{ marginTop: 8 }} onClick={() => navigate('home')}>
        Back
      </button>
    </div>
  );
}

// --- Strength Session View ---
function StrengthSessionView({ session }: { session: ActiveSessionState }) {
  const [showMenu, setShowMenu] = useState(false);
  const [showEndConfirm, setShowEndConfirm] = useState(false);
  const [undoSet, setUndoSet] = useState<number | null>(null);
  const undoTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { exercises, sets, currentExerciseIndex, weightOverrides } = session;
  const currentEx = exercises[currentExerciseIndex];
  const exSets = sets.filter((s) => s.exerciseIndex === currentExerciseIndex);
  const completedSetsForEx = exSets.filter((s) => s.completed).length;
  const nextSet = exSets.find((s) => !s.completed);
  const allExSetsComplete = completedSetsForEx === exSets.length;
  const canFinishEarly = !!session.setsRange
    && completedSetsForEx >= session.setsRange[0]
    && !allExSetsComplete;

  // Two-phase timer state (rest count-up / exercise count-up)
  const [timerDisplay, setTimerDisplay] = useState<{
    phase: 'rest' | 'exercise';
    elapsed: number;
    isOvertime: boolean;
    restDuration: number | null;
  } | null>(null);
  const lastAnnouncedRef = useRef<number | null>(null);
  const restCompleteFiredRef = useRef(false);

  useEffect(() => {
    if (!session.timerState) {
      setTimerDisplay(null);
      lastAnnouncedRef.current = null;
      restCompleteFiredRef.current = false;
      return;
    }

    const { phase, startedAt, restDurationSeconds } = session.timerState;

    // Reset the "Go" fired flag when entering a new rest phase
    if (phase === 'rest') {
      restCompleteFiredRef.current = false;
    }

    const interval = setInterval(() => {
      const elapsed = Math.max(0, Date.now() - startedAt);

      if (phase === 'rest' && restDurationSeconds != null) {
        const restMs = restDurationSeconds * 1000;
        const isOvertime = elapsed >= restMs;
        const remaining = restMs - elapsed;

        // Voice milestone announcements (countdown from set time)
        if (!isOvertime && remaining > 0) {
          const sec = Math.ceil(remaining / 1000);
          if (sec !== lastAnnouncedRef.current) {
            const announced = feedbackVoiceMilestone(remaining);
            if (announced !== null) lastAnnouncedRef.current = announced;
          }
        }

        // Fire "Go" feedback exactly once when crossing into overtime
        if (isOvertime && !restCompleteFiredRef.current) {
          restCompleteFiredRef.current = true;
          feedbackRestComplete();
        }

        setTimerDisplay({ phase: 'rest', elapsed, isOvertime, restDuration: restDurationSeconds });
      } else {
        // Exercise phase: just count up
        setTimerDisplay({ phase: 'exercise', elapsed, isOvertime: false, restDuration: null });
      }
    }, 250);
    return () => clearInterval(interval);
  }, [session.timerState?.phase, session.timerState?.startedAt]);

  function completeSet() {
    // --- REST PHASE: transition to exercise phase (don't record a set) ---
    if (session.timerState?.phase === 'rest') {
      updateAppData((d) => ({
        ...d,
        activeSession: d.activeSession
          ? {
              ...d.activeSession,
              timerState: { phase: 'exercise', startedAt: Date.now(), restDurationSeconds: null },
            }
          : null,
      }));
      return;
    }

    // --- EXERCISE PHASE or NO TIMER: record the set, start rest ---
    if (!nextSet) return;
    feedbackSetComplete();

    const updatedSets = sets.map((s) =>
      s === nextSet
        ? { ...s, completed: true, actualReps: s.targetReps, completedAt: new Date().toISOString() }
        : s,
    );

    // Start rest timer (count-up with set time reference)
    const restDuration = getRestDuration(appData.value);
    const timerState = restDuration > 0
      ? { phase: 'rest' as const, startedAt: Date.now(), restDurationSeconds: restDuration }
      : null;

    // Set undo
    setUndoSet(nextSet.setNumber);
    if (undoTimer.current) clearTimeout(undoTimer.current);
    undoTimer.current = setTimeout(() => setUndoSet(null), 10000);

    const newCompletedCount = updatedSets.filter(
      (s) => s.exerciseIndex === currentExerciseIndex && s.completed,
    ).length;
    const allDone = newCompletedCount === exSets.length;

    if (allDone) {
      feedbackExerciseComplete();
    }

    updateAppData((d) => ({
      ...d,
      activeSession: d.activeSession
        ? { ...d.activeSession, sets: updatedSets, timerState }
        : null,
    }));

    // Auto-advance after all sets complete (1.5s delay)
    if (allDone && currentExerciseIndex < exercises.length - 1) {
      setTimeout(() => {
        updateAppData((d) => {
          if (!d.activeSession) return d;
          const nextIndex = d.activeSession.currentExerciseIndex + 1;
          const startTimes = { ...d.activeSession.exerciseStartTimes };
          if (!startTimes[nextIndex]) {
            startTimes[nextIndex] = new Date().toISOString();
          }
          return {
            ...d,
            activeSession: { ...d.activeSession, currentExerciseIndex: nextIndex, timerState: null, exerciseStartTimes: startTimes },
          };
        });
      }, 1500);
    }

    // Check if ALL exercises are done
    const allExercisesDone = updatedSets.every((s) => s.completed);
    if (allExercisesDone) {
      setTimeout(() => completeSession(updatedSets), 1500);
    }
  }

  function handleUndo() {
    if (undoSet === null) return;
    feedbackUndo();
    const updatedSets = sets.map((s) =>
      s.exerciseIndex === currentExerciseIndex && s.setNumber === undoSet
        ? { ...s, completed: false, actualReps: null, completedAt: null }
        : s,
    );
    updateAppData((d) => ({
      ...d,
      activeSession: d.activeSession ? { ...d.activeSession, sets: updatedSets, timerState: null } : null,
    }));
    setUndoSet(null);
  }

  function finishExercise() {
    feedbackExerciseComplete();
    // Remove incomplete sets for the current exercise
    const updatedSets = sets.filter(
      (s) => !(s.exerciseIndex === currentExerciseIndex && !s.completed),
    );

    const isLastExercise = currentExerciseIndex >= exercises.length - 1;

    if (isLastExercise) {
      // All exercises done — complete the session
      updateAppData((d) => ({
        ...d,
        activeSession: d.activeSession
          ? { ...d.activeSession, sets: updatedSets, timerState: null }
          : null,
      }));
      setTimeout(() => completeSession(updatedSets), 300);
    } else {
      // Advance to next exercise
      const nextIndex = currentExerciseIndex + 1;
      updateAppData((d) => {
        if (!d.activeSession) return d;
        const startTimes = { ...d.activeSession.exerciseStartTimes };
        if (!startTimes[nextIndex]) {
          startTimes[nextIndex] = new Date().toISOString();
        }
        return {
          ...d,
          activeSession: {
            ...d.activeSession,
            sets: updatedSets,
            currentExerciseIndex: nextIndex,
            timerState: null,
            exerciseStartTimes: startTimes,
          },
        };
      });
    }
    setUndoSet(null);
  }

  function completeSession(finalSets?: SessionSet[]) {
    feedbackSessionComplete();
    const useSets = finalSets || sets;
    const sessionEndTime = new Date();
    const startTimes = session.exerciseStartTimes || {};

    // Convert to SessionLog with per-exercise durations
    const exerciseLogs: ExerciseLog[] = exercises.map((ex, ei) => {
      const exSets = useSets.filter((s) => s.exerciseIndex === ei);
      const actualWeight = weightOverrides[ei] ?? ex.targetWeight;

      // Calculate duration: from this exercise's start to the next exercise's start (or session end)
      let durationSeconds: number | undefined;
      const exStart = startTimes[ei];
      if (exStart) {
        const nextStart = startTimes[ei + 1];
        const endTime = nextStart ? new Date(nextStart).getTime() : sessionEndTime.getTime();
        durationSeconds = Math.round((endTime - new Date(exStart).getTime()) / 1000);
      }

      return {
        liftName: ex.liftName,
        targetWeight: ex.targetWeight,
        actualWeight,
        sets: exSets.map((s) => ({
          targetReps: s.targetReps,
          actualReps: s.actualReps ?? 0,
          completed: s.completed,
        })),
        durationSeconds,
      };
    });

    const anyCompleted = useSets.some((s) => s.completed);
    const allCompleted = useSets.every((s) => s.completed);
    const totalDurationSeconds = Math.round((sessionEndTime.getTime() - new Date(session.startedAt).getTime()) / 1000);

    const log: SessionLog = {
      id: generateId(),
      date: new Date().toISOString().slice(0, 10),
      templateId: session.templateId,
      week: session.programWeek,
      sessionNumber: session.programSession,
      status: allCompleted ? 'completed' : anyCompleted ? 'partial' : 'skipped',
      startedAt: session.startedAt,
      completedAt: sessionEndTime.toISOString(),
      exercises: exerciseLogs,
      notes: '',
      durationSeconds: totalDurationSeconds,
      lastModified: sessionEndTime.toISOString(),
    };

    // Advance program
    updateAppData((d) => {
      const program = d.activeProgram;
      if (!program) return { ...d, activeSession: null, sessionHistory: [...d.sessionHistory, log] };

      const template = getTemplate(program.templateId);
      let nextSession = program.currentSession + 1;
      let nextWeek = program.currentWeek;

      if (template && nextSession > template.sessionsPerWeek) {
        nextSession = 1;
        nextWeek++;
      }

      return {
        ...d,
        activeSession: null,
        sessionHistory: [...d.sessionHistory, log],
        activeProgram: {
          ...program,
          currentWeek: nextWeek,
          currentSession: nextSession,
          lastModified: new Date().toISOString(),
        },
      };
    });

    navigate('home');
  }

  function goToExercise(index: number) {
    if (index < 0 || index >= exercises.length) return;
    updateAppData((d) => {
      if (!d.activeSession) return d;
      const startTimes = { ...d.activeSession.exerciseStartTimes };
      if (!startTimes[index]) {
        startTimes[index] = new Date().toISOString();
      }
      return {
        ...d,
        activeSession: { ...d.activeSession, currentExerciseIndex: index, timerState: null, exerciseStartTimes: startTimes },
      };
    });
  }

  const displayWeight = weightOverrides[currentExerciseIndex] ?? currentEx.targetWeight;
  const plateResult = currentEx.liftName === 'Weighted Pull-up'
    ? calculateBeltPlates(displayWeight, appData.value.profile.plateInventoryBelt)
    : calculateBarbellPlates(displayWeight, appData.value.profile.barbellWeight, appData.value.profile.plateInventoryBarbell);

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Top bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px' }}>
        <div style={{ fontSize: 14, color: 'var(--muted)' }}>
          Week {session.programWeek} — Session {session.programSession}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          <CastButton />
          <button
            class="btn btn-ghost"
            style={{ padding: '8px' }}
            onClick={() => setShowMenu(!showMenu)}
            aria-label="Session actions"
          >
            <IconMore />
          </button>
        </div>
      </div>

      {/* Exercise dots */}
      <div class="pager-dots">
        {exercises.map((ex, i) => {
          const exSetsComplete = sets.filter((s) => s.exerciseIndex === i && s.completed).length;
          const exTotalSets = sets.filter((s) => s.exerciseIndex === i).length;
          const isDone = exSetsComplete === exTotalSets;
          return (
            <button
              key={i}
              class={`pager-dot${i === currentExerciseIndex ? ' active' : ''}`}
              style={isDone ? { background: 'var(--success)' } : undefined}
              onClick={() => goToExercise(i)}
              aria-label={`Exercise ${i + 1} of ${exercises.length}, ${ex.liftName}${isDone ? ', complete' : ''}`}
            />
          );
        })}
      </div>

      {/* Exercise Card */}
      <div style={{ flex: 1, padding: '0 16px', overflow: 'auto' }}>
        <div class="exercise-card" role="group" aria-label={`${currentEx.liftName} exercise`}>
          <div class="exercise-name">{currentEx.liftName}</div>

          {/* Set dots */}
          <div class="set-dots" style={{ marginBottom: 16 }}>
            {exSets.map((s, i) => (
              <div
                key={i}
                class={`set-dot${s.completed ? ' completed' : ''}`}
                aria-label={`Set ${i + 1}, ${s.completed ? 'completed' : 'pending'}`}
              >
                {s.completed && <IconCheck />}
              </div>
            ))}
          </div>

          {/* Weight */}
          <div class="exercise-weight" aria-label={`${displayWeight} pounds`}>
            {displayWeight} <span style={{ fontSize: 18, fontWeight: 400, color: 'var(--muted)', marginLeft: 4 }}>lb</span>
          </div>

          {/* Plates */}
          <div class="exercise-plates">
            <PlateDisplay result={plateResult} isBodyweight={currentEx.liftName === 'Weighted Pull-up'} />
          </div>

          {/* Reps */}
          <div class="exercise-reps">
            {nextSet ? `x ${nextSet.targetReps} reps` : 'All sets complete'}
          </div>

          {/* Early finish — inside card, away from Complete Set button */}
          {canFinishEarly && (
            <button
              class="btn btn-ghost"
              style={{ marginTop: 16 }}
              onClick={finishExercise}
              aria-label={`Done with ${currentEx.liftName}, skip remaining sets`}
            >
              Done with {currentEx.liftName}
            </button>
          )}

          {/* Two-Phase Timer */}
          {timerDisplay && (
            <div
              class={`rest-timer${timerDisplay.isOvertime ? ' overtime' : ''}${timerDisplay.phase === 'exercise' ? ' exercise-phase' : ''}`}
              role="timer"
              aria-label={`${timerDisplay.phase === 'rest' ? 'Rest' : 'Exercise'} timer, ${Math.floor(timerDisplay.elapsed / 1000)} seconds`}
            >
              <div class="rest-timer-label">
                {timerDisplay.phase === 'rest' ? 'Rest' : 'Exercise Time'}
              </div>
              <div class="rest-timer-time">
                {formatTimerDisplay(timerDisplay.elapsed)}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Undo toast + Complete Set Button — pinned to bottom */}
      <div class="session-action-bar">
        {undoSet !== null && (
          <div class="undo-toast" role="alert" aria-live="assertive">
            <span>Set {undoSet} complete</span>
            <button class="undo-btn" onClick={handleUndo}>Undo</button>
          </div>
        )}
        <button
          class={`complete-set-btn${session.timerState?.phase === 'rest' ? ' rest-active' : ''}`}
          onClick={completeSet}
          disabled={!nextSet && session.timerState?.phase !== 'rest'}
          aria-label={
            session.timerState?.phase === 'rest'
              ? `Begin set ${nextSet ? nextSet.setNumber : ''}`
              : nextSet
                ? `Complete set ${nextSet.setNumber} of ${exSets.length}, ${currentEx.liftName} at ${displayWeight} pounds`
                : 'All sets complete'
          }
        >
          {session.timerState?.phase === 'rest'
            ? `Begin Set ${nextSet ? nextSet.setNumber : ''}`
            : nextSet
              ? `Complete Set ${nextSet.setNumber} / ${exSets.length}`
              : 'All Sets Done'
          }
        </button>
      </div>

      {/* Nav buttons */}
      {exercises.length > 1 && (
        <>
          {currentExerciseIndex > 0 && (
            <button
              class="pager-nav prev"
              onClick={() => goToExercise(currentExerciseIndex - 1)}
              aria-label={`Previous exercise, ${exercises[currentExerciseIndex - 1].liftName}`}
              style={{ position: 'fixed', left: 4, top: '50%' }}
            >
              <IconChevronLeft />
            </button>
          )}
          {currentExerciseIndex < exercises.length - 1 && (
            <button
              class="pager-nav next"
              onClick={() => goToExercise(currentExerciseIndex + 1)}
              aria-label={`Next exercise, ${exercises[currentExerciseIndex + 1].liftName}`}
              style={{ position: 'fixed', right: 4, top: '50%' }}
            >
              <IconChevronRight />
            </button>
          )}
        </>
      )}

      {/* Actions Menu */}
      {showMenu && (
        <>
          <div class="dialog-overlay" onClick={() => setShowMenu(false)} style={{ background: 'rgba(0,0,0,0.5)' }} />
          <div class="actions-menu">
            {nextSet && (
              <button class="actions-menu-item" onClick={() => { completeSet(); setShowMenu(false); }}>
                Complete Current Set
              </button>
            )}
            {timerDisplay && timerDisplay.phase === 'exercise' && (
              <button class="actions-menu-item" onClick={() => {
                updateAppData((d) => ({
                  ...d,
                  activeSession: d.activeSession ? { ...d.activeSession, timerState: null } : null,
                }));
                setShowMenu(false);
              }}>
                Stop Timer
              </button>
            )}
            <button class="actions-menu-item danger" onClick={() => { setShowMenu(false); setShowEndConfirm(true); }}>
              End Workout
            </button>
          </div>
        </>
      )}

      {/* End Workout Confirm */}
      {showEndConfirm && (
        <ConfirmDialog
          title="End Workout?"
          message="Your progress will be saved."
          confirmLabel="End Workout"
          onConfirm={() => { setShowEndConfirm(false); completeSession(); }}
          onCancel={() => setShowEndConfirm(false)}
        />
      )}
    </div>
  );
}

// --- Stale Session ---
function StaleSessionPrompt({ session }: { session: ActiveSessionState }) {
  function resume() {
    updateAppData((d) => ({
      ...d,
      activeSession: d.activeSession ? { ...d.activeSession, status: 'in_progress' } : null,
    }));
  }

  function discard() {
    const anyCompleted = session.sets.some((s) => s.completed);
    const log: SessionLog = {
      id: generateId(),
      date: new Date().toISOString().slice(0, 10),
      templateId: session.templateId,
      week: session.programWeek,
      sessionNumber: session.programSession,
      status: anyCompleted ? 'partial' : 'skipped',
      startedAt: session.startedAt,
      completedAt: new Date().toISOString(),
      exercises: [],
      notes: '',
      lastModified: new Date().toISOString(),
    };

    updateAppData((d) => ({
      ...d,
      activeSession: null,
      sessionHistory: [...d.sessionHistory, log],
    }));
    navigate('home');
  }

  return (
    <div class="screen" style={{ textAlign: 'center', paddingTop: 48 }}>
      <h2>Resume Workout?</h2>
      <p style={{ color: 'var(--muted)', margin: '8px 0 24px' }}>
        You have an unfinished session from{' '}
        {new Date(session.startedAt).toLocaleDateString()}.
      </p>
      <button class="btn btn-primary" style={{ marginBottom: 12, width: '100%' }} onClick={resume}>
        Resume
      </button>
      <button class="btn btn-danger" style={{ width: '100%' }} onClick={discard}>
        Discard
      </button>
    </div>
  );
}

function formatTimerDisplay(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

function getRestDuration(data: { profile: { restTimerDefault: number }; computedSchedule: any; activeProgram: any }): number {
  const defaultRest = data.profile.restTimerDefault;
  if (defaultRest > 0) return defaultRest;

  // Auto-detect from intensity
  const week = data.computedSchedule?.weeks.find(
    (w: any) => w.weekNumber === data.activeProgram?.currentWeek,
  );
  if (!week) return 120;
  if (week.percentage >= 90) return 180;
  if (week.percentage >= 70) return 120;
  return 90;
}
