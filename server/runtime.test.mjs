import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runtimeConfiguration, readState, writeState } from './runtime.mjs';
import { pushConfigured } from './apns.mjs';

test('hosted mode refuses ephemeral defaults and weak pairing secrets', () => {
  assert.throws(() => runtimeConfiguration({ HOBBIT_HOSTED: 'true' }), /persistent/);
  assert.throws(() => runtimeConfiguration({ HOBBIT_HOSTED: 'true', HOBBIT_DATA_DIR: '/tmp/hobbit', HOBBIT_DEVICE_SECRET: 'short' }), /pairing secret/);
});

test('hosted state persists independently of process memory and preserves private permissions', t => {
  const directory = mkdtempSync(join(tmpdir(), 'hobbit-runtime-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const env = { HOBBIT_HOSTED: 'true', HOBBIT_DATA_DIR: directory, HOBBIT_DEVICE_SECRET: 'a'.repeat(43), PORT: '10000' };
  const first = runtimeConfiguration(env);
  const schedule = { version: 2, plans: [{ id: 'legacy', habit: 'Walk', hour: 15, timeZone: 'Europe/London' }] };
  writeState(first.dataDirectory, 'schedule', schedule);
  writeState(first.dataDirectory, 'device', { token: 'abc123' });
  const restarted = runtimeConfiguration(env);
  assert.equal(restarted.port, 10000);
  assert.deepEqual(readState(restarted.dataDirectory, 'schedule', null), schedule);
  assert.deepEqual(readState(restarted.dataDirectory, 'device', {}), { token: 'abc123' });
  assert.equal(statSync(join(directory, 'schedule.json')).mode & 0o777, 0o600);
  assert.equal(readState(directory, 'missing', null), null);
});

test('Apple push accepts hosted secret material without a Mac file path', () => {
  assert.equal(pushConfigured({ APNS_KEY_P8: 'secret', APNS_KEY_ID: 'id', APNS_TEAM_ID: 'team' }), true);
  assert.equal(pushConfigured({ APNS_KEY_P8: 'secret', APNS_KEY_ID: 'id' }), false);
});
