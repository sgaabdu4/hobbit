import test from 'node:test';
import assert from 'node:assert/strict';
import { migrateHabits, updateHabit, updateHabitProgress, nextHabitCall } from './habits.mjs';

const first = { id: 'first', habit: 'Stretch', mode: 'Gentle', hour: 10, minute: 0, timeZone: 'Europe/London', paused: false, completedDays: ['2026-10-31'] };
const second = { ...first, id: 'second', habit: 'Read', hour: 18, completedDays: [] };

test('old single habit migrates without losing progress or its time', () => {
  assert.deepEqual(migrateHabits(first), [{ ...first, id: 'legacy' }]);
  assert.deepEqual(migrateHabits({ version: 2, plans: [first, second] }), [first, second]);
});

test('adding, editing and completing habits do not affect another habit', () => {
  let plans = updateHabit([first], 'second', second);
  assert.equal(plans.length, 2);
  plans = updateHabit(plans, 'second', { ...second, mode: 'Aggressive' });
  plans = updateHabitProgress(plans, 'second', ['2026-11-01']);
  assert.deepEqual(plans[0], first);
  assert.deepEqual(plans[1].completedDays, ['2026-11-01']);
  assert.equal(plans[1].mode, 'Aggressive');
  assert.throws(() => updateHabitProgress(plans, 'missing', []));
});

test('the next call uses the right habit and skips only that completed habit', () => {
  const now = Date.parse('2026-11-01T09:00:00Z');
  assert.equal(nextHabitCall([second, first], now).plan.id, 'first');
  const completed = updateHabitProgress([first, second], 'first', ['2026-11-01']);
  assert.equal(nextHabitCall(completed, now).plan.id, 'second');
  assert.equal(nextHabitCall([{ ...first, paused: true }, second], now).plan.id, 'second');
  assert.equal(nextHabitCall([{ ...first, paused: true }], now), null);
});

test('overlapping calls are rejected, including across midnight', () => {
  assert.throws(() => updateHabit([first], 'second', { ...second, hour: 10, minute: 3 }), /five minutes/);
  assert.doesNotThrow(() => updateHabit([first], 'second', { ...second, hour: 10, minute: 5 }));
  assert.throws(() => updateHabit([{ ...first, hour: 23, minute: 58 }], 'second', { ...second, hour: 0, minute: 1 }), /five minutes/);
});
