import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';

test('hosted HTTP behind TLS protects routes and restores habits and push registration after restart', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'hobbit-hosted-'));
  const probe = createServer();
  probe.listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const secret = 'test-pairing-secret-'.repeat(3);
  let child;
  const stop = async () => {
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    await exited;
  };
  t.after(async () => { await stop(); rmSync(directory, { recursive: true, force: true }); });
  async function start() {
    child = spawn(process.execPath, [fileURLToPath(new URL('./server.mjs', import.meta.url))], {
      cwd: directory,
      env: { PATH: process.env.PATH, HOBBIT_HOSTED: 'true', HOBBIT_DATA_DIR: directory, HOBBIT_DEVICE_SECRET: secret,
        PORT: String(port), OPENAI_API_KEY: 'test-only', APNS_KEY_P8: 'test-only', APNS_KEY_ID: 'test', APNS_TEAM_ID: 'test' },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Hosted test server did not start.')), 10000);
      child.stdout.once('data', () => { clearTimeout(timer); resolve(); });
      child.once('exit', code => { clearTimeout(timer); reject(new Error(`Hosted test server exited: ${code}`)); });
      child.once('error', reject);
    });
  }
  const request = (path, method = 'GET', body, token = secret) => fetch(`http://127.0.0.1:${port}${path}`, {
    method, headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000)
  });
  await start();
  assert.equal((await request('/healthz', 'GET', null, '')).status, 200);
  assert.equal((await request('/health', 'GET', null, 'wrong')).status, 401);
  assert.equal((await request('/device', 'POST', { token: 'a'.repeat(64) })).status, 200);
  const plan = { habit: 'Walk for one minute', mode: 'Gentle', hour: 15, minute: 0, timeZone: 'Europe/London', paused: true };
  assert.equal((await request('/habits/legacy', 'PUT', plan)).status, 200);
  const before = await (await request('/habits')).json();
  await stop();
  await start();
  assert.deepEqual(await (await request('/habits')).json(), before);
  assert.equal((await (await request('/health')).json()).deviceRegistered, true);
});
