import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';

export function runtimeConfiguration(env = process.env) {
  const hosted = env.HOBBIT_HOSTED === 'true';
  const dataDirectory = env.HOBBIT_DATA_DIR || '.local';
  if (hosted && (!env.HOBBIT_DATA_DIR || !isAbsolute(dataDirectory))) throw new Error('Hosted mode needs an absolute persistent HOBBIT_DATA_DIR.');
  const secret = env.HOBBIT_DEVICE_SECRET || (!hosted && existsSync('.local/server-secret') ? readFileSync('.local/server-secret', 'utf8').trim() : '');
  if (secret.length < 32) throw new Error('Set a pairing secret of at least 32 characters.');
  const port = Number(env.PORT || 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be between 1 and 65535.');
  mkdirSync(dataDirectory, { recursive: true, mode: 0o700 });
  return { hosted, dataDirectory, secret, port };
}

export function readState(directory, name, fallback) {
  const path = join(directory, name + '.json');
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : fallback;
}

export function writeState(directory, name, value) {
  const path = join(directory, name + '.json');
  writeFileSync(path + '.tmp', JSON.stringify(value), { mode: 0o600 });
  renameSync(path + '.tmp', path);
}
