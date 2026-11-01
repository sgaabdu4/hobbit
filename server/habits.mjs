import { validateSchedule, validateCompletedDays, nextCallAt } from './schedule.mjs';

export function migrateHabits(saved) {
  if (!saved) return [];
  if (saved.version === 2 && Array.isArray(saved.plans)) return saved.plans;
  return [{ ...saved, id: 'legacy' }];
}

export function updateHabit(plans, id, input) {
  const draft = validateSchedule(input);
  const current = plans.find(plan => plan.id === id);
  const now = Date.now();
  const date = nextCallAt({ ...draft, completedDays: [] }, now);
  if (!draft.paused) {
    for (const other of plans.filter(plan => plan.id !== id && !plan.paused)) {
      const otherDate = nextCallAt({ ...other, completedDays: [], lastAttemptDay: null }, now);
      const distance = Math.abs(date - otherDate) % 86400000;
      if (Math.min(distance, 86400000 - distance) < 300000) {
        throw new Error(`Choose a call time at least five minutes from "${other.habit}".`);
      }
    }
  }
  const plan = { ...draft, id, completedDays: current?.completedDays ?? [], lastAttemptDay: current?.lastAttemptDay ?? null, lastError: null };
  return current ? plans.map(value => value.id === id ? plan : value) : [...plans, plan];
}

export function updateHabitProgress(plans, id, days) {
  if (!plans.some(plan => plan.id === id)) throw new Error('This habit no longer exists. Return to Habits.');
  const completedDays = validateCompletedDays(days);
  return plans.map(plan => plan.id === id ? { ...plan, completedDays } : plan);
}

export function nextHabitCall(plans, now = Date.now()) {
  return plans.map(plan => ({ plan, due: nextCallAt(plan, now) }))
    .filter(entry => entry.due !== null).sort((a, b) => a.due - b.due)[0] ?? null;
}
