import https from 'node:https';
import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { greetingFor, liveConfiguration, validateHabit } from './domain.mjs';
import { pushConfigured, sendCallPush } from './apns.mjs';
import { dayKey, nextCallAt, validateSchedule, validateCompletedDays } from './schedule.mjs';
import { extractHabit, onboardingConfiguration, onboardingGreeting } from './onboarding.mjs';
import { petPrompt } from './pet-design.mjs';

const secret = readFileSync('.local/server-secret', 'utf8').trim();
const unhingedVoiceID = process.env.OPENAI_UNHINGED_VOICE_ID || (existsSync('.local/drill-voice.json') ? JSON.parse(readFileSync('.local/drill-voice.json', 'utf8')).id : undefined);
let device = existsSync('.local/device.json') ? JSON.parse(readFileSync('.local/device.json', 'utf8')) : {};
const calls = new Map();
let livePending = false;
let lastSessionAt = 0;
let activeVoice;
let imagePending = false;
let plan = existsSync('.local/schedule.json') ? JSON.parse(readFileSync('.local/schedule.json', 'utf8')) : null;
let dailyTimer;

function savePlan() {
  writeFileSync('.local/schedule.json.tmp', JSON.stringify(plan), { mode: 0o600 });
  renameSync('.local/schedule.json.tmp', '.local/schedule.json');
}

function busyCall() {
  if (activeVoice && Date.now() > activeVoice.expiresAt) activeVoice = null;
  for (const call of calls.values()) {
    if (call.status === 'ringing' && Date.now() > call.expiresAt) call.status = 'missed';
    if (call.status === 'active' && Date.now() > call.activeUntil) call.status = 'ended';
  }
  return livePending || Boolean(activeVoice) || [...calls.values()].some(call => ['scheduled', 'ringing', 'answering', 'active'].includes(call.status));
}

async function ring(call) {
  if (call.status !== 'scheduled') return;
  try {
    await sendCallPush(device.token, call.id);
    if (call.status === 'scheduled') { call.status = 'ringing'; call.expiresAt = Date.now() + 60000; }
  } catch (error) { call.status = 'failed'; call.error = error.message; }
}

function armDailyCall() {
  clearTimeout(dailyTimer);
  if (!plan || plan.paused) return;
  const due = nextCallAt(plan);
  dailyTimer = setTimeout(async () => {
    const current = plan;
    if (!current || current.paused) return;
    current.lastAttemptDay = dayKey(due, current.timeZone);
    current.lastError = null;
    if (Date.now() - due > 60000) current.lastError = 'Your computer was asleep at call time. Try a call now.';
    else if (!device.token || !pushConfigured()) current.lastError = 'Incoming calls are not ready. Open Hobbit and retry the connection.';
    else if (busyCall()) current.lastError = 'Your daily call was skipped because another call was in progress.';
    savePlan();
    if (!current.lastError) {
      const call = { id: randomUUID(), habit: current.habit, mode: current.mode, status: 'scheduled', scheduledAt: due };
      calls.set(call.id, call);
      await ring(call);
      if (call.error) { current.lastError = 'The daily call could not reach your iPhone. Try a call now.'; savePlan(); }
    }
    armDailyCall();
  }, Math.min(due - Date.now(), 2147483647));
}

function scheduleResult() { return { plan, nextCallAt: nextCallAt(plan) }; }

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
    if (request.method === 'GET' && request.url === '/schedule') return reply(response, 200, scheduleResult());
    if (request.method === 'POST' && request.url === '/habit-draft') {
      if (!process.env.OPENAI_API_KEY) return reply(response, 503, { error: 'Voice setup is incomplete. Type your habit instead.' });
      return reply(response, 200, await extractHabit((await readJSON(request)).transcript));
    }
    if (request.method === 'PUT' && request.url === '/schedule') {
      const input = validateSchedule(await readJSON(request));
      if (!process.env.OPENAI_API_KEY || !pushConfigured() || !device.token) return reply(response, 503, { error: 'Connect this iPhone before saving daily calls. Tap Retry connection.' });
      if (busyCall()) return reply(response, 409, { error: 'Finish or cancel the current call before changing your daily call.' });
      plan = { ...input, completedDays: plan?.completedDays ?? [], lastAttemptDay: plan?.lastAttemptDay ?? null, lastError: null };
      savePlan(); armDailyCall();
      return reply(response, 200, scheduleResult());
    }
    if (request.method === 'PUT' && request.url === '/progress') {
      const days = validateCompletedDays((await readJSON(request)).completedDays);
      if (plan) { plan.completedDays = days; savePlan(); armDailyCall(); }
      return reply(response, 200, scheduleResult());
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
            prompt: petPrompt(input.description.trim()) }),
          signal: AbortSignal.timeout(180000)
        });
        const result = await upstream.json();
        if (!upstream.ok || !result.data?.[0]?.b64_json) return reply(response, 502, { error: `Pet creation failed (HTTP ${upstream.status}). Your current pet is unchanged. Try again.` });
        return reply(response, 201, { image: result.data[0].b64_json, columns: 4, rows: 4 });
      } finally { imagePending = false; }
    }
    if (request.method === 'POST' && request.url === '/calls') {
      const input = await readJSON(request);
      const habit = validateHabit(input);
      if (!process.env.OPENAI_API_KEY) return reply(response, 503, { error: 'Voice is not configured on the server yet.' });
      if (!pushConfigured() || !device.token) return reply(response, 503, { error: 'Incoming calls are not ready. Apple push credentials and this iPhone’s push registration are required.' });
      const delay = input.delaySeconds ?? 15;
      if (!Number.isInteger(delay) || delay < 10 || delay > 86400) return reply(response, 400, { error: 'Choose a call time within the next day.' });
      if (busyCall()) return reply(response, 409, { error: 'A call is already scheduled or active. Finish it first.' });
      const id = randomUUID();
      const call = { id, ...habit, status: 'scheduled', scheduledAt: Date.now() + delay * 1000 };
      calls.set(id, call);
      call.timer = setTimeout(() => ring(call), delay * 1000);
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
    const voiceMatch = request.url?.match(/^\/voice\/([a-fA-F0-9-]{36})$/);
    if (request.method === 'DELETE' && voiceMatch) {
      if (activeVoice?.id === voiceMatch[1]) activeVoice = null;
      return reply(response, 200, { ended: true });
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
      if (activeVoice && Date.now() > activeVoice.expiresAt) activeVoice = null;
      if (livePending || activeVoice || Date.now() - lastSessionAt < 5000) return reply(response, 429, { error: 'A voice connection is already starting or active. Finish it and wait a moment.' });
      livePending = true;
      if (incoming) incoming.status = 'answering';
      try {
        const upstream = await fetch('https://api.openai.com/v1/live/sessions', {
          method: 'POST', headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
          body: JSON.stringify({ session: input.purpose === 'onboarding' && !incoming ? onboardingConfiguration() : liveConfiguration(context, unhingedVoiceID), transport: { type: 'webrtc', sdp: input.sdp } }),
          signal: AbortSignal.timeout(30000)
        });
        const result = await upstream.json();
        if (!upstream.ok) {
          const code = result.error?.code || 'request_rejected';
          console.error('OpenAI voice rejected:', upstream.status, code);
          return reply(response, 502, { error: `OpenAI voice is unavailable (HTTP ${upstream.status}, ${code}).` });
        }
        lastSessionAt = Date.now();
        activeVoice = { id: randomUUID(), expiresAt: Date.now() + 190000 };
        if (incoming) { incoming.status = 'active'; incoming.activeUntil = Date.now() + 190000; }
        console.log('Voice session created:', context.mode, context.mode === 'Unhinged' && unhingedVoiceID ? 'custom drill sergeant' : context.mode === 'Gentle' ? 'marin' : 'vesper');
        return reply(response, 201, { ...result, connectionID: activeVoice.id, greeting: input.purpose === 'onboarding' && !incoming ? onboardingGreeting : greetingFor(context) });
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
armDailyCall();
server.listen(8787, '0.0.0.0', () => console.log('Hobbit HTTPS server listening on port 8787.'));
