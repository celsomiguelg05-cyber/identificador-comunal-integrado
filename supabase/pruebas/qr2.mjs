// Genera un QR rotativo CC2 igual que la app, para probar verificar_carne.
import { createHmac, randomBytes } from 'node:crypto';
const master = process.argv[2] || randomBytes(32).toString('base64url');
const [id, ver] = ['PXT-0002', 2];
const step = Math.floor(Date.now() / 1000 / 30);
const sp = createHmac('sha256', Buffer.from(master, 'base64url')).update(`${id}|${ver}`).digest();
const code = createHmac('sha256', sp).update(`${id}|${ver}|${step}`).digest().subarray(0, 12).toString('base64url');
console.log(JSON.stringify({ master, qr: `CC2|${id}|${ver}|${step}|${code}`, malo: `CC2|${id}|${ver}|${step}|AAAAAAAAAAAAAAAA` }));
