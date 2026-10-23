import { createHash, randomBytes } from 'node:crypto';
import { promises as fs } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { dirname } from 'node:path';
import dgram from 'node:dgram';
import tls from 'node:tls';
import https from 'node:https';

export const DEFAULT_CONFIG = `${os.homedir()}/.vitreus-ai/connection.json`;
const MAX_RESPONSE = 8 * 1024 * 1024;
const TIMEOUT_MS = 8000;

export function isLanIPv4(address) {
  if (typeof address !== 'string' || !net.isIPv4(address)) return false;
  const parts = address.split('.').map(Number);
  return parts[0] === 127 || parts[0] === 10 ||
    (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
    (parts[0] === 192 && parts[1] === 168) ||
    (parts[0] === 169 && parts[1] === 254);
}

export function isDiscoveryCandidate(packet, remoteAddress, config, nonce) {
  return isLanIPv4(remoteAddress) && packet?.type === 'vitreus-ai-service' && packet.version === 1 &&
    packet.nonce === nonce && packet.deviceId === config.deviceId &&
    Number.isInteger(packet.port) && packet.port >= 1 && packet.port <= 65535;
}

function normalizeFingerprint(value) {
  const fingerprint = String(value ?? '').replaceAll(':', '').toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(fingerprint)) throw new Error('fingerprint must be a SHA-256 hex digest');
  return fingerprint;
}

export function validatePairing(pairing) {
  if (!pairing || pairing.version !== 1 || !isLanIPv4(pairing.address) ||
      !Number.isInteger(pairing.port) || pairing.port < 1 || pairing.port > 65535 ||
      typeof pairing.pairingCode !== 'string' || pairing.pairingCode.length < 1 || pairing.pairingCode.length > 256 ||
      typeof pairing.deviceId !== 'string' || pairing.deviceId.length > 256) {
    throw new Error('invalid pairing JSON (expected version 1, LAN IPv4, port, deviceId and pairingCode)');
  }
  normalizeFingerprint(pairing.fingerprint);
  return pairing;
}

export async function readConfig(file = DEFAULT_CONFIG) {
  const data = JSON.parse(await fs.readFile(file, 'utf8'));
  validatePairing({ ...data, pairingCode: 'stored-config-validation' });
  if (typeof data.token !== 'string' || data.token.length < 1 || data.token.length > 4096) throw new Error('invalid connection config');
  return data;
}

export async function writeConfig(file, config) {
  const pairing = { ...config, pairingCode: config.pairingCode ?? 'stored-config-validation' };
  validatePairing(pairing);
  if (typeof config.token !== 'string' || config.token.length < 1) throw new Error('invalid token');
  const directory = dirname(file);
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.${randomBytes(6).toString('hex')}.tmp`;
  try {
    await fs.writeFile(temporary, `${JSON.stringify({ version: 1, deviceId: config.deviceId, address: config.address, port: config.port, fingerprint: normalizeFingerprint(config.fingerprint), token: config.token }, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    await fs.chmod(temporary, 0o600);
    await fs.rename(temporary, file);
    if (process.platform !== 'win32') await fs.chmod(file, 0o600);
  } finally {
    await fs.rm(temporary, { force: true });
  }
}

function connectPinned(address, port, fingerprint) {
  if (!isLanIPv4(address) || !Number.isInteger(port) || port < 1 || port > 65535) {
    return Promise.reject(new Error('invalid LAN endpoint'));
  }
  normalizeFingerprint(fingerprint);
  return new Promise((resolve, reject) => {
    const socket = tls.connect({ host: address, port, rejectUnauthorized: false, servername: undefined });
    const timeout = setTimeout(() => socket.destroy(new Error('TLS connection timed out')), TIMEOUT_MS);
    const fail = error => { clearTimeout(timeout); socket.destroy(); reject(error); };
    socket.once('error', fail);
    socket.once('secureConnect', () => {
      const cert = socket.getPeerCertificate(true);
      const actual = cert?.raw ? createHash('sha256').update(cert.raw).digest('hex') : '';
      if (actual !== normalizeFingerprint(fingerprint)) return fail(new Error('TLS certificate fingerprint mismatch'));
      clearTimeout(timeout);
      socket.removeListener('error', fail);
      resolve(socket);
    });
  });
}

async function requestPinned(config, path, body, token) {
  if (token && !/^[A-Za-z0-9_-]{1,4096}$/.test(token)) throw new Error('invalid bearer token');
  // A socket is not handed to HTTP until TLS identity has been verified.
  const agent = new https.Agent({ keepAlive: false });
  agent.createConnection = (_options, callback) => {
    connectPinned(config.address, config.port, config.fingerprint).then(
      socket => callback(null, socket), error => callback(error));
    return undefined;
  };
  const payload = Buffer.from(JSON.stringify(body));
  try {
    return await new Promise((resolve, reject) => {
      const headers = { 'Content-Type': 'application/json', 'Content-Length': payload.length };
      if (token) headers.Authorization = `Bearer ${token}`;
      const request = https.request({ hostname: config.address, port: config.port,
        path, method: 'POST', agent, headers }, response => {
        const chunks = [];
        let size = 0;
        response.on('data', chunk => {
          size += chunk.length;
          if (size > MAX_RESPONSE) response.destroy(new Error('HTTP response exceeds 8 MiB'));
          else chunks.push(chunk);
        });
        response.once('error', reject);
        response.once('aborted', () => reject(new Error('incomplete HTTP response')));
        response.once('end', () => {
          if (!response.complete) return reject(new Error('incomplete HTTP response'));
          const status = response.statusCode || 0;
          if (status >= 300 && status < 400) return reject(new Error('redirects are not allowed'));
          let result;
          try { result = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
          catch { return reject(new Error('invalid JSON response')); }
          if (result?.error) {
            const error = new Error(String(result.error.message || 'RPC error'));
            error.code = String(result.error.code || 'RPC_ERROR');
            return reject(error);
          }
          if (status < 200 || status >= 300) return reject(new Error(`HTTP status ${status}`));
          resolve(result);
        });
      });
      const timer = setTimeout(() => request.destroy(new Error('HTTP response timed out')), TIMEOUT_MS);
      request.once('close', () => clearTimeout(timer));
      request.once('error', reject);
      request.end(payload);
    });
  } finally { agent.destroy(); }
}

export async function verifyPin(config) {
  const socket = await connectPinned(config.address, config.port, config.fingerprint);
  socket.destroy();
}

// Bounded fallback for routed/container networks where broadcasts do not cross NAT.
// Probe only the remembered RFC1918 /24, never arbitrary/public ranges.
export function discoveryTargets(address) {
  if (!isLanIPv4(address)) return [];
  const parts = address.split('.').map(Number);
  if (!(parts[0] === 10 || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] === 192 && parts[1] === 168))) return [];
  const prefix = parts.slice(0, 3).join('.');
  return Array.from({ length: 254 }, (_, i) => `${prefix}.${i + 1}`);
}

export async function discover(config) {
  const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });
  const nonce = randomBytes(16).toString('hex');
  try {
    await new Promise((resolve, reject) => { socket.once('error', reject); socket.bind(0, '0.0.0.0', resolve); });
    socket.setBroadcast(true);
    const candidates = new Map();
    let finished = false;
    let probeTimer;
    const result = new Promise(resolve => {
      const finish = value => { if (!finished) { finished = true; clearTimeout(timer); clearInterval(probeTimer); resolve(value); } };
      const timer = setTimeout(() => finish(null), 5500);
      socket.on('error', () => finish(null));
      socket.on('message', async (message, remote) => {
        if (finished || message.length > 512 || candidates.size >= 8 || !isLanIPv4(remote.address)) return;
        let packet;
        try { packet = JSON.parse(message.toString('utf8')); } catch { return; }
        if (!isDiscoveryCandidate(packet, remote.address, config, nonce)) return;
        const key = `${remote.address}:${packet.port}`;
        if (candidates.has(key)) return;
        const candidate = { ...config, address: remote.address, port: packet.port };
        candidates.set(key, candidate);
        try { await verifyPin(candidate); finish(candidate); } catch { /* Keep failed candidates counted to bound discovery work. */ }
      });
    });
    const packet = Buffer.from(JSON.stringify({ type: 'vitreus-ai-discover', version: 1, nonce }));
    const broadcasts = new Set(['255.255.255.255']);
    for (const entries of Object.values(os.networkInterfaces())) for (const item of entries ?? []) {
      if (item.family !== 'IPv4' || item.internal || !isLanIPv4(item.address)) continue;
      const parts = item.address.split('.').map(Number);
      const mask = item.netmask.split('.').map(Number);
      broadcasts.add(parts.map((part, index) => (part & mask[index]) | (~mask[index] & 255)).join('.'));
    }
    const send = address => socket.send(packet, 39871, address, () => { /* Discovery is best-effort. */ });
    for (const broadcast of broadcasts) send(broadcast);
    send(config.address);
    const targets = discoveryTargets(config.address);
    let index = 0;
    // At most 100 tiny, credential-free discovery packets per second, once per attempt.
    probeTimer = setInterval(() => {
      if (finished || index >= targets.length) { clearInterval(probeTimer); return; }
      send(targets[index++]);
    }, 10);
    return await result;
  } finally { socket.close(); }
}

export async function rpc(config, method, params, configFile) {
  let endpoint = config;
  try { await verifyPin(endpoint); }
  catch {
    endpoint = await discover(config);
    if (!endpoint) throw new Error('device unavailable; no RPC was sent');
    if (configFile) await writeConfig(configFile, endpoint);
  }
  const response = await requestPinned(endpoint, '/rpc', { method, params }, endpoint.token);
  if (response && typeof response === 'object' && response.error) {
    const error = new Error(String(response.error.message ?? 'RPC error'));
    error.code = response.error.code;
    throw error;
  }
  if (!response || !Object.hasOwn(response, 'result')) throw new Error('invalid RPC response shape');
  return response.result;
}

export async function pair(pairing, clientName = 'Vitreus AI Connector') {
  validatePairing(pairing);
  const result = await requestPinned(pairing, '/pair', { clientName, pairingCode: pairing.pairingCode }, null);
  if (typeof result.token !== 'string' || !result.token || (result.deviceId && result.deviceId !== pairing.deviceId)) throw new Error('invalid pairing response');
  return { ...pairing, deviceId: result.deviceId ?? pairing.deviceId, token: result.token };
}
