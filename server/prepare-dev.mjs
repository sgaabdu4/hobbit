import { execFileSync, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdirSync, existsSync, readFileSync, writeFileSync, chmodSync } from 'node:fs';

const hostname = execFileSync('scutil', ['--get', 'LocalHostName'], { encoding: 'utf8' }).trim() + '.local';
const address = execFileSync('ipconfig', ['getifaddr', 'en0'], { encoding: 'utf8' }).trim();
if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(address)) throw new Error('Connect this Mac to Wi-Fi before preparing the device.');
mkdirSync('.local/tls', { recursive: true, mode: 0o700 });
mkdirSync('Sources/Habitaker/Resources', { recursive: true });
const existingCertificate = existsSync('.local/tls/cert.pem')
  ? execFileSync('openssl', ['x509', '-in', '.local/tls/cert.pem', '-noout', '-text'], { encoding: 'utf8' }) : '';
const certificateFresh = existingCertificate && spawnSync('openssl', ['x509', '-in', '.local/tls/cert.pem', '-checkend', '3600', '-noout'], { stdio: 'ignore' }).status === 0;
if (!certificateFresh || !existingCertificate.includes(`IP Address:${address}`) || !existingCertificate.includes('TLS Web Server Authentication')) {
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
    '-keyout', '.local/tls/key.pem', '-out', '.local/tls/cert.pem', '-subj', '/CN=Hobbit Local',
    '-addext', 'basicConstraints=critical,CA:FALSE',
    '-addext', 'keyUsage=critical,digitalSignature,keyEncipherment',
    '-addext', 'extendedKeyUsage=serverAuth',
    '-addext', `subjectAltName=DNS:${hostname},DNS:localhost,IP:127.0.0.1,IP:${address}`], { stdio: 'ignore' });
  chmodSync('.local/tls/key.pem', 0o600);
}
if (!existsSync('.local/server-secret')) {
  writeFileSync('.local/server-secret', randomBytes(32).toString('base64url'), { mode: 0o600 });
}
const der = execFileSync('openssl', ['x509', '-in', '.local/tls/cert.pem', '-outform', 'der']);
writeFileSync('Sources/Habitaker/Resources/DevelopmentConfig.json', JSON.stringify({
  serverURL: `https://${address}:8787`,
  deviceSecret: readFileSync('.local/server-secret', 'utf8').trim(),
  certificate: der.toString('base64')
}), { mode: 0o600 });
console.log('Local HTTPS pairing prepared. Development credentials are excluded from Git.');
