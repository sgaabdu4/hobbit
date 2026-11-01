import http2 from 'node:http2';
import { readFileSync } from 'node:fs';
import { sign } from 'node:crypto';

export function pushConfigured(env = process.env) {
  return Boolean(env.APNS_KEY_FILE && env.APNS_KEY_ID && env.APNS_TEAM_ID);
}

export async function sendCallPush(token, callID, env = process.env) {
  if (!pushConfigured(env)) throw new Error('Apple push credentials are not configured.');
  const head = Buffer.from(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })).toString('base64url');
  const message = `${head}.${body}`;
  const signature = sign('sha256', Buffer.from(message), {
    key: readFileSync(env.APNS_KEY_FILE), dsaEncoding: 'ieee-p1363'
  }).toString('base64url');
  const host = env.APNS_ENVIRONMENT === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  await new Promise((resolve, reject) => {
    const connection = http2.connect(host);
    let settled = false;
    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      connection.close();
      if (error) reject(error); else resolve();
    };
    const timer = setTimeout(() => { connection.destroy(); finish(new Error('Apple push delivery timed out.')); }, 10000);
    connection.on('error', () => finish(new Error('Could not connect to Apple push service.')));
    const request = connection.request({
      ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${message}.${signature}`,
      'apns-topic': `${env.APNS_BUNDLE_ID || 'app.habitaker.authproof'}.voip`,
      'apns-push-type': 'voip', 'apns-priority': '10', 'apns-expiration': '0'
    });
    let status;
    let response = '';
    request.on('response', headers => { status = headers[':status']; });
    request.on('data', chunk => { if (response.length < 4096) response += chunk; });
    request.on('error', () => finish(new Error('Apple push request failed.')));
    request.on('end', () => {
      if (status === 200) return finish();
      let reason = '';
      try { reason = JSON.parse(response).reason || ''; } catch {}
      finish(new Error(`Apple rejected the call invitation (HTTP ${status}, ${reason}).`));
    });
    request.end(JSON.stringify({ aps: { 'content-available': 1 }, call_id: callID, caller: 'Pip' }));
  });
}
