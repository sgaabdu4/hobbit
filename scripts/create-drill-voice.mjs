import { mkdirSync, writeFileSync } from 'node:fs';
import { drillVoicePrompt, drillVoiceScript } from '../server/voice-design.mjs';

if (!process.env.OPENAI_API_KEY) throw new Error('Set OPENAI_API_KEY before creating the voice.');
const response = await fetch('https://api.openai.com/v1/audio/voices', {
  method: 'POST',
  headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'prompt', name: 'Hobbit Drill Sergeant', model: 'auto', prompt: drillVoicePrompt, script_hint: drillVoiceScript }),
  signal: AbortSignal.timeout(180000)
});
const result = await response.json();
if (!response.ok || !result.id) {
  const scopes = result.error?.message?.match(/api\.[a-z_.]+/g)?.join(', ') || 'none reported';
  throw new Error(`Voice creation failed: HTTP ${response.status}, ${result.error?.code || 'unknown_error'}. Required scopes: ${scopes}`);
}
mkdirSync('.local', { recursive: true });
writeFileSync('.local/drill-voice.json', JSON.stringify(result), { mode: 0o600 });
console.log('Custom drill-sergeant voice saved locally. Restart the server to use it.');
