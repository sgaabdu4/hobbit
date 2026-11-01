import { validateHabit } from './domain.mjs';

export function validateSchedule(input) {
  const habit = validateHabit(input);
  if (!Number.isInteger(input.hour) || input.hour < 0 || input.hour > 23 || !Number.isInteger(input.minute) || input.minute < 0 || input.minute > 59) throw new Error('Choose a valid daily call time.');
  if (typeof input.timeZone !== 'string') throw new Error('Choose a time zone.');
  Temporal.Now.zonedDateTimeISO(input.timeZone);
  if (typeof input.paused !== 'boolean') throw new Error('Choose whether calls are paused.');
  return { ...habit, hour: input.hour, minute: input.minute, timeZone: input.timeZone, paused: input.paused };
}

export function dayKey(now, timeZone) {
  return Temporal.Instant.fromEpochMilliseconds(now).toZonedDateTimeISO(timeZone).toPlainDate().toString();
}

export function nextCallAt(plan, now = Date.now()) {
  if (!plan || plan.paused) return null;
  const local = Temporal.Instant.fromEpochMilliseconds(now).toZonedDateTimeISO(plan.timeZone);
  let day = local.toPlainDate();
  for (let offset = 0; offset < 370; offset++) {
    const key = day.toString();
    const candidate = day.toZonedDateTime({ timeZone: plan.timeZone, plainTime: { hour: plan.hour, minute: plan.minute } });
    if (candidate.epochMilliseconds > now && key !== plan.lastAttemptDay && !plan.completedDays?.includes(key)) return candidate.epochMilliseconds;
    day = day.add({ days: 1 });
  }
  throw new Error('A next call time could not be found.');
}

export function validateCompletedDays(value) {
  if (!Array.isArray(value) || value.length > 730 || value.some(day => typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day))) throw new Error('Progress could not be saved.');
  for (const day of value) Temporal.PlainDate.from(day);
  return [...new Set(value)].sort();
}
