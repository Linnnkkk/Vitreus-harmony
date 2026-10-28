const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'pages/WebDavSettingsPage.ets'), 'utf8');
const settings = fs.readFileSync(path.join(root, 'common/WebDavSettings.ets'), 'utf8');
const probe = fs.readFileSync(path.join(root, 'common/WebDavProbe.ets'), 'utf8');
function method(name, text = source) {
  const start = text.search(new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return text.slice(start, text.indexOf('\n  }', start) + 4)
    .replace(/\b(private|static) /g, '')
    .replace(/: Promise<(?:void|WebDavProbeResult)>/g, '')
    .replace(/: (?:void|boolean|string|number|WebDavProbeResult|WebDavConfig|http\.HttpRequestOptions|rcp\.RequestHeaders)/g, '')
    .replace(/: WebDavCredential \| undefined/g, '')
    .replace(/ as (?:common\.UIAbilityContext|http\.RequestMethod|BusinessError|Error|string)/g, '')
    .replace(/ as Record<string, string>/g, '')
    .replace(/AppStorage\.get<(?:boolean|string)>/g, 'AppStorage.get');
}
const runtimeValues = new Map();
const settingsCtx = { AppStorage: { get: key => runtimeValues.get(key) } };
vm.createContext(settingsCtx);
vm.runInContext(`class Settings { ${['normalizeUrl', 'vaultNameFromUrl', 'connectionKey', 'needsRestart'].map(n => method(n, settings)).join('\n')} }; globalThis.WebDavSettings = { normalizeUrl: Settings.prototype.normalizeUrl, vaultNameFromUrl: Settings.prototype.vaultNameFromUrl, connectionKey: Settings.prototype.connectionKey, needsRestart: Settings.prototype.needsRestart };`, settingsCtx);
const WebDavSettings = settingsCtx.WebDavSettings;
function makePage(overrides = {}) {
  const ctx = {
    WebDavCredentialStore: { load: async () => ({ user: 'user', pwd: 'secret' }), save: async () => true },
    WebDavSettings: { ...WebDavSettings, needsRestart: () => true, save: () => true },
    VipService: { isVip: () => true },
    WebDavProbe: { test: async () => ({ ok: true, message: 'success' }) },
    ...overrides
  };
  vm.createContext(ctx);
  vm.runInContext(`class Page { ${['edited', 'loadCredential', 'onPageHide', 'onPageShow', 'changeEnabled', 'requireVip', 'validate', 'testConnection', 'disableSaved', 'save', 'savedResult'].map(n => method(n)).join('\n')} }; globalThis.page = new Page();`, ctx);
  Object.assign(ctx.page, {
    pageAlive: true, loadEpoch: 0, editEpoch: 0, operationEpoch: 0, credentialId: 'id',
    credentialLoading: false, loadFailed: false, saving: false, savePending: false, testing: false,
    message: '', user: 'user', pwd: 'secret', url: 'https://example.com/dav/notes', webDavEnabled: true,
    loadedUser: '', loadedPwd: '', testPassed: false, getUIContext: () => ({ getHostContext: () => ({}) }),
    showRestartDialog: () => { ctx.dialogShown = true; }
  });
  return { page: ctx.page, ctx };
}
function gate() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
test('nonmember enable routes to purchase without switching on, while disabling remains available', () => {
  const routes = [];
  const { page } = makePage({ VipService: { isVip: () => false }, router: { pushUrl: r => routes.push(r.url) } });
  page.webDavEnabled = false;
  page.changeEnabled(true);
  assert.deepEqual(routes, ['pages/VipPanelPage']); assert.equal(page.webDavEnabled, false);
  page.webDavEnabled = true; page.changeEnabled(false); assert.equal(page.webDavEnabled, false);
  assert.equal(routes.length, 1);
});
test('member enable updates draft and does not navigate away', () => {
  const { page } = makePage({ router: { pushUrl: () => { throw Error('unexpected navigation'); } } });
  page.webDavEnabled = false; page.changeEnabled(true); assert.equal(page.webDavEnabled, true);
});
test('restoring bindings during credential loading does not lock the page', async () => {
  const g = gate(); const { page } = makePage({ WebDavCredentialStore: { load: () => g.promise } });
  const pending = page.loadCredential(); page.edited();
  g.resolve({ user: 'loaded', pwd: 'loaded-secret' }); await pending;
  assert.equal(page.user, 'loaded'); assert.equal(page.pwd, 'loaded-secret');
  assert.equal(page.credentialLoading, false); assert.equal(page.loadFailed, false);
});
test('a real intervening edit is preserved and page remains usable', async () => {
  const g = gate(); const { page } = makePage({ WebDavCredentialStore: { load: () => g.promise } });
  const pending = page.loadCredential(); page.editEpoch++; page.user = 'typed';
  g.resolve({ user: 'old', pwd: 'old' }); await pending;
  assert.equal(page.user, 'typed'); assert.equal(page.pwd, 'secret');
  assert.equal(page.credentialLoading, false); assert.equal(page.loadFailed, false);
});
test('return from hidden page cannot apply stale credentials and can reload', async () => {
  const g = gate(); let loads = 0;
  const { page } = makePage({ WebDavCredentialStore: { load: () => ++loads === 1 ? g.promise : Promise.resolve({ user: 'fresh', pwd: 'fresh' }) } });
  const pending = page.loadCredential(); page.onPageHide(); g.resolve({ user: 'old', pwd: 'old' }); await pending;
  assert.equal(page.user, 'user'); page.onPageShow(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.user, 'fresh'); assert.equal(page.credentialLoading, false);
});
test('credential errors have a working retry', async () => {
  let loads = 0;
  const { page } = makePage({ WebDavCredentialStore: { load: async () => { if (++loads === 1) { throw Error('private'); } return { user: 'retry', pwd: 'ok' }; } } });
  await page.loadCredential(); assert.equal(page.loadFailed, true); assert.equal(page.credentialLoading, false);
  await page.loadCredential(); assert.equal(page.loadFailed, false); assert.equal(page.user, 'retry');
});
test('URL final directory decodes automatically, including legacy saved URLs', () => {
  assert.equal(WebDavSettings.vaultNameFromUrl('https://example.com/dav/%E7%AC%94%E8%AE%B0///'), '笔记');
  assert.equal(WebDavSettings.vaultNameFromUrl('https://example.com/old-library'), 'old-library');
  for (const url of ['https://example.com/', 'https://user:pass@example.com/dav', 'https://example.com/dav?secret=1', 'https://example.com/%2Fbad', 'https://example.com/%00', 'https://example.com/.hidden', 'https://example.com/%ZZ']) {
    assert.throws(() => WebDavSettings.vaultNameFromUrl(url), undefined, url);
  }
});
test('nonmembers cannot test or save, even if UI state was stale', async () => {
  let requests = 0; let writes = 0;
  const { page } = makePage({ VipService: { isVip: () => false }, WebDavProbe: { test: async () => { requests++; } }, WebDavCredentialStore: { save: async () => { writes++; } } });
  page.vip = true; await page.testConnection(); await page.save();
  assert.equal(requests, 0); assert.equal(writes, 0); assert.match(page.message, /会员/);
});
test('saving always tests current credentials; failed test writes nothing', async () => {
  let writes = 0; let captured;
  const { page } = makePage({ WebDavProbe: { test: async (...args) => { captured = args; return { ok: false, message: 'denied' }; } }, WebDavCredentialStore: { save: async () => { writes++; } } });
  page.testPassed = true; page.pwd = 'new-password'; await page.save();
  assert.deepEqual(captured, ['https://example.com/dav/notes', 'user', 'new-password']);
  assert.equal(writes, 0); assert.equal(page.saving, false); assert.equal(page.message, 'denied');
});
test('successful save derives name and needs no restart before local service starts', async () => {
  let config; let probes = 0;
  const { page, ctx } = makePage({ WebDavSettings: { ...WebDavSettings, save: (_, value) => { config = value; return true; } }, WebDavProbe: { test: async () => { probes++; return { ok: true, message: 'ok' }; } } });
  page.url = 'https://example.com/dav/%E7%AC%94%E8%AE%B0/'; await page.save();
  assert.equal(probes, 1); assert.equal(config.vaultName, '笔记'); assert.equal(config.url.endsWith('/'), false);
  assert.equal(ctx.dialogShown, undefined); assert.match(page.message, /已保存/);
  assert.equal(page.saving, false); assert.equal(page.savePending, false);
});
test('saved remote configuration can be disabled without network access', async () => {
  let requests = 0, saved;
  const previous = { enabled: true, url: 'https://example.com/dav/notes', vaultName: 'notes', credentialId: 'id' };
  const { page, ctx } = makePage({
    WebDavSettings: { ...WebDavSettings, load: () => ({ ...previous }), save: (_, value) => { saved = value; return true; } },
    WebDavProbe: { test: async () => { requests++; throw Error('offline'); } }
  });
  page.disableSaved();
  assert.equal(requests, 0); assert.equal(saved.enabled, false); assert.equal(saved.credentialId, 'id');
  assert.equal(ctx.dialogShown, undefined);
});

test('expired members can disable an existing vault without credentials or network', () => {
  let saved;
  const { page, ctx } = makePage({
    VipService: { isVip: () => false },
    WebDavSettings: { ...WebDavSettings, load: () => ({ enabled: true, vaultName: 'notes', credentialId: 'id' }), save: (_, value) => { saved = value; return true; } },
    WebDavProbe: { test: () => { throw Error('must not connect'); } }
  });
  page.loadFailed = true; page.disableSaved();
  assert.equal(saved.enabled, false); assert.equal(page.webDavEnabled, false); assert.equal(ctx.dialogShown, undefined);
});

test('restart is based on the running connection rather than merely saving settings', () => {
  const config = { enabled: true, url: 'https://example.com/dav/notes', vaultName: 'notes', credentialId: 'id' };
  runtimeValues.clear();
  assert.equal(WebDavSettings.needsRestart(config), false);
  runtimeValues.set('webDavRuntimeStarted', true);
  runtimeValues.set('webDavRuntimeKey', '');
  assert.equal(WebDavSettings.needsRestart({ ...config, enabled: false }), false);
  assert.equal(WebDavSettings.needsRestart(config), true);
  runtimeValues.set('webDavRuntimeKey', WebDavSettings.connectionKey(config));
  assert.equal(WebDavSettings.needsRestart(config), false);
  for (const changed of [{ enabled: false }, { credentialId: 'new' }, { url: 'https://example.com/dav/other' }]) {
    assert.equal(WebDavSettings.needsRestart({ ...config, ...changed }), true);
  }
  runtimeValues.clear();
});

test('unchanged credentials are reused and repeated save does not request restart', async () => {
  let writes = 0;
  const config = { enabled: true, url: 'https://example.com/dav/notes', vaultName: 'notes', credentialId: 'id' };
  runtimeValues.set('webDavRuntimeStarted', true);
  runtimeValues.set('webDavRuntimeKey', WebDavSettings.connectionKey(config));
  const { page, ctx } = makePage({ WebDavSettings: { ...WebDavSettings, save: () => true },
    WebDavCredentialStore: { save: async () => { writes++; return true; } } });
  page.loadedUser = 'user'; page.loadedPwd = 'secret';
  await page.save();
  assert.equal(writes, 0); assert.equal(page.credentialId, 'id'); assert.equal(ctx.dialogShown, undefined);
  runtimeValues.clear();
});

test('saving an inactive connection does not require restart or discard edited credentials', async () => {
  let saved;
  const { page, ctx } = makePage({ WebDavSettings: { ...WebDavSettings, save: (_, config) => { saved = config; return true; } } });
  page.webDavEnabled = false; page.pwd = 'new';
  await page.save();
  assert.equal(saved.enabled, false); assert.notEqual(saved.credentialId, 'id'); assert.equal(ctx.dialogShown, undefined);
  assert.match(page.message, /无需重启/);
});

test('hide or edit during validation prevents saving and stale results', async () => {
  for (const action of ['hide', 'edit']) {
    const g = gate(); let writes = 0;
    const { page } = makePage({ WebDavProbe: { test: () => g.promise }, WebDavCredentialStore: { save: async () => { writes++; return true; } } });
    const pending = page.save(); if (action === 'hide') { page.onPageHide(); } else { page.edited(); }
    g.resolve({ ok: true, message: 'ok' }); await pending;
    assert.equal(writes, 0); page.onPageShow(); assert.equal(page.saving, false);
  }
});
test('membership expiry while request runs prevents writes', async () => {
  const g = gate(); let vip = true; let writes = 0;
  const { page } = makePage({ VipService: { isVip: () => vip }, WebDavProbe: { test: () => g.promise }, WebDavCredentialStore: { save: async () => { writes++; } } });
  const pending = page.save(); vip = false; g.resolve({ ok: true, message: 'ok' }); await pending;
  assert.equal(writes, 0); assert.equal(page.saving, false);
});
test('hidden test cannot overwrite a fresh test after returning', async () => {
  const g = gate(); let count = 0;
  const { page } = makePage({ WebDavProbe: { test: () => ++count === 1 ? g.promise : Promise.resolve({ ok: true, message: 'fresh' }) } });
  const pending = page.testConnection(); page.onPageHide(); page.onPageShow(); await page.testConnection();
  g.resolve({ ok: false, message: 'stale' }); await pending;
  assert.equal(page.message, 'fresh'); assert.equal(page.testing, false); assert.equal(page.testPassed, true);
});
const probeCtx = {};
vm.createContext(probeCtx);
vm.runInContext(`class Probe { ${method('inspect', probe)} }; globalThis.inspect = Probe.prototype.inspect;`, probeCtx);
const collection = '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/notes/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';
test('only 207 with successful directory properties passes, never OPTIONS 200', () => {
  assert.equal(probeCtx.inspect(207, collection).ok, true);
  assert.equal(probeCtx.inspect(200, collection).ok, false);
  assert.equal(probeCtx.inspect(207, collection.replace('200 OK', '403 Forbidden')).ok, false);
  assert.equal(probeCtx.inspect(207, collection.replace('<d:collection/>', '')).ok, false);
  assert.equal(probeCtx.inspect(207, '<html>login password</html>').ok, false);
  assert.equal(probeCtx.inspect(207, '<!DOCTYPE foo>' + collection).ok, false);
  for (const code of [401, 403, 404, 405, 500]) { assert.equal(probeCtx.inspect(code, 'password-private').message.includes('password-private'), false); }
});
test('probe uses native HTTP with Basic auth, actual PROPFIND, Depth:0 and bounded lifetime', async () => {
  let options; let endpoint; let destroyed = 0; let sessionOptions;
  const ctx = { rcp: { Request: class { constructor(url, method, headers, content) { this.url = url; this.method = method; this.headers = headers; this.content = content; } }, createSession: configuration => { sessionOptions = configuration; return { fetch: async request => { endpoint = request.url; options = request; return { statusCode: 207, toString: () => collection }; }, close: () => { destroyed++; } }; } }, util: { Base64Helper: class { encodeToStringSync(value) { return Buffer.from(value).toString('base64'); } }, TextEncoder } };
  vm.createContext(ctx);
  vm.runInContext(`class Probe { ${method('inspect', probe)} ${method('test', probe)} }; globalThis.WebDavProbe = { inspect: Probe.prototype.inspect }; globalThis.run = Probe.prototype.test;`, ctx);
  const result = await ctx.run('https://example.com/dav/notes', '名字', 'secret');
  assert.equal(result.ok, true); assert.equal(options.method, 'PROPFIND'); assert.equal(options.headers.Depth, '0');
  assert.equal(options.headers.Authorization, 'Basic ' + Buffer.from('名字:secret').toString('base64'));
  assert.equal(endpoint, 'https://example.com/dav/notes/'); assert.equal(destroyed, 1);
  assert.ok(sessionOptions.requestConfiguration.transfer.timeout.connectMs > 0);
  assert.ok(sessionOptions.requestConfiguration.transfer.timeout.transferMs > 0);
});
test('probe timeout is clear and transport errors never expose secrets', async () => {
  for (const code of [2300028, 2300006]) {
    let destroyed = 0;
    const ctx = { rcp: { Request: class {}, createSession: () => ({ fetch: async () => { throw { code, message: 'https://user:secret@example.com private' }; }, close: () => { destroyed++; } }) }, util: { Base64Helper: class { encodeToStringSync() { return 'auth'; } }, TextEncoder } };
    vm.createContext(ctx);
    vm.runInContext(`class Probe { ${method('test', probe)} }; globalThis.run = Probe.prototype.test;`, ctx);
    const result = await ctx.run('https://example.com/dav', 'user', 'secret');
    assert.equal(result.ok, false); assert.doesNotMatch(result.message, /secret|private|example/);
    if (code === 2300028) { assert.match(result.message, /超时/); } assert.equal(destroyed, 1);
  }
});
test('page uses theme cards, no manual name, and common attributes only in Styles', () => {
  assert.doesNotMatch(source, /text: \$\$this\.vaultName|@State private enabled/);
  assert.match(source, /RestartPrompt\.show/); assert.match(source, /系统最近任务/); assert.match(source, /pages\/VipPanelPage/);
  for (const style of source.matchAll(/@Styles\s+\w+\(\)\s*\{([\s\S]*?)\n  \}/g)) { assert.doesNotMatch(style[1], /\.fontColor|\.placeholderColor|\.type\(/); }
  assert.doesNotMatch(probe, /console\.|hilog\.|OPTIONS|X-HTTP-Method/);
});
