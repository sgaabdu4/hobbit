import test from 'node:test';
import assert from 'node:assert/strict';
import { validateHabit, liveConfiguration } from './domain.mjs';

test('blank and oversized habits are rejected before session creation', () => {
  for (const habit of ['', '   ', 'x'.repeat(141), null]) {
    assert.throws(() => validateHabit({ habit, mode: 'Gentle' }));
  }
});

test('unknown intensity cannot silently enable stronger coaching', () => {
  assert.throws(() => validateHabit({ habit: 'Stretch', mode: 'unknown' }));
  assert.equal(validateHabit({ habit: ' Stretch ', mode: 'Gentle' }).habit, 'Stretch');
});

test('cosmetic decisions cannot complete a habit', () => {
  const config = liveConfiguration({ habit: 'Stretch', mode: 'Gentle' });
  for (const trigger of config.triggers) {
    assert.deepEqual(trigger.decisions.questions.map(q => q.name), trigger.event_type === 'session.input_transcript.delta' ? ['expression', 'call_control'] : ['expression']);
    assert.equal(trigger.decisions.questions.some(q => q.choices.some(c => c.value === 'completed')), false);
  }
});
