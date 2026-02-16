import { useState } from 'preact/hooks';
import { appData } from '../state';
import { navigate } from '../router';
import { getTemplate } from '../templates/definitions';
import { IconChevronDown } from '../components/Icons';
import { MaxChart } from '../components/MaxChart';

function formatDuration(seconds: number): string {
  if (seconds >= 3600) {
    const h = Math.floor(seconds / 3600);
    const m = Math.round((seconds % 3600) / 60);
    return `${h}h ${m}m`;
  }
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${s}s`;
}

export function History() {
  const { sessionHistory, maxTestHistory } = appData.value;
  const [expandedSession, setExpandedSession] = useState<string | null>(null);

  // Sort newest first
  const sortedSessions = [...sessionHistory].sort(
    (a, b) => new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime(),
  );
  const sortedTests = [...maxTestHistory].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
  );

  if (!sortedSessions.length && !sortedTests.length) {
    return (
      <div class="screen">
        <div class="screen-header"><h1>History</h1></div>
        <div class="empty-state">
          <p>No training history yet. Complete a workout to see it here.</p>
          <button class="btn btn-primary" onClick={() => navigate('home')}>
            Go to Dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div class="screen">
      <div class="screen-header"><h1>History</h1></div>

      {/* 1RM Progression Chart */}
      {sortedTests.length >= 2 && (
        <div class="settings-group">
          <div class="settings-group-title">1RM Progression</div>
          <MaxChart tests={sortedTests} />
        </div>
      )}

      {/* 1RM Test Log */}
      {sortedTests.length > 0 && (
        <div class="settings-group">
          <div class="settings-group-title">1RM Test Log</div>
          <div role="list">
            {sortedTests.map((test) => (
              <div key={test.id} class="history-item" role="listitem"
                aria-label={`${new Date(test.date).toLocaleDateString()}. ${test.liftName}, ${test.weight} pounds, ${test.reps} reps, calculated 1RM ${Math.round(test.calculatedMax)} pounds, Working Max ${Math.round(test.workingMax)} pounds.`}
              >
                <div class="history-date">{new Date(test.date).toLocaleDateString()}</div>
                <div class="history-title">{test.liftName}</div>
                <div class="history-detail">
                  {test.weight} lb x {test.reps} reps — 1RM: {Math.round(test.calculatedMax)} lb
                  {' '}({test.maxType === 'training' ? 'TM' : 'True'}: {Math.round(test.workingMax)} lb)
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Completed Sessions */}
      {sortedSessions.length > 0 && (
        <div class="settings-group">
          <div class="settings-group-title">Completed Sessions</div>
          <div role="list">
            {sortedSessions.map((session) => {
              const template = getTemplate(session.templateId as any);
              const isExpanded = expandedSession === session.id;
              const durationStr = session.durationSeconds != null
                ? formatDuration(session.durationSeconds)
                : session.startedAt && session.completedAt
                  ? `${Math.round((new Date(session.completedAt).getTime() - new Date(session.startedAt).getTime()) / 60000)}m`
                  : null;

              return (
                <div key={session.id} class="history-item" role="listitem">
                  <button
                    style={{ width: '100%', background: 'none', border: 'none', color: 'inherit', textAlign: 'left', padding: 0 }}
                    onClick={() => setExpandedSession(isExpanded ? null : session.id)}
                    aria-expanded={isExpanded}
                  >
                    <div class="history-date">{new Date(session.date).toLocaleDateString()}</div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <div>
                        <div class="history-title">
                          {template?.name || session.templateId} — Week {session.week}, Session {session.sessionNumber}
                        </div>
                        <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 4 }}>
                          <span class={`status-badge status-${session.status}`}>
                            {session.status}
                          </span>
                          {durationStr !== null && (
                            <span style={{ fontSize: 13, color: 'var(--muted)' }}>
                              {durationStr}
                            </span>
                          )}
                        </div>
                      </div>
                      <IconChevronDown />
                    </div>
                  </button>

                  {isExpanded && (
                    <div style={{ marginTop: 8, paddingLeft: 0 }}>
                      {session.exercises.map((ex, i) => (
                        <div key={i} style={{ padding: '4px 0', fontSize: 14 }}>
                          <span style={{ fontWeight: 600 }}>{ex.liftName}</span>
                          <span style={{ color: 'var(--muted)' }}>
                            {' '}— {ex.actualWeight} lb, {ex.sets.filter((s) => s.completed).length}/{ex.sets.length} sets
                            {ex.durationSeconds != null && `, ${formatDuration(ex.durationSeconds)}`}
                          </span>
                        </div>
                      ))}
                      {session.notes && (
                        <div style={{ marginTop: 8, fontSize: 13, color: 'var(--muted)', fontStyle: 'italic' }}>
                          {session.notes}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
