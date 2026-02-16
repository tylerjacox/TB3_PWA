import { useState, useEffect, useRef } from 'preact/hooks';
import { appData, updateAppData, currentLifts } from '../state';
import type { ActiveSessionState, SessionLog, SessionSet, ExerciseLog, ComputedExercise } from '../types';
import { generateId } from '../types';
import { getTemplate } from '../templates/definitions';
import { navigate } from '../router';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { IconMore, IconChevronLeft, IconChevronRight, IconCheck, IconClose } from '../components/Icons';
import { PlateDisplay } from '../components/PlateDisplay';
import { calculateBarbellPlates, calculateBeltPlates } from '../calculators/plates';
import {
  feedbackSetComplete, feedbackExerciseComplete, feedbackRestComplete,
  feedbackUndo, feedbackSessionComplete,
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
  const [targetSets, setTargetSets] = useState(currentWeek.setsRange[1]);

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
      weightOverrides: {},
      exerciseStartTimes: { 0: now },
      restTimerState: null,
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

      {hasSetRange && (
        <div style={{ margin: '16px 0' }}>
          <p style={{ fontSize: 15, marginBottom: 8 }}>How many sets today?</p>
          <div style={{ display: 'flex', gap: 8, justifyContent: 'center' }}>
            {Array.from(
              { length: currentWeek.setsRange[1] - currentWeek.setsRange[0] + 1 },
              (_, i) => currentWeek.setsRange[0] + i,
            ).map((n) => (
              <button
                key={n}
                class={`btn ${targetSets === n ? 'btn-primary' : 'btn-secondary'}`}
                style={{ minWidth: 56, minHeight: 56 }}
                onClick={() => setTargetSets(n)}
              >
                {n}
              </button>
            ))}
          </div>
        </div>
      )}

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

  // Rest timer state
  const [restRemaining, setRestRemaining] = useState<number | null>(null);

  useEffect(() => {
    if (!session.restTimerState?.running || !session.restTimerState.targetEndTime) {
      setRestRemaining(null);
      return;
    }
    const interval = setInterval(() => {
      const remaining = Math.max(0, session.restTimerState!.targetEndTime! - Date.now());
      setRestRemaining(remaining);
      if (remaining <= 0) {
        feedbackRestComplete();
        updateAppData((d) => ({
          ...d,
          activeSession: d.activeSession
            ? { ...d.activeSession, restTimerState: null }
            : null,
        }));
      }
    }, 250);
    return () => clearInterval(interval);
  }, [session.restTimerState?.running, session.restTimerState?.targetEndTime]);

  function completeSet() {
    if (!nextSet) return;
    feedbackSetComplete();

    const updatedSets = sets.map((s) =>
      s === nextSet
        ? { ...s, completed: true, actualReps: s.targetReps, completedAt: new Date().toISOString() }
        : s,
    );

    // Start rest timer
    const profile = appData.value.profile;
    const template = getTemplate(session.templateId as any);
    const shouldShowRest = !template?.hideRestTimer && profile.restTimerDefault > 0;
    const restDuration = getRestDuration(appData.value);

    const restTimerState = shouldShowRest
      ? { running: true, targetEndTime: Date.now() + restDuration * 1000 }
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
        ? { ...d.activeSession, sets: updatedSets, restTimerState }
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
            activeSession: { ...d.activeSession, currentExerciseIndex: nextIndex, restTimerState: null, exerciseStartTimes: startTimes },
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
      activeSession: d.activeSession ? { ...d.activeSession, sets: updatedSets } : null,
    }));
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
        activeSession: { ...d.activeSession, currentExerciseIndex: index, restTimerState: null, exerciseStartTimes: startTimes },
      };
    });
  }

  function skipRestTimer() {
    updateAppData((d) => ({
      ...d,
      activeSession: d.activeSession ? { ...d.activeSession, restTimerState: null } : null,
    }));
    setRestRemaining(null);
  }

  function addRestTime() {
    updateAppData((d) => ({
      ...d,
      activeSession: d.activeSession?.restTimerState
        ? {
            ...d.activeSession,
            restTimerState: {
              ...d.activeSession.restTimerState,
              targetEndTime: (d.activeSession.restTimerState.targetEndTime || Date.now()) + 30000,
            },
          }
        : d.activeSession,
    }));
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
        <button
          class="btn btn-ghost"
          style={{ padding: '8px' }}
          onClick={() => setShowMenu(!showMenu)}
          aria-label="Session actions"
        >
          <IconMore />
        </button>
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

          {/* Rest Timer */}
          {restRemaining !== null && restRemaining > 0 && (
            <div class="rest-timer" role="timer" aria-label={`Rest timer, ${Math.ceil(restRemaining / 1000)} seconds`}>
              <div class="rest-timer-time">
                {Math.floor(restRemaining / 60000)}:{String(Math.floor((restRemaining % 60000) / 1000)).padStart(2, '0')}
              </div>
              <div class="rest-timer-controls">
                <button class="btn btn-secondary" onClick={addRestTime} aria-label="Add 30 seconds to rest timer">
                  +30s
                </button>
                <button class="btn btn-secondary" onClick={skipRestTimer} aria-label="Skip rest timer">
                  Skip
                </button>
              </div>
            </div>
          )}

          {/* Complete Set Button */}
          <button
            class="complete-set-btn"
            onClick={completeSet}
            disabled={!nextSet}
            aria-label={nextSet
              ? `Complete set ${nextSet.setNumber} of ${exSets.length}, ${currentEx.liftName} at ${displayWeight} pounds`
              : 'All sets complete'
            }
          >
            {nextSet ? `Complete Set ${nextSet.setNumber} / ${exSets.length}` : 'All Sets Done'}
          </button>
        </div>
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

      {/* Undo toast */}
      {undoSet !== null && (
        <div class="undo-toast" role="alert" aria-live="assertive">
          <span>Set {undoSet} complete</span>
          <button class="undo-btn" onClick={handleUndo}>Undo</button>
        </div>
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
            {restRemaining !== null && (
              <button class="actions-menu-item" onClick={() => { skipRestTimer(); setShowMenu(false); }}>
                Skip Rest Timer
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
