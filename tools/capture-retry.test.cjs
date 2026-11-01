// Production Service + Engine + DAV/native requesters; only SDK, settings and transport are fixtures.
// No network requests, user settings or disk writes are performed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const root = path.join(__dirname, '../entry/src/main/ets/common');

function fixture(native = false, disk = new Map(), remoteFiles = new Map()) {
  const files = remoteFiles, calls = [], diskWrites = [];
  const handles = new Map(); let nextHandle = 0;
  const intents = new Map();
  let config = { enabled: true, vaultName: 'PARA', credentialId: 'abc', url: 'https://dav.example/dav/PARA' };
  let templates = { version: 1, quickNotePath: '', quickNoteHeading: '', clipPath: '' };
  let server = 'https://ignis.example', member = true, version = 1, dropPath, beforeCredential;
  let clipFetches = 0, failDiskStage;
  const collection = '<d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';
  const response = (statusCode, body = '', headers = {}) => ({ statusCode, headers, toString: () => body });
  const json = (status, data) => response(status, JSON.stringify(data), { 'content-type': 'application/json' });
  const fileKey = (base, name) => base + '/' + name;
  function put(key, content) {
    files.set(key, { body: content, etag: '"v' + version++ + '"' });
    if (dropPath && key.endsWith('/' + dropPath)) { dropPath = undefined; throw Error('response lost after commit'); }
  }
  const sandbox = {
    console, URL, TextEncoder,
    AppStorage: { get: key => key === 'serverUrl' ? (native ? server : '') : undefined },
    fs: {
      OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
      accessSync: p => disk.has(p), readTextSync: p => disk.get(p),
      openSync: p => { diskWrites.push(p); const fd = ++nextHandle; handles.set(fd, p); disk.set(p, ''); return { fd }; },
      writeSync: (fd, value) => { if (failDiskStage && JSON.parse(value).stage === failDiskStage) throw Error('disk full'); disk.set(handles.get(fd), value); }, closeSync: fd => handles.delete(fd),
      renameSync: (from, to) => { disk.set(to, disk.get(from)); disk.delete(from); }
    },
    hilog: {},
    url: { URL },
    util: { TextEncoder, Base64Helper: class { encodeToStringSync(v) { return Buffer.from(v).toString('base64'); } } },
    webview: { WebCookieManager: { fetchCookie: async () => '' } },
    RemoteServerSettings: { restore() {} },
    RemoteCredentialStore: { load: async () => undefined },
    WebDavCredentialStore: { load: async () => { if (beforeCredential) { const fn = beforeCredential; beforeCredential = undefined; fn(); } return { user: 'fixture', pwd: 'secret' }; } },
    VipService: { isVip: () => member },
    CapturePathSettings: { load: () => ({ ...templates }) },
    WebClip: {
      pickUrl: text => text.startsWith('https://') ? text : '', skipped: () => ({ ok: false }),
      fetch: async () => { clipFetches++; return { ok: true, title: 'Fixture article', body: 'Captured body', metadata: { site: 'fixture', author: '', published: '', description: '', canonical: '' } }; }
    },
    rcp: {
      Request: class { constructor(target, method, headers) { Object.assign(this, { url: target, method, headers }); } },
      createSession: () => ({ close() {}, fetch: async req => {
        calls.push(req);
        const target = new URL(req.url);
        if (target.pathname.startsWith('/api/')) {
          if (target.pathname === '/api/version') return json(200, { version: 'fixture' });
          if (target.pathname === '/api/vault/list') return json(200, [{ id: 'remote', name: 'Remote' }]);
          if (req.method === 'GET') {
            const value = files.get(fileKey(target.origin, target.searchParams.get('path')));
            return value ? response(200, value.body, { 'content-type': 'text/plain' }) : json(404, { code: 'ENOENT' });
          }
          const value = JSON.parse(req.content);
          if (target.pathname.endsWith('/mkdir')) return json(200, { ok: true });
          const key = fileKey(target.origin, value.path);
          put(key, target.pathname.endsWith('/appendFile') ? files.get(key).body + value.content : value.content);
          return json(200, { ok: true });
        }
        if (req.method === 'PROPFIND') return response(207, collection, { 'content-type': 'application/xml' });
        if (req.method === 'MKCOL') return response(201);
        const key = decodeURIComponent(req.url), value = files.get(key);
        if (req.method === 'GET') return value ? response(200, value.body, { etag: value.etag, 'content-type': 'text/markdown' }) : response(404);
        if (req.headers['If-None-Match'] === '*' && value) return response(412);
        if (req.headers['If-Match'] && (!value || req.headers['If-Match'] !== value.etag)) return response(412);
        if (req.method === 'PUT') { put(key, req.content); return response(201); }
        throw Error('unexpected request ' + req.method);
      } })
    }
  };
  vm.createContext(sandbox);
  for (const [name, expose] of [
    ['CapturePathTemplate', 'CapturePathTemplate'], ['QuickCapture', 'QuickCapture'],
    ['WebDavSettings', 'WebDavSettings'], ['RemoteCapture', 'RemoteCapture,RemoteCaptureEngine'],
    ['WebDavProbe', 'WebDavProbe'], ['WebDavCaptureHttp', 'createWebDavCaptureRequester'],
    ['RemoteCaptureHttp', 'createNativeRemoteRequester'], ['RemoteCaptureService', 'RemoteCaptureService']
  ]) {
    const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8')
      .replace(/^import .*;\n/gm, '').replace(/export (class|function|interface|type)/g, '$1');
    vm.runInContext('(function(){' + stripTypeScriptTypes(source) + ';Object.assign(globalThis,{' + expose + '});})();', sandbox);
  }
  sandbox.WebDavSettings.load = () => ({ ...config });
  const context = { filesDir: '/fixture' };
  const newIntent = () => sandbox.RemoteCapture.newIntent();
  const capture = (text, kind = 'quick', options = {}) => {
    // Caller fixture owns intent identity, just as the production pages do.
    const label = options.intent ?? text;
    if (!intents.has(label)) intents.set(label, newIntent());
    return sandbox.RemoteCaptureService.capture(context, text,
      options.isTask ?? false, options.addTime ?? true, kind,
      options.vault ?? { id: native ? 'remote' : 'webdav:abc', name: 'stale page name' }, intents.get(label));
  };
  return {
    capture, files, calls, diskWrites, disk, intents, newIntent,
    failDisk: stage => { failDiskStage = stage; },
    restart: () => { const next = fixture(native, disk, files); for (const [k, v] of intents) next.intents.set(k, v); return next; }, config: () => config, templates: () => templates,
    setConfig: c => { config = c; }, setTemplates: t => { templates = t; }, setServer: s => { server = s; },
    setMember: m => { member = m; }, onCredential: fn => { beforeCredential = fn; },
    drop: p => { dropPath = p; }, fetches: () => clipFetches,
    key: p => fileKey(native ? server : config.url, p),
    writes: () => calls.filter(c => c.method === 'PUT' || c.method === 'POST' && !c.url.endsWith('/mkdir')).length
  };
}

for (const native of [false, true]) {
  test(`${native ? 'Ignis' : 'WebDAV'} Service retry confirms lost index response without another mutation; successful same input is a new submission`, async () => {
    const f = fixture(native);
    await f.capture('seed'); // exercise append to an existing note, not just initial create
    f.drop('Inbox.md');
    await assert.rejects(f.capture('once'), /未知/);
    const writes = f.writes();
    const recovered = await f.capture('once');
    assert.equal(recovered.stage, 'done'); assert.equal(f.writes(), writes);
    assert.equal(f.files.get(f.key('Inbox.md')).body.split('once').length - 1, 1);
    const next = await f.capture('once', 'quick', { intent: 'new once' });
    assert.notEqual(next.id, recovered.id);
    assert.equal(f.files.get(f.key('Inbox.md')).body.split('once').length - 1, 2);
    assert.ok(f.diskWrites.length > 0);
    assert.ok([...f.disk.keys()].every(p => !p.includes('remote-capture-pending')));
  });
}

test('clip PUT response lost: retry reuses original body/path/time, one clip and one index entry', async () => {
  const f = fixture(); f.setTemplates({ ...f.templates(), clipPath: 'Clips/article.md' });
  f.drop('Clips/article.md'); await assert.rejects(f.capture('https://article.example/a', 'share'), /未知/);
  const op = await f.capture('https://article.example/a', 'share');
  assert.equal(op.clipPath, 'Clips/article.md'); assert.equal(f.fetches(), 1);
  assert.equal(f.calls.filter(c => c.method === 'PUT' && c.url.endsWith('/Clips/article.md')).length, 1);
  assert.equal([...f.files.keys()].filter(k => k.includes('/Clips/')).length, 1);
  assert.equal(f.files.get(f.key('Inbox.md')).body.split('[[Clips/article]]').length - 1, 1);
});

test('confirmed clipping permits another deliberate submission of the same URL', async () => {
  const f = fixture(); f.setTemplates({ ...f.templates(), clipPath: 'Clips/article.md' });
  const first = await f.capture('https://article.example/a', 'share');
  const second = await f.capture('https://article.example/a', 'share', { intent: 'second share' });
  assert.notEqual(first.id, second.id); assert.equal(second.clipPath, 'Clips/article (2).md');
  assert.equal(f.fetches(), 2); assert.equal([...f.files.keys()].filter(k => k.includes('/Clips/')).length, 2);
});

test('clip index response lost: retry neither creates suffix clip nor appends another link', async () => {
  const f = fixture(); f.setTemplates({ ...f.templates(), clipPath: 'Clips/article.md' });
  f.drop('Inbox.md'); await assert.rejects(f.capture('https://article.example/a', 'share'), /未知/);
  const writes = f.writes(); await f.capture('https://article.example/a', 'share');
  assert.equal(f.writes(), writes); assert.equal(f.fetches(), 1);
  assert.equal([...f.files.keys()].filter(k => k.includes('/Clips/')).length, 1);
});

test('old unknown result does not block new input; changed remote content is never overwritten by old retry', async () => {
  const f = fixture(); f.drop('Inbox.md'); await assert.rejects(f.capture('old'), /未知/);
  await f.capture('different new');
  const before = f.files.get(f.key('Inbox.md')).body, writes = f.writes();
  await assert.rejects(f.capture('old'), /快照不一致/);
  assert.equal(f.writes(), writes); assert.equal(f.files.get(f.key('Inbox.md')).body, before);
});

test('same DAV credential alias with changed URL or vault name cannot reuse a failed target snapshot', async () => {
  const f = fixture(), original = { ...f.config() };
  f.drop('Inbox.md'); await assert.rejects(f.capture('same'), /未知/);
  const originalBody = f.files.get(f.key('Inbox.md')).body;
  f.setConfig({ ...original, url: 'https://dav.example/dav/OTHER', vaultName: 'OTHER' });
  await assert.rejects(f.capture('same'), /变更/);
  const other = await f.capture('same', 'quick', { intent: 'other config' }); assert.equal(other.stage, 'done');
  assert.equal(other.webDavKey.includes('OTHER'), true);
  f.setConfig(original); const writes = f.writes(); await f.capture('same');
  assert.equal(f.writes(), writes); assert.equal(f.files.get(f.key('Inbox.md')).body, originalBody);
});

test('path rule changes save to new rule; restoring old rule recovers old unknown operation', async () => {
  const f = fixture(), original = { ...f.templates() };
  f.drop('Inbox.md'); await assert.rejects(f.capture('same'), /未知/);
  f.setTemplates({ ...original, quickNotePath: 'New.md', quickNoteHeading: '## Notes' });
  await assert.rejects(f.capture('same'), /变更/);
  const next = await f.capture('same', 'quick', { intent: 'new rules' }); assert.equal(next.quickPath, 'New.md');
  assert.match(f.files.get(f.key('New.md')).body, /## Notes/);
  f.setTemplates(original); const writes = f.writes(); await f.capture('same'); assert.equal(f.writes(), writes);
});

test('DAV settings switched during credential await send no requests to either target', async () => {
  const f = fixture(); f.onCredential(() => f.setConfig({ ...f.config(), url: 'https://other.example/dav/PARA' }));
  await assert.rejects(f.capture('same'), /变更/); assert.equal(f.calls.length, 0);
});

test('Ignis server changes isolate failed captures and restoring server recovers original snapshot', async () => {
  const f = fixture(true); f.drop('Inbox.md'); await assert.rejects(f.capture('same'), /未知/);
  f.setServer('https://other.example'); await assert.rejects(f.capture('same'), /变更/);
  await f.capture('same', 'quick', { intent: 'other server' });
  f.setServer('https://ignis.example'); const writes = f.writes(); await f.capture('same'); assert.equal(f.writes(), writes);
});

for (const native of [false, true]) {
  test(`${native ? 'Ignis' : 'DAV'} cold module restart restores same intent and preserves A after B`, async () => {
    const f = fixture(native);
    f.drop('Inbox.md'); await assert.rejects(f.capture('A'), /未知/);
    const aPath = '/fixture/capture-retry-' + f.intents.get('A') + '.json';
    const aSnapshot = f.disk.get(aPath);
    const restarted = f.restart();
    const writes = restarted.writes();
    const a = await restarted.capture('A');
    assert.equal(a.id, f.intents.get('A')); assert.equal(restarted.writes(), writes);
    assert.equal(JSON.parse(restarted.disk.get(aPath)).after, '');
    // A second uncertain operation stays independent while a new submission proceeds.
    restarted.drop('Inbox.md'); await assert.rejects(restarted.capture('unconfirmed'), /未知/);
    const pendingPath = '/fixture/capture-retry-' + restarted.intents.get('unconfirmed') + '.json';
    const pending = restarted.disk.get(pendingPath);
    await restarted.capture('B');
    assert.equal(restarted.disk.get(pendingPath), pending);
    const again = restarted.restart(), before = again.files.get(again.key('Inbox.md')).body;
    await assert.rejects(again.capture('unconfirmed'), /快照不一致/);
    assert.equal(again.files.get(again.key('Inbox.md')).body, before);
    assert.equal(again.writes(), 0);
    assert.ok(aSnapshot.includes('indexUnknown'));
  });

  test(`${native ? 'Ignis' : 'DAV'} explicit fresh identity accepts same text after unknown result`, async () => {
    const f = fixture(native);
    f.drop('Inbox.md'); await assert.rejects(f.capture('identical'), /未知/);
    const oldId = f.intents.get('identical');
    const next = await f.capture('identical', 'quick', { intent: 'fresh event' });
    assert.notEqual(next.id, oldId);
    assert.equal(f.files.get(f.key('Inbox.md')).body.split('identical').length - 1, 2);
    assert.equal(JSON.parse(f.disk.get('/fixture/capture-retry-' + oldId + '.json')).stage, 'indexUnknown');
  });
}

test('operation snapshot write failure prevents all content writes', async () => {
  const f = fixture();
  f.failDisk('indexWriting');
  await assert.rejects(f.capture('bad'), /disk full/);
  const record = JSON.parse(f.disk.get('/fixture/capture-retry-' + f.intents.get('bad') + '.json'));
  assert.equal(record.stage, 'prepared');
  assert.equal(f.writes(), 0);
});

function pageMethods(pageName, names, sandbox) {
  const source = fs.readFileSync(path.join(root, '../pages/' + pageName + '.ets'), 'utf8');
  const methods = names.map(name => {
    let start = source.indexOf('  private ' + name + '(');
    if (start < 0) start = source.indexOf('  private async ' + name + '(');
    assert.ok(start >= 0, name);
    const end = source.indexOf('\n  }', start) + 4;
    return source.slice(start, end).replace('private ', '');
  }).join('\n');
  vm.createContext(sandbox);
  vm.runInContext(stripTypeScriptTypes('class Page {' + methods + '} globalThis.Page = Page;'), sandbox);
  return new sandbox.Page();
}

test('production QuickNote draft methods restore explicit identity/options/target across fresh page instance', () => {
  const disk = new Map(), handles = new Map(); let serial = 0;
  const sandbox = { fs: {
    OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    accessSync: p => disk.has(p), readTextSync: p => disk.get(p),
    openSync: p => { const fd = ++serial; handles.set(fd, p); return { fd }; },
    writeSync: (fd, content) => disk.set(handles.get(fd), content), closeSync: fd => handles.delete(fd),
    renameSync: (a, b) => { disk.set(b, disk.get(a)); disk.delete(a); }
  } };
  const names = ['draftFile', 'saveDraft', 'loadDraft'];
  const page = pageMethods('QuickNote', names, sandbox), ctx = { filesDir: '/fixture' };
  Object.assign(page, { intentId: 'draft-A', isTask: true, addTime: false, remoteVaultId: 'webdav:abc' });
  page.saveDraft(ctx, 'same draft', true);
  const restored = new sandbox.Page();
  assert.equal(restored.loadDraft(ctx), 'same draft');
  assert.equal(restored.intentId, 'draft-A'); assert.equal(restored.remoteVaultId, 'webdav:abc');
  assert.equal(restored.isTask, true); assert.equal(restored.addTime, false);
  sandbox.fs.writeSync = () => { throw Error('disk full'); };
  assert.throws(() => restored.saveDraft(ctx, 'new', true), /尚未写入远程库/);
  assert.equal(JSON.parse(disk.get('/fixture/quick_note_draft.txt')).text, 'same draft');
});

test('production ShareCapture retry preserves identity and consuming a new same-text share rotates identity', () => {
  let serial = 0;
  const sandbox = {
    RemoteCapture: { newIntent: () => 'intent-' + ++serial },
    AppStorage: { setOrCreate() {}, get: () => ({ text: 'identical share' }) }
  };
  const page = pageMethods('ShareCapture', ['consume', 'retry'], sandbox);
  Object.assign(page, { readyTick: 1, consumedTick: 0, clearTimers() {}, run() {}, payloadText: 'identical share' });
  page.consume(); const first = page.intentId;
  page.retry(); assert.equal(page.intentId, first);
  page.readyTick = 2; page.consume(); assert.notEqual(page.intentId, first);
});

test('production QuickNote doSave retries with its draft identity and persists before requesting', async () => {
  const ids = [], events = [];
  const sandbox = { getContext: () => ({ filesDir: '/fixture' }), RemoteCaptureService: {
    capture: async (...args) => { events.push('request'); ids.push(args[6]); throw Error('lost response'); }
  } };
  const page = pageMethods('QuickNote', ['doSave'], sandbox);
  Object.assign(page, { text: 'draft', intentId: 'draft-operation', remoteMode: true,
    remoteVaults: [{ id: 'v', name: 'vault' }], remoteVaultId: 'v',
    saveDraft: () => events.push('draft') });
  await page.doSave(); await page.doSave();
  assert.deepEqual(ids, ['draft-operation', 'draft-operation']);
  assert.deepEqual(events, ['draft', 'request', 'draft', 'request']);
});
