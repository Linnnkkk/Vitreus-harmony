'use strict';
// Run the actual production fetch section, patched in memory. Never write the repository ZIP.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const test = require('node:test');
const patch = path.join(__dirname, 'patch-ignis-request.py');
const production = execFileSync('python3', [patch, '--stdout-shim'], { maxBuffer: 8 * 1024 * 1024 }).toString();
const start = production.indexOf('  // packages/shim/src/globals/fetch.js\n');
const end = production.indexOf('  // packages/shim/src/globals/window.js\n', start);
assert.ok(start >= 0 && end > start);
const section = production.slice(start, end);
function harness() {
  const calls = [], direct = [];
  const window = { fetch: async (...args) => { direct.push(args); return new Response('native'); } };
  new Function('window', 'Request', 'Headers', 'Response', 'URL', 'isSameOrigin', 'isDirectFetchHost',
    'desktopHeaders', 'proxyFetch', 'console', section + '\ninstallFetchShim();')(
    window, Request, Headers, Response, URL,
    url => url.startsWith('https://local.test/'), url => url.startsWith('https://direct.test/'),
    () => ({ origin: 'app://obsidian.md', 'user-agent': 'desktop-test' }),
    async value => { calls.push(value); return { body: 'ok', status: 200, headers: {} }; },
    { log() {}, error() {} });
  return { fetch: window.fetch, calls, direct };
}
const url = 'https://cross.test/post';
function request(body, extra = {}) { return new Request(url, { method: 'POST', body, ...extra }); }
function bytes(value) { return [...new Uint8Array(value)]; }

test('Request UTF-8 body reaches proxy, original remains readable, headers/method retained', async () => {
  const h = harness(), r = request('汉字+text', { headers: { 'x-request': 'yes', authorization: 'Bearer fixture' } });
  await h.fetch(r);
  assert.equal(new TextDecoder().decode(h.calls[0].body), '汉字+text');
  assert.equal(h.calls[0].method, 'POST');
  assert.equal(h.calls[0].headers['x-request'], 'yes');
  assert.equal(h.calls[0].headers.authorization, 'Bearer fixture');
  assert.equal(h.calls[0].headers.origin, 'app://obsidian.md');
  assert.equal(r.bodyUsed, false);
  assert.equal(await r.text(), '汉字+text');
});
test('Request binary body preserves every byte including NUL/invalid UTF-8', async () => {
  const h = harness(); await h.fetch(request(new Uint8Array([0, 255, 128, 65])));
  assert.deepEqual(bytes(h.calls[0].body), [0, 255, 128, 65]);
});
for (const override of ['override', '', new Uint8Array([0, 254]), new Uint8Array([8, 7]).buffer]) {
  test('init.body override takes priority: ' + (typeof override === 'string' ? JSON.stringify(override) : override.constructor.name), async () => {
    const h = harness(), r = request('original');
    r.clone = () => { throw new Error('must not read overridden Request'); };
    await h.fetch(r, { body: override });
    assert.equal(h.calls[0].body, override);
    assert.equal(r.bodyUsed, false);
  });
}
for (const init of [undefined, {}, { body: null }, { body: undefined }]) {
  test('null/undefined body inherits Request per RequestInit semantics: ' + JSON.stringify(init), async () => {
    const h = harness(); await h.fetch(request('inherited'), init);
    assert.equal(new TextDecoder().decode(h.calls[0].body), 'inherited');
  });
}
test('already-consumed Request rejects TypeError before proxy call', async () => {
  const h = harness(), r = request('used'); await r.text();
  await assert.rejects(h.fetch(r), TypeError); assert.equal(h.calls.length, 0);
});
test('locked Request rejects TypeError before proxy call', async () => {
  const h = harness(), r = request('locked'), reader = r.body.getReader();
  await assert.rejects(h.fetch(r), TypeError); assert.equal(h.calls.length, 0); reader.releaseLock();
});
test('replacement body on consumed Request does not read consumed input', async () => {
  const h = harness(), r = request('used'); await r.text();
  await h.fetch(r, { body: 'replacement' }); assert.equal(h.calls[0].body, 'replacement');
});
test('arrayBuffer read error rejects, never silently posts empty body', async () => {
  const h = harness(), r = request('error');
  r.clone = () => ({ arrayBuffer: async () => { throw new TypeError('stream failure'); } });
  await assert.rejects(h.fetch(r), /stream failure/); assert.equal(h.calls.length, 0);
});
for (const method of ['GET', 'HEAD']) {
  test(method + ' never clones/reads Request or init.body', async () => {
    const h = harness(), r = request('ignored'); r.clone = () => { throw new Error('must not clone'); };
    await h.fetch(r, { method, get body() { throw new Error('must not access'); } });
    assert.equal(h.calls[0].body, null); assert.equal(h.calls[0].method, method);
  });
}
test('bodyless POST Request stays null without clone', async () => {
  const h = harness(), r = request(undefined); r.clone = () => { throw new Error('must not clone'); };
  await h.fetch(r); assert.equal(h.calls[0].body, null);
});
for (const host of ['local', 'direct']) {
  test(host + ' origin passes exact Request/init through without reading', async () => {
    const h = harness(), r = new Request('https://' + host + '.test/path', { method: 'POST', body: 'native' });
    r.clone = () => { throw new Error('must not clone'); };
    const init = { get body() { throw new Error('must not access'); } };
    await h.fetch(r, init); assert.equal(h.calls.length, 0);
    assert.equal(h.direct[0][0], r); assert.equal(h.direct[0][1], init);
  });
}
test('existing string URL init conversion and header override unchanged', async () => {
  const h = harness(); await h.fetch(url, { method: 'post', body: { a: 1 }, headers: { origin: 'custom' } });
  assert.equal(h.calls[0].body, '{"a":1}'); assert.equal(h.calls[0].headers.origin, 'custom');
});
test('patch is idempotent/fail-closed and preserves latest relay + all non-shim members', () => {
  const code = `import importlib.util, io, zipfile
spec=importlib.util.spec_from_file_location('patch', ${JSON.stringify(patch)})
p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
raw=p.ARCHIVE.read_bytes()
result, shim, changed=p.prepare(raw)
assert p.prepare(result)==(result, shim, False)
for data in [shim.replace(p.NEW.encode(), b'partial'), shim+p.OLD.encode()]:
 try: p.patch_shim(data)
 except ValueError: pass
 else: raise AssertionError('ambiguous/partial accepted')
# Simulate another agent's newer relay edits at application time, in memory only.
out=io.BytesIO()
with zipfile.ZipFile(io.BytesIO(raw)) as z, zipfile.ZipFile(out,'w') as dest:
 dest.comment=b'latest relay archive'
 for info in z.infolist():
  data=z.read(info.filename)
  if info.filename==p.MEMBER: data += b'\\n// latest-relay-shim-sentinel\\n'
  dest.writestr(info,data)
 dest.writestr('request-test-relay-sentinel.txt', b'latest relay member')
latest=out.getvalue(); updated, patched, _=p.prepare(latest)
assert patched.endswith(b'// latest-relay-shim-sentinel\\n')
with zipfile.ZipFile(io.BytesIO(latest)) as a, zipfile.ZipFile(io.BytesIO(updated)) as b:
 assert a.comment==b.comment and a.namelist()==b.namelist()
 for name in a.namelist():
  if name!=p.MEMBER: assert a.read(name)==b.read(name)
  ai,bi=a.getinfo(name),b.getinfo(name)
  for attr in ('date_time','compress_type','external_attr','internal_attr','comment','extra','create_system'):
   assert getattr(ai,attr)==getattr(bi,attr), (name,attr)
assert p.ARCHIVE.read_bytes()==raw
print('archive integrity/idempotence/fail-closed/relay preservation PASS')`;
  const result = execFileSync('python3', ['-B', '-c', code]).toString();
  assert.match(result, /PASS/);
});
