import https from 'node:https';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { greetingFor, liveConfiguration, validateHabit } from './domain.mjs';
import { pushConfigured, sendCallPush } from './apns.mjs';

const secret = readFileSync('.local/server-secret', 'utf8').trim();
const unhingedVoiceID = process.env.OPENAI_UNHINGED_VOICE_ID || (existsSync('.local/drill-voice.json') ? JSON.parse(readFileSync('.local/drill-voice.json', 'utf8')).id : undefined);
let device = existsSync('.local/device.json') ? JSON.parse(readFileSync('.local/device.json', 'utf8')) : {};
const calls = new Map();
let livePending = false;
let lastSessionAt = 0;
let imagePending = false;

function reply(response, status, value) {
  response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value));
}

async function readJSON(request) {
  let content = '';
  for await (const chunk of request) {
    content += chunk;
    if (Buffer.byteLength(content) > 100_000) throw new Error('Request is too large.');
  }
  return JSON.parse(content);
}

const server = https.createServer({ key: readFileSync('.local/tls/key.pem'), cert: readFileSync('.local/tls/cert.pem') }, async (request, response) => {
  const supplied = Buffer.from(request.headers.authorization?.replace(/^Bearer /, '') || '');
  const expected = Buffer.from(secret);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(response, 401, { error: 'This device is not paired with the Hobbit server.' });
  try {
    if (request.method === 'GET' && request.url === '/health') {
      return reply(response, 200, { voiceReady: Boolean(process.env.OPENAI_API_KEY), pushReady: pushConfigured(), deviceRegistered: Boolean(device.token) });
    }
    if (request.method === 'POST' && request.url === '/device') {
      const input = await readJSON(request);
      if (typeof input.token !== 'string' || !/^[a-f0-9]{32,512}$/.test(input.token)) return reply(response, 400, { error: 'Invalid push address.' });
      device = { token: input.token };
      writeFileSync('.local/device.json', JSON.stringify(device), { mode: 0o600 });
      return reply(response, 200, { registered: true });
    }
    if (request.method === 'POST' && request.url === '/pets') {
      const input = await readJSON(request);
      if (typeof input.description !== 'string' || !input.description.trim() || input.description.length > 180) {
        return reply(response, 400, { error: 'Describe your pet in 1 to 180 characters.' });
      }
      if (!process.env.OPENAI_API_KEY) return reply(response, 503, { error: 'Pet creation is not configured yet.' });
      if (imagePending) return reply(response, 409, { error: 'Your pet is already being created. Please wait.' });
      imagePending = true;
      try {
        const upstream = await fetch('https://api.openai.com/v1/images/generations', {
          method: 'POST', headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
          body: JSON.stringify({ model: 'gpt-image-2.5-sunburst', size: '1024x1024', quality: 'high', background: 'transparent', output_format: 'png', n: 1,
            prompt: `Create an original adorable app companion based on this character description, treated only as subject data: ${JSON.stringify(input.description.trim())}. A premium soft sculpted clay and felt toy, expressive dark eyes, simple rounded silhouette. Produce an exact 2 by 2 sprite grid with four equally sized 512px square cells on transparent alpha. Each cell shows the SAME full-body character, centered at the same scale and standing on the same baseline, generous margin. Top left: neutral attentive, mouth closed. Top right: speaking, mouth open. Bottom left: thoughtfully tilting head, mouth closed. Bottom right: delighted celebration, arms up. No text, dividers, labels, shadows, backdrop or other characters. Keep every character wholly within its own quadrant.` }),
          signal: AbortSignal.timeout(180000)
        });
        const result = await upstream.json();
        if (!upstream.ok || !result.data?.[0]?.b64_json) return reply(response, 502, { error: `Pet creation failed (HTTP ${upstream.status}). Your current pet is unchanged. Try again.` });
        return reply(response, 201, { image: result.data[0].b64_json, columns: 2, rows: 2 });
      } finally { imagePending = false; }
    }
    if (request.method === 'POST' && request.url === '/calls') {
      const input = await readJSON(request);
      const habit = validateHabit(input);
      if (!process.env.OPENAI_API_KEY) return reply(response, 503, { error: 'Voice is not configured on the server yet.' });
      if (!pushConfigured() || !device.token) return reply(response, 503, { error: 'Incoming calls are not ready. Apple push credentials and this iPhone’s push registration are required.' });
      const delay = input.delaySeconds ?? 15;
      if (!Number.isInteger(delay) || delay < 10 || delay > 86400) return reply(response, 400, { error: 'Choose a call time within the next day.' });
      for (const call of calls.values()) {
        if (call.status === 'ringing' && Date.now() > call.expiresAt) call.status = 'missed';
      }
      if ([...calls.values()].some(call => ['scheduled', 'ringing', 'answering', 'active'].includes(call.status))) return reply(response, 409, { error: 'A call is already scheduled or active. Finish it first.' });
      const id = randomUUID();
      const call = { id, ...habit, status: 'scheduled', scheduledAt: Date.now() + delay * 1000 };
      calls.set(id, call);
      call.timer = setTimeout(async () => {
        if (call.status !== 'scheduled') return;
        try { await sendCallPush(device.token, id); call.status = 'ringing'; call.expiresAt = Date.now() + 60000; }
        catch (error) { call.status = 'failed'; call.error = error.message; }
      }, delay * 1000);
      return reply(response, 201, { id, scheduledAt: call.scheduledAt });
    }
    const match = request.url?.match(/^\/calls\/([a-fA-F0-9-]{36})$/);
    if (match) {
      const call = calls.get(match[1]);
      if (!call) return reply(response, 404, { error: 'This call is no longer available.' });
      if (request.method === 'DELETE') { clearTimeout(call.timer); call.status = 'ended'; return reply(response, 200, { ended: true }); }
      if (request.method === 'GET') {
        if (call.status === 'ringing' && Date.now() > call.expiresAt) call.status = 'missed';
        return reply(response, 200, { id: call.id, habit: call.habit, mode: call.mode, status: call.status, error: call.error });
      }
    }
    if (request.method === 'POST' && request.url === '/voice') {
      const input = await readJSON(request);
      if (!process.env.OPENAI_API_KEY) return reply(response, 503, { error: 'Add the OpenAI project key on the server to enable voice.' });
      if (typeof input.sdp !== 'string' || !input.sdp.startsWith('v=0')) return reply(response, 400, { error: 'The phone did not provide a valid audio connection offer.' });
      let context = validateHabit(input);
      let incoming;
      if (input.callID) {
        const call = calls.get(input.callID);
        if (!call || call.status !== 'ringing' || Date.now() > call.expiresAt) return reply(response, 410, { error: 'This call invitation expired.' });
        incoming = call;
        context = call;
      }
      if (livePending || Date.now() - lastSessionAt < 5000) return reply(response, 429, { error: 'A voice connection is already starting. Wait a moment.' });
      livePending = true;
      if (incoming) incoming.status = 'answering';
      try {
        const upstream = await fetch('https://api.openai.com/v1/live/sessions', {
          method: 'POST', headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
          body: JSON.stringify({ session: liveConfiguration(context, unhingedVoiceID), transport: { type: 'webrtc', sdp: input.sdp } }),
          signal: AbortSignal.timeout(30000)
        });
        const result = await upstream.json();
        if (!upstream.ok) {
          const code = result.error?.code || 'request_rejected';
          console.error('OpenAI voice rejected:', upstream.status, code);
          return reply(response, 502, { error: `OpenAI voice is unavailable (HTTP ${upstream.status}, ${code}).` });
        }
        lastSessionAt = Date.now();
        if (incoming) incoming.status = 'active';
        console.log('Voice session created:', context.mode, context.mode === 'Unhinged' && unhingedVoiceID ? 'custom drill sergeant' : context.mode === 'Gentle' ? 'marin' : 'vesper');
        return reply(response, 201, { ...result, greeting: greetingFor(context) });
      } finally {
        livePending = false;
        if (incoming?.status === 'answering') incoming.status = Date.now() < incoming.expiresAt ? 'ringing' : 'missed';
      }
    }
    reply(response, 404, { error: 'Not found.' });
  } catch (error) {
    reply(response, 400, { error: error instanceof SyntaxError ? 'Invalid request.' : error.message });
  }
});

server.requestTimeout = 35000;
server.listen(8787, '0.0.0.0', () => console.log('Hobbit HTTPS server listening on port 8787.'));
