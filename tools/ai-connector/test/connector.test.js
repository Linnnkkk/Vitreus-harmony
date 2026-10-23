import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { X509Certificate } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createServer } from 'node:https';
import { readFile, mkdtemp, stat, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pair, rpc, writeConfig, isLanIPv4, isDiscoveryCandidate, discoveryTargets } from '../src/connector.js';

test('routed discovery fallback is bounded to remembered private /24', () => {
  const targets = discoveryTargets('192.168.0.27');
  assert.equal(targets.length, 254);
  assert.equal(new Set(targets).size, 254);
  assert.equal(targets[0], '192.168.0.1');
  assert.equal(targets.at(-1), '192.168.0.254');
  for (const address of ['8.8.8.8', '127.0.0.1', '169.254.1.2', 'invalid', '172.32.0.1']) {
    assert.deepEqual(discoveryTargets(address), []);
  }
});

const base = dirname(fileURLToPath(import.meta.url));
const key = await readFile(join(base, 'synthetic-key.pem'));
const cert = await readFile(join(base, 'synthetic-cert.pem'));
const fingerprint = createHash('sha256').update(new X509Certificate(cert).raw).digest('hex');

async function fixture(handler) {
  const server = createServer({ key, cert }, handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return { server, address: { address: '127.0.0.1', port: address.port, fingerprint, deviceId: 'synthetic-device', version: 1 } };
}

test('config writes atomically with restrictive permissions', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'vitreus-ai-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const file = join(directory, 'connection.json');
  await writeConfig(file, { ...fixtureConfig(), token: 'secret-token' });
  const mode = (await stat(file)).mode & 0o777;
  if (process.platform !== 'win32') assert.equal(mode, 0o600);
  assert.equal((await readFile(file, 'utf8')).includes('pairingCode'), false);
});

function fixtureConfig() { return { version: 1, deviceId: 'synthetic-device', address: '127.0.0.1', port: 4444, fingerprint, token: 'secret-token' }; }

test('stdio subprocess negotiates MCP, lists tools, and keeps stdout protocol-only', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'vitreus-ai-mcp-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const config = join(directory, 'connection.json');
  await writeConfig(config, fixtureConfig());
  const cli = join(base, '../src/cli.js');
  const child = spawn(process.execPath, [cli, '--config', config], { stdio: ['pipe', 'pipe', 'pipe'] });
  const stdout = [];
  const stderr = [];
  child.stdout.on('data', chunk => stdout.push(chunk));
  child.stderr.on('data', chunk => stderr.push(chunk));
  child.stdin.end([
    JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } }),
    JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
    JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'ping' }),
  ].join('\n') + '\n');
  const exitCode = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
  assert.equal(exitCode, 0);
  assert.equal(Buffer.concat(stderr).toString(), '');
  const messages = Buffer.concat(stdout).toString().trim().split('\n').map(JSON.parse);
  assert.equal(messages[0].result.protocolVersion, '2025-03-26');
  assert.equal(messages[1].result.tools.length, 19);
  assert.match(messages[0].result.instructions, /Obsidian/);
  assert.equal(messages[1].result.tools.find(tool => tool.name === 'vitreus_tags').annotations.readOnlyHint, true);
  assert.equal(messages[1].result.tools.find(tool => tool.name === 'vitreus_edit').inputSchema.properties.expectedRevision.type, 'string');
  assert.deepEqual(messages[2].result, {});
});

test('TLS pin mismatch sends no pairing credentials', async t => {
  let received = '';
  const endpoint = await fixture((request, response) => {
    request.on('data', chunk => { received += chunk.toString(); });
    response.end(JSON.stringify({ result: { token: 'unexpected' } }));
  });
  t.after(() => endpoint.server.close());
  await assert.rejects(pair({ ...endpoint.address, fingerprint: '0'.repeat(64), pairingCode: 'synthetic-pair-code' }));
  await assert.rejects(rpc({ ...endpoint.address, fingerprint: '0'.repeat(64), token: 'must-not-leak' }, 'vaults/create', { content: 'x' }));
  assert.equal(received, '');
});

test('RPC error is surfaced and a disconnected write is never retried', async t => {
  let writes = 0;
  const endpoint = await fixture((request, response) => {
    writes++;
    request.resume();
    response.writeHead(409, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ error: { code: 'REVISION_CONFLICT', message: 'revision mismatch' } }));
  });
  t.after(() => endpoint.server.close());
  await assert.rejects(rpc({ ...endpoint.address, token: 'synthetic-token' }, 'vaults/edit', { expectedRevision: 'rev-1' }), error => error.code === 'REVISION_CONFLICT');
  assert.equal(writes, 1);
  await new Promise(resolve => endpoint.server.close(resolve));
  const disconnected = await fixture((request, response) => { writes++; request.resume(); response.destroy(); });
  t.after(() => disconnected.server.close());
  await assert.rejects(rpc({ ...disconnected.address, token: 'synthetic-token' }, 'vaults/append', { expectedRevision: 'rev-2' }));
  assert.equal(writes, 2);
});

test('chunked Unicode and large valid JSON are decoded by the HTTP parser', async t => {
  const content = '中文🙂\\n'.repeat(100000);
  const endpoint = await fixture((request, response) => {
    request.resume();
    response.writeHead(200, { 'Content-Type': 'application/json' });
    const bytes = Buffer.from(JSON.stringify({ result: { content } }));
    response.write(bytes.subarray(0, 23));
    response.write(bytes.subarray(23, 29));
    response.end(bytes.subarray(29));
  });
  t.after(() => { endpoint.server.closeAllConnections(); endpoint.server.close(); });
  const result = await rpc({ ...endpoint.address, token: 'synthetic-token' }, 'read', {});
  assert.equal(result.content, content);
});

test('truncated HTTP bodies and bearer header injection are rejected', async t => {
  let requests = 0;
  const endpoint = await fixture((request, response) => {
    requests++;
    request.resume();
    response.writeHead(200, { 'Content-Length': 500 });
    response.write('{"result":1}');
    setImmediate(() => response.destroy());
  });
  t.after(() => { endpoint.server.closeAllConnections(); endpoint.server.close(); });
  await assert.rejects(rpc({ ...endpoint.address, token: 'synthetic-token' }, 'read', {}));
  await assert.rejects(rpc({ ...endpoint.address, token: 'bad\\r\\nX-Evil:1' }, 'read', {}), /invalid bearer token/);
  assert.equal(requests, 1);
});

test('LAN address policy rejects public addresses and discovery metadata must match', () => {
  assert.equal(isLanIPv4('192.168.1.20'), true);
  assert.equal(isLanIPv4('8.8.8.8'), false);
  const config = { deviceId: 'trusted-device' };
  const response = { type: 'vitreus-ai-service', version: 1, nonce: 'nonce-1', deviceId: 'trusted-device', port: 7443 };
  assert.equal(isDiscoveryCandidate(response, '192.168.1.30', config, 'nonce-1'), true);
  assert.equal(isDiscoveryCandidate({ ...response, nonce: 'attacker-nonce' }, '192.168.1.30', config, 'nonce-1'), false);
  assert.equal(isDiscoveryCandidate({ ...response, deviceId: 'other-device' }, '192.168.1.30', config, 'nonce-1'), false);
  assert.equal(isDiscoveryCandidate(response, '8.8.8.8', config, 'nonce-1'), false);
});
