// Test the actual modules extracted from the shipped ZIP, never a reimplementation.
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { EventEmitter } = require('node:events');
const { Readable } = require('node:stream');
const archive = path.join(__dirname, '../entry/src/main/resources/rawfile/ignis-server.zip');
const source = execFileSync('python3', ['-c', 'import zipfile,sys;sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read("apps/ignis-server/server/index.js"))', archive], { maxBuffer: 12 * 1024 * 1024 }).toString();
function moduleSource(name) {
  const marker = '// apps/ignis-server/server/routes/proxy/' + name + '.js\n';
  const start = source.indexOf(marker);
  assert.notEqual(start, -1);
  const end = source.indexOf('\n// ', start + marker.length);
  return source.slice(start, end);
}
function actual({ mode = 'any', allow = [], privateAllow = [], responses = [], addresses = {} } = {}) {
  const calls = [], lookups = [];
  const settings = { get(key) { return ({ proxyMode: mode, proxyAllowlist: allow, proxyAllowPrivate: privateAllow })[key]; } };
  const dns = { lookup(host, options, cb) { lookups.push(host); cb(null, [{ address: addresses[host] || '93.184.216.34', family: 4 }]); } };
  dns.promises = { lookup: async host => [{ address: addresses[host] || '93.184.216.34', family: 4 }] };
  const transport = { request(url, options, cb) {
    calls.push({ url: url.href, ...options });
    const req = new EventEmitter();
    req.write = () => {};
    req.end = () => queueMicrotask(() => {
      const finish = err => {
        if (err) return req.emit('error', err);
        const spec = responses[calls.length - 1] || {};
        const res = Readable.from([Buffer.from('ok')]);
        res.statusCode = spec.status || 200;
        res.headers = spec.location ? { location: spec.location } : {};
        cb(res);
      };
      if (require('node:net').isIP(url.hostname)) finish();
      else options.lookup(url.hostname, {}, finish);
    });
    return req;
  } };
  const context = vm.createContext({
    URL, Buffer, console: { warn() {} },
    require(name) {
      if (name === 'dns') return dns;
      if (name === 'http' || name === 'https') return transport;
      return require(name);
    },
    require_settings: () => settings,
    __commonJS: factories => {
      let mod;
      return () => {
        if (!mod) { mod = { exports: {} }; Object.values(factories)[0](mod.exports, mod); }
        return mod.exports;
      };
    }
  });
  vm.runInContext(moduleSource('ssrf-guard') + moduleSource('relay'), context);
  const relay = vm.runInContext('require_relay()', context);
  const guard = vm.runInContext('require_ssrf_guard()', context);
  return { relay, guard, calls, lookups, context };
}
const headers = { aUtHoRiZaTiOn: 'secret', COOKIE: 'sid=secret', Cookie2: 'legacy', 'PROXY-Authorization': 'proxy-secret', HOST: 'a.test', Accept: 'text/plain' };
for (const status of [301, 302, 303, 307, 308]) {
  test(`${status}: cross-origin removes sensitive headers case-insensitively, retains safe headers`, async () => {
    const x = actual({ responses: [{ status, location: 'https://b.test/path' }] });
    await x.relay.relayOnce({ url: 'https://a.test/start', method: 'GET', headers });
    assert.deepEqual({ ...x.calls[1].headers }, { Accept: 'text/plain' });
    assert.equal(x.calls[0].headers.aUtHoRiZaTiOn, 'secret');
    assert.equal(headers.COOKIE, 'sid=secret');
    assert.equal(x.lookups.length, 2, 'no extra DNS preflight per hop');
  });
}
test('same-origin relative redirect retains credentials', async () => {
  const x = actual({ responses: [{ status: 302, location: '/next' }] });
  await x.relay.proxyRequest({ url: 'https://a.test/start', method: 'GET', headers });
  assert.deepEqual({ ...x.calls[1].headers }, headers);
});
for (const target of ['https://a.test:8443/next', 'http://a.test/next']) {
  test(`origin change strips credentials: ${target}`, async () => {
    const x = actual({ responses: [{ status: 307, location: target }] });
    await x.relay.proxyRequest({ url: 'https://a.test/', method: 'GET', headers });
    assert.deepEqual({ ...x.calls[1].headers }, { Accept: 'text/plain' });
  });
}
test('A -> B -> A never restores stripped credentials', async () => {
  const x = actual({ responses: [{ status: 302, location: 'https://b.test/' }, { status: 302, location: 'https://a.test/' }] });
  await x.relay.proxyRequest({ url: 'https://a.test/', method: 'GET', headers });
  assert.equal(x.calls[2].headers.aUtHoRiZaTiOn, undefined);
});
test('allowlist denies an unlisted initial host before transport', async () => {
  const x = actual({ mode: 'allowlist', allow: ['a.test'] });
  await assert.rejects(x.relay.relayOnce({ url: 'https://b.test/', method: 'GET', headers }), e => e.statusCode === 403 && e.block.code === 'allowlist');
  assert.equal(x.calls.length, 0);
});
test('allowlist checks every hop and blocks before DNS or transport', async () => {
  const x = actual({ mode: 'allowlist', allow: ['a.test', 'b.test'], responses: [{ status: 302, location: 'https://b.test/' }, { status: 302, location: 'https://c.test/' }] });
  await assert.rejects(x.relay.relayOnce({ url: 'https://a.test/', method: 'GET', headers }), e => e.statusCode === 403 && e.block.code === 'allowlist' && e.block.host === 'c.test');
  assert.equal(x.calls.length, 2);
  assert.deepEqual(x.lookups, ['a.test', 'b.test']);
});
test('allowlist permits listed redirects', async () => {
  const x = actual({ mode: 'allowlist', allow: ['a.test', 'b.test'], responses: [{ status: 302, location: 'https://b.test/' }] });
  assert.equal((await x.relay.relayOnce({ url: 'https://a.test/', method: 'GET', headers })).status, 200);
});
test('existing SSRF private literal guard still blocks redirects', async () => {
  const x = actual({ responses: [{ status: 302, location: 'http://127.0.0.1/' }] });
  await assert.rejects(x.relay.proxyRequest({ url: 'https://a.test/', method: 'GET', headers }), e => e.block.code === 'private-host');
  assert.equal(x.calls.length, 1);
});
test('existing safeLookup blocks private DNS result on a listed redirect', async () => {
  const x = actual({ mode: 'allowlist', allow: ['a.test', 'b.test'], addresses: { 'b.test': '10.0.0.1' }, responses: [{ status: 302, location: 'https://b.test/' }] });
  await assert.rejects(x.relay.relayOnce({ url: 'https://a.test/', method: 'GET', headers }), e => e.block.code === 'private-resolve');
  assert.equal(x.calls[1].lookup, x.guard.safeLookup);
});
test('existing explicitly allowed private addresses remain supported', async () => {
  const x = actual({ privateAllow: ['127.0.0.1'], responses: [{ status: 302, location: 'http://127.0.0.1/' }] });
  assert.equal((await x.relay.relayOnce({ url: 'https://a.test/', method: 'GET', headers })).status, 200);
});
test('non-http redirects and redirect loops retain existing rejection', async () => {
  const x = actual({ responses: [{ status: 302, location: 'file:///etc/passwd' }] });
  await assert.rejects(x.relay.proxyRequest({ url: 'https://a.test/', method: 'GET', headers }), e => e.statusCode === 400);
  const y = actual({ responses: Array.from({ length: 6 }, () => ({ status: 302, location: '/loop' })) });
  await assert.rejects(y.relay.proxyRequest({ url: 'https://a.test/', method: 'GET', headers }), e => e.statusCode === 508);
  assert.equal(y.calls.length, 6);
});
test('production route forwards structured allowlist rejection', async () => {
  const x = actual({ mode: 'allowlist', allow: ['a.test'], responses: [{ status: 302, location: 'https://b.test/' }] });
  let handler;
  Object.assign(x.context, {
    require_express2: () => ({ Router: () => ({ post: (_, fn) => { handler = fn; } }) }),
    require_config: () => ({}), require_src2: () => ({ sanitizeError: e => ({ error: e.message }) }),
    require_signin: () => ({ signinCredentials: () => null })
  });
  vm.runInContext(moduleSource('index') + ';require_proxy();', x.context);
  let status, body;
  await handler({ body: { url: 'https://a.test/', headers } }, { status(n) { status = n; return this; }, json(b) { body = b; } });
  assert.equal(status, 403);
  assert.equal(body.code, 'allowlist');
  assert.equal(body.host, 'b.test');
  assert.equal(x.calls.length, 1);
});
