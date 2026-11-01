import test from 'node:test';
import assert from 'node:assert/strict';
import { nextCallAt, validateSchedule, validateCompletedDays } from './schedule.mjs';

const plan = { habit: 'Stretch for two minutes', mode: 'Gentle', hour: 15, minute: 0, timeZone: 'Europe/London', paused: false, completedDays: [] };
test('daily calls skip completed days and already attempted days', () => {
  const now = Date.parse('2026-11-01T14:00:00Z');
  assert.equal(nextCallAt(plan, now), Date.parse('2026-11-01T15:00:00Z'));
  assert.equal(nextCallAt({ ...plan, completedDays: ['2026-11-01'] }, now), Date.parse('2026-11-02T15:00:00Z'));
  assert.equal(nextCallAt({ ...plan, lastAttemptDay: '2026-11-01' }, now), Date.parse('2026-11-02T15:00:00Z'));
  assert.equal(nextCallAt({ ...plan, paused: true }, now), null);
});
test('daily calls retain local time across daylight saving changes', () => {
  assert.equal(nextCallAt(plan, Date.parse('2026-10-24T15:00:00Z')), Date.parse('2026-10-25T15:00:00Z'));
  assert.equal(nextCallAt(plan, Date.parse('2026-03-28T16:00:00Z')), Date.parse('2026-03-29T14:00:00Z'));
});
test('invalid schedules and malformed progress cannot be saved', () => {
  assert.throws(() => validateSchedule({ ...plan, hour: 25 }));
  assert.throws(() => validateSchedule({ ...plan, timeZone: 'wrong' }));
  assert.throws(() => validateCompletedDays(['2026-02-30']));
  assert.deepEqual(validateCompletedDays(['2026-11-01', '2026-11-01']), ['2026-11-01']);
});
