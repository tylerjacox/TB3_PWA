// Pure utility functions extracted from Session.tsx for testability

export function formatTimerDisplay(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

export function getRestDuration(data: { profile: { restTimerDefault: number }; computedSchedule: any; activeProgram: any }): number {
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
