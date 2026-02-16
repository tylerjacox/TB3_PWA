import type { ComputedSession, ComputedWeek } from '../types';
import type { PlateResult } from '../calculators/plates';
import { PlateDisplay } from './PlateDisplay';

const BODYWEIGHT_LIFTS = ['Weighted Pull-up'];

export function SessionPreview({
  session,
  week,
  sessionLabel,
  compact,
}: {
  session: ComputedSession;
  week: ComputedWeek;
  sessionLabel?: string;
  compact?: boolean;
}) {
  const setsLabel = week.setsRange[0] === week.setsRange[1]
    ? `${week.setsRange[0]}`
    : `${week.setsRange[0]}-${week.setsRange[1]}`;
  const repsLabel = Array.isArray(week.repsPerSet)
    ? week.repsPerSet.join(',')
    : `${week.repsPerSet}`;

  return (
    <div class="session-item">
      <div class="session-item-header">
        {sessionLabel || `Session ${session.sessionNumber}`} — {setsLabel}x{repsLabel} @ {week.percentage}%
      </div>
      {session.exercises.map((ex, i) => {
        const isBodyweight = BODYWEIGHT_LIFTS.includes(ex.liftName);
        const hasPlates = ex.plateBreakdownPerSide && ex.plateBreakdownPerSide.length > 0;

        // Reconstruct PlateResult from stored data
        const plateResult: PlateResult | null = hasPlates ? {
          plates: ex.plateBreakdownPerSide,
          displayText: ex.plateBreakdown,
          achievable: ex.achievable,
          isBarOnly: false,
          isBodyweightOnly: false,
          isBelowBar: false,
        } : null;

        // Check special cases from the breakdown text
        const isBarOnly = ex.plateBreakdown === 'Bar only';
        const isBodyweightOnly = ex.plateBreakdown === 'Bodyweight only';

        return (
          <div key={i} class="session-exercise-block">
            <div class="session-exercise">
              <span class="session-exercise-name">{ex.liftName}</span>
              <span class="session-exercise-weight">
                {ex.targetWeight > 0 ? `${ex.targetWeight} lb` : ''}
              </span>
            </div>
            {!compact && plateResult && (
              <PlateDisplay result={plateResult} isBodyweight={isBodyweight} />
            )}
            {!compact && isBarOnly && (
              <span class="plate-status-text">Bar only</span>
            )}
            {!compact && isBodyweightOnly && (
              <span class="plate-status-text">Bodyweight only</span>
            )}
            {!compact && !ex.achievable && !hasPlates && ex.targetWeight > 0 && (
              <span class="plate-status-text text-error">{ex.plateBreakdown}</span>
            )}
          </div>
        );
      })}
    </div>
  );
}
