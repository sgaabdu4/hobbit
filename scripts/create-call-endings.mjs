import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

if (!process.env.OPENAI_API_KEY) throw new Error('Set OPENAI_API_KEY locally. This generates six billable voice clips.');
const custom = JSON.parse(readFileSync('.local/drill-voice.json', 'utf8')).id;
mkdirSync('.local/endings', { recursive: true });
const lines = {
  farewell: 'Okay. Good job showing up. Speak soon.',
  completion: 'Well done! Good job. Your habit is done. Speak tomorrow.'
};
async function generate(kind, mode, voice) {
  const name = `${kind}-${mode}`;
  if (existsSync(`Sources/Habitaker/Resources/${name}.wav`)) { console.log(JSON.stringify({ name, existing: true })); return; }
  const audio = [], transcript = [];
  let lastSpeech = 0, timer, closing = false;
  const ws = new WebSocket('wss://api.openai.com/v1/live/sessions', { headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}` } });
  await new Promise((resolve, reject) => {
    const deadline = setTimeout(() => { ws.close(); reject(new Error(`${name}: timed out`)); }, 60000);
    ws.onopen = () => ws.send(JSON.stringify({ type: 'session.start', session: {
      model: 'gpt-live-1',
      instructions: `You are recording one short closing line for Pip, a fictional habit companion. Say exactly: ${JSON.stringify(lines[kind])}. No extra words, sounds, questions or introduction. ${mode === 'gentle' ? 'Warm and natural.' : 'A firm masculine coach, satisfied and brisk, with decisive warmth. No shouting or insults in this closing line.'}`,
      audio: { format: { type: 'audio/pcm', rate: 24000 }, output: { voice } }
    } }));
    ws.onerror = () => reject(new Error(`${name}: connection failed`));
    ws.onmessage = event => {
      const value = JSON.parse(event.data);
      if (value.type === 'error') { ws.close(); reject(new Error(`${name}: ${value.error?.code}`)); }
      if (value.type === 'session.started') {
        ws.send(JSON.stringify({ type: 'session.commentary.append', delegation_id: null, content: `Speak the exact closing line now, once: ${lines[kind]}` }));
        timer = setInterval(() => {
          if (closing) return;
          ws.send(JSON.stringify({ type: 'session.input_audio.append', audio: Buffer.alloc(4800).toString('base64') }));
          if (lastSpeech && Date.now() - lastSpeech > 1400) { closing = true; ws.send(JSON.stringify({ type: 'session.close' })); }
        }, 100);
      }
      if (value.type === 'session.output_audio.delta') {
        const chunk = Buffer.from(value.delta, 'base64'); audio.push(chunk);
        for (let i = 0; i + 1 < chunk.length; i += 2) if (Math.abs(chunk.readInt16LE(i)) > 300) { lastSpeech = Date.now(); break; }
      }
      if (value.type === 'session.output_transcript.delta') transcript.push(value.delta);
      if (value.type === 'session.closed') {
        clearInterval(timer); clearTimeout(deadline); ws.close();
        if (!lastSpeech) { reject(new Error(`${name}: no speech received`)); return; }
        const actual = transcript.join('').trim();
        const normalize = text => text.toLowerCase().replace(/[^a-z]/g, '');
        if (normalize(actual) !== normalize(lines[kind])) { reject(new Error(`${name}: unexpected words: ${actual}`)); return; }
        writeFileSync(`.local/endings/${name}.pcm`, Buffer.concat(audio));
        const converted = spawnSync('ffmpeg', ['-y', '-f', 's16le', '-ar', '24000', '-ac', '1', '-i', `.local/endings/${name}.pcm`, '-af', 'silenceremove=start_periods=1:start_duration=0.05:start_threshold=-45dB:stop_periods=1:stop_duration=0.5:stop_threshold=-45dB', '-c:a', 'pcm_s16le', `Sources/Habitaker/Resources/${name}.wav`], { stdio: 'ignore' });
        if (converted.status !== 0) { reject(new Error(`${name}: conversion failed`)); return; }
        console.log(JSON.stringify({ name, transcript: actual })); resolve();
      }
    };
    ws.onclose = () => { clearInterval(timer); clearTimeout(deadline); if (!closing) reject(new Error(`${name}: closed early`)); };
  });
}
for (const [mode, voice] of [['gentle', 'marin'], ['aggressive', 'vesper'], ['unhinged', { id: custom }]]) {
  const results = await Promise.allSettled(Object.keys(lines).map(kind => generate(kind, mode, voice)));
  for (const result of results) if (result.status === 'rejected') throw result.reason;
}
