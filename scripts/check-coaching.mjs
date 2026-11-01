import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { greetingFor, liveConfiguration } from '../server/domain.mjs';

const configuration = liveConfiguration({ habit: 'Stretch for two minutes', mode: 'Unhinged' });
const headers = { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' };
if (!process.env.OPENAI_API_KEY) throw new Error('Set OPENAI_API_KEY locally before this billable check.');
const cases = [
  ["I don't want to do it.", 'none'],
  ["I can't be bothered. Maybe later.", 'none'],
  ['I am tired.', 'none'],
  ['Stop pushing me. Leave me alone.', 'stop'],
  ['End the call now.', 'stop'],
  ['I finished my two minutes of stretching.', 'completed']
];
for (const [input, expected] of cases) {
  const response = await fetch('https://api.openai.com/v1/decisions', {
    method: 'POST', headers, signal: AbortSignal.timeout(30000),
    body: JSON.stringify({ ...configuration.delegation.decisions, input })
  });
  assert.equal(response.ok, true, `Decisions returned HTTP ${response.status}`);
  const actual = (await response.json()).answers.find(answer => answer.name === 'habit_action')?.choice;
  console.log(JSON.stringify({ input, expected, actual }));
  assert.equal(actual, expected);
}

if (process.argv[2]) {
  const inputAudio = readFileSync(process.argv[2]);
  const voiceID = process.env.OPENAI_UNHINGED_VOICE_ID || (existsSync('.local/drill-voice.json') ? JSON.parse(readFileSync('.local/drill-voice.json', 'utf8')).id : undefined);
  if (voiceID) configuration.audio.output.voice = { id: voiceID };
  configuration.audio.format = { type: 'audio/pcm', rate: 24000 };
  let inputTranscript = '', reply = '', inputStarted = false, lastOutput = 0, inputOffset = 0;
  let timer, silenceFrames = 0, closing = false;
  const outputAudio = [];
  const socket = new WebSocket('wss://api.openai.com/v1/live/sessions', { headers });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { socket.close(); reject(new Error('Live coaching check timed out.')); }, 60000);
    socket.onopen = () => socket.send(JSON.stringify({ type: 'session.start', session: configuration }));
    socket.onerror = () => reject(new Error('Live WebSocket connection failed.'));
    socket.onmessage = event => {
      const value = JSON.parse(event.data);
      if (value.type === 'error') { console.log(JSON.stringify({ error: value.error?.code })); socket.close(); reject(new Error('Live rejected the check.')); }
      if (value.type === 'session.started') {
        socket.send(JSON.stringify({ type: 'session.commentary.append', delegation_id: null, content: greetingFor({ habit: 'Stretch for two minutes', mode: 'Unhinged' }) }));
        timer = setInterval(() => {
          if (!inputStarted && lastOutput && Date.now() - lastOutput > 1500) inputStarted = true;
          if (closing) return;
          if (!inputStarted) {
            socket.send(JSON.stringify({ type: 'session.input_audio.append', audio: Buffer.alloc(4800).toString('base64') }));
            return;
          }
          const chunk = inputOffset < inputAudio.length ? inputAudio.subarray(inputOffset, inputOffset + 4800) : Buffer.alloc(4800);
          if (inputOffset >= inputAudio.length) silenceFrames++;
          inputOffset += 4800;
          socket.send(JSON.stringify({ type: 'session.input_audio.append', audio: chunk.toString('base64') }));
          if (silenceFrames > 60 && reply && Date.now() - lastOutput > 1800) {
            closing = true;
            socket.send(JSON.stringify({ type: 'session.close' }));
          }
        }, 100);
      }
      if (value.type === 'session.output_audio.delta') {
        const chunk = Buffer.from(value.delta, 'base64');
        let peak = 0;
        for (let index = 0; index + 1 < chunk.length; index += 2) peak = Math.max(peak, Math.abs(chunk.readInt16LE(index)));
        if (peak > 300) lastOutput = Date.now();
        if (inputStarted) outputAudio.push(chunk);
      }
      if (value.type === 'session.input_transcript.delta') inputTranscript += value.delta;
      if (value.type === 'session.output_transcript.delta' && inputStarted) reply += value.delta;
      if (value.type === 'session.closed') {
        clearTimeout(timeout); clearInterval(timer); socket.close();
        console.log(JSON.stringify({ syntheticInput: inputTranscript, liveReply: reply }));
        writeFileSync('.local/coaching-reply.pcm', Buffer.concat(outputAudio), { mode: 0o600 });
        try {
          assert.match(inputTranscript.toLowerCase(), /want|wanna/);
          assert.ok(reply.length > 20, 'Live must reply to reluctance.');
          assert.doesNotMatch(reply.toLowerCase(), /okay,? no problem|no worries|goodbye|skip it today/);
          resolve();
        } catch (error) { reject(error); }
      }
    };
    socket.onclose = () => { clearTimeout(timeout); clearInterval(timer); if (!closing) reject(new Error('Live closed before the reply.')); };
  });
}
