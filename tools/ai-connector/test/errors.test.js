import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:https';
import { X509Certificate, createHash } from 'node:crypto';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { publicError, connectorError, serviceError } from '../src/errors.js';
import { writeConfig } from '../src/connector.js';

const base = dirname(fileURLToPath(import.meta.url));
const cli = join(base, '../src/cli.js');
const canary = 'SECRET_CANARY_DoNotReflect';
const call = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'vitreus_vaults', arguments: {} } }) + '\n';
function run(args, input = '') {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, ...args], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', code => resolve({ code, stdout, stderr }));
    child.stdin.end(input);
  });
}
function noLeak(output, directory) {
  assert.ok(!output.includes(canary), output);
  assert.ok(!output.includes(directory), output);
  assert.doesNotMatch(output, /\/tmp\/|\/home\/|[A-Z]:\\/);
}
async function temporary(t) {
  const directory = await mkdtemp(join(tmpdir(), 'vitreus-errors-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test('only explicitly constructed errors and strictly enumerated service codes are public', () => {
  const hostile = Object.assign(new Error(canary + '/private/config'), { code: canary });
  assert.equal(publicError(hostile).code, 'CONNECTOR_ERROR');
  for (const code of [canary, 'ENOENT', '__proto__', 'toString', 401, {}, null]) {
    assert.equal(publicError(serviceError(code)).code, 'CONNECTOR_ERROR');
  }
  const safe = connectorError('CONFIG_INVALID');
  safe.code = canary;
  safe.message = canary;
  assert.equal(publicError(safe).code, 'CONFIG_INVALID');
  assert.equal(publicError(serviceError('UNAUTHORIZED')).code, 'UNAUTHORIZED');
});

test('malformed config with token canary and ENOENT never leak to subprocess CLI stderr or MCP', async t => {
  const directory = await temporary(t);
  const malformed = join(directory, canary + '.json');
  await writeFile(malformed, '{"token":"' + canary + '", ' + canary);
  for (const file of [malformed, join(directory, canary + '-missing.json')]) {
    const status = await run(['status', '--config', file]);
    assert.equal(status.code, 1);
    assert.equal(status.stdout, '');
    noLeak(status.stderr, directory);
    const parsed = JSON.parse(status.stderr);
    assert.equal(parsed.identityReachable, false);
    assert.equal(parsed.authenticated, false);
    assert.match(parsed.error.code, /^CONFIG_(INVALID|UNAVAILABLE)$/);
    const mcp = await run(['serve', '--config', file], call);
    assert.equal(mcp.code, 0);
    noLeak(mcp.stdout + mcp.stderr, directory);
    assert.equal(JSON.parse(mcp.stdout).result.isError, true);
  }
  const pair = await run(['pair', '--file', malformed]);
  assert.equal(pair.code, 1);
  noLeak(pair.stderr, directory);
  const missingPair = await run(['pair', '--file', join(directory, canary)]);
  noLeak(missingPair.stderr, directory);
});

const key = await readFile(join(base, 'synthetic-key.pem'));
const cert = await readFile(join(base, 'synthetic-cert.pem'));
const fingerprint = createHash('sha256').update(new X509Certificate(cert).raw).digest('hex');
async function phone(t, directory, handler) {
  const server = createServer({ key, cert }, handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const config = join(directory, 'connection.json');
  await writeConfig(config, { version: 1, address: '127.0.0.1', port: server.address().port, deviceId: canary, fingerprint, token: canary });
  return config;
}

test('remote error text and unknown code are never reflected by CLI or MCP', async t => {
  const directory = await temporary(t);
  let code = 'UNAUTHORIZED';
  const config = await phone(t, directory, (req, res) => {
    req.resume();
    res.writeHead(401);
    res.end(JSON.stringify({ error: { code, message: canary + directory } }));
  });
  for (const remoteCode of ['UNAUTHORIZED', canary + directory]) {
    code = remoteCode;
    const status = await run(['status', '--config', config]);
    noLeak(status.stderr, directory);
    const result = JSON.parse(status.stderr);
    assert.equal(result.identityReachable, true);
    assert.equal(result.authenticated, false);
    assert.equal(result.error.code, remoteCode === 'UNAUTHORIZED' ? 'UNAUTHORIZED' : 'CONNECTOR_ERROR');
    assert.ok(!status.stderr.includes(fingerprint));
    const mcp = await run(['serve', '--config', config], call);
    noLeak(mcp.stdout + mcp.stderr, directory);
    assert.equal(JSON.parse(mcp.stdout).result.isError, true);
  }
});

test('status authenticates with only a pinned read-only vaults RPC and returns no identity secrets', async t => {
  const directory = await temporary(t);
  const requests = [];
  let validShape = true;
  const config = await phone(t, directory, (req, res) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      requests.push({ path: req.url, body: JSON.parse(body), authorization: req.headers.authorization });
      res.end(JSON.stringify({ result: validShape ? { vaults: [] } : { anything: true } }));
    });
  });
  const status = await run(['status', '--config', config]);
  assert.equal(status.code, 0);
  noLeak(status.stderr, directory);
  assert.ok(!status.stderr.includes(fingerprint));
  const result = JSON.parse(status.stderr);
  assert.deepEqual(Object.keys(result).sort(), ['address', 'authenticated', 'identityReachable', 'port']);
  assert.equal(result.identityReachable, true);
  assert.equal(result.authenticated, true);
  assert.deepEqual(requests, [{ path: '/rpc', body: { method: 'vaults', params: {} }, authorization: 'Bearer ' + canary }]);
  validShape = false;
  const invalid = JSON.parse((await run(['status', '--config', config])).stderr);
  assert.equal(invalid.identityReachable, true);
  assert.equal(invalid.authenticated, false);
  assert.equal(invalid.error.code, 'RESPONSE_INVALID');
});
