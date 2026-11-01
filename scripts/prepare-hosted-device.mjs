import { readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';

const url = new URL(process.env.HOBBIT_SERVER_URL || '');
if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
  throw new Error('HOBBIT_SERVER_URL must be a public HTTPS address without credentials or a query.');
}
url.pathname = url.pathname.replace(/\/$/, '') + '/';
const secret = process.env.HOBBIT_DEVICE_SECRET || readFileSync('.local/server-secret', 'utf8').trim();
if (secret.length < 32) throw new Error('A pairing secret of at least 32 characters is required.');
const response = await fetch(new URL('health', url), {
  headers: { authorization: 'Bearer ' + secret }, redirect: 'error', signal: AbortSignal.timeout(15000)
});
if (!response.ok) throw new Error(`Hosted server pairing failed (HTTP ${response.status}).`);
const health = await response.json();
if (!health.voiceReady || !health.pushReady) throw new Error('Configure voice and Apple push credentials before switching this phone.');
const path = 'Sources/Habitaker/Resources/DevelopmentConfig.json';
if (existsSync(path) && !existsSync('.local/device-config-before-hosting.json')) copyFileSync(path, '.local/device-config-before-hosting.json');
writeFileSync(path, JSON.stringify({ serverURL: url.href.replace(/\/$/, ''), deviceSecret: secret }), { mode: 0o600 });
console.log('Hosted HTTPS pairing verified. Rebuild and install the app to switch servers.');
