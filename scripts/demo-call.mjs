import https from 'node:https';
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('npm run demo:call -- --list\nnpm run demo:call -- --habit "Stretch for two minutes" --delay 15\nnpm run demo:call -- --cancel CALL_ID');
  process.exit(0);
}
const option = name => { const index = args.indexOf(name); return index < 0 ? undefined : args[index + 1]; };
const configuration = JSON.parse(readFileSync(new URL('../Sources/Habitaker/Resources/DevelopmentConfig.json', import.meta.url), 'utf8'));

function request(path, method = 'GET', body) {
  return new Promise((resolve, reject) => {
    const data = body ? Buffer.from(JSON.stringify(body)) : null;
    const connection = https.request(new URL(path, configuration.serverURL + '/'), {
      method, ca: readFileSync(new URL('../.local/tls/cert.pem', import.meta.url)),
      headers: { authorization: 'Bearer ' + configuration.deviceSecret, 'content-type': 'application/json', ...(data ? { 'content-length': data.length } : {}) },
      timeout: 15000
    }, response => {
      let text = '';
      response.on('data', chunk => { text += chunk; });
      response.on('end', () => {
        try {
          const result = JSON.parse(text);
          if (response.statusCode >= 400) reject(new Error(result.error || 'Call request failed.'));
          else resolve(result);
        } catch (error) { reject(error); }
      });
    });
    connection.on('timeout', () => connection.destroy(new Error('Cannot reach the Hobbit server. Start it with npm start.')));
    connection.on('error', reject);
    connection.end(data);
  });
}

try {
  const cancel = option('--cancel');
  if (cancel) {
    if (!/^[a-f0-9-]{36}$/i.test(cancel)) throw new Error('Provide the call ID printed when scheduling it.');
    await request('calls/' + cancel, 'DELETE');
    console.log('Call cancelled.');
  } else {
    const { habits } = await request('habits');
    const plans = habits.map(entry => entry.plan);
    if (args.includes('--list')) {
      for (const plan of plans) console.log(`${plan.habit} | ${plan.mode} | ${String(plan.hour).padStart(2, '0')}:${String(plan.minute).padStart(2, '0')}`);
    } else {
      const wanted = option('--habit');
      const matches = wanted ? plans.filter(plan => plan.id === wanted || plan.habit.toLowerCase() === wanted.toLowerCase()) : plans;
      if (matches.length !== 1) throw new Error('Choose one habit with --habit "Habit name". Use --list to see saved habits.');
      const plan = matches[0];
      const delaySeconds = Number(option('--delay') ?? 15);
      if (!Number.isInteger(delaySeconds) || delaySeconds < 10 || delaySeconds > 60) throw new Error('Choose a demo delay from 10 to 60 seconds.');
      const call = await request('calls', 'POST', { habitID: plan.id, habit: plan.habit, mode: plan.mode, delaySeconds });
      console.log(`Your iPhone will ring in ${delaySeconds} seconds for "${plan.habit}" (${plan.mode}).\nCall ID: ${call.id}`);
    }
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
