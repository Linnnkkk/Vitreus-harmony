// Execute production helper and page methods; only Harmony SDK I/O is replaced.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = name => fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
function js(code) {
  return code.replace(/^import .*;\n/gm, '')
    .replace(/export interface \w+ \{[^}]*\}\n/g, '')
    .replace(/export class /g, 'class ').replace(/private /g, '')
    .replace(/ as (?:Record<string, Object>|common\.UIAbilityContext|string)/g, '')
    .replace(/AppStorage.get<\w+>/g, 'AppStorage.get')
    .replace(/: (?:common\.UIAbilityContext|StartupPreference|string|boolean|number|void)(?=\s*[,;)=\{])/g, '');
}
function fixture(files = new Map()) {
  const storage = new Map(); let failure = '';
  const io = { OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    accessSync: p => files.has(p),
    readTextSync(p) { if (failure === 'read' || !files.has(p)) throw Error('read'); return files.get(p); },
    openSync(p) { if (failure === 'open') throw Error('open'); return { fd: p }; },
    writeSync(p, s) { if (failure === 'write') throw Error('write'); files.set(p, s); }, closeSync() {},
    renameSync(a, b) { if (failure === 'rename') throw Error('rename'); files.set(b, files.get(a)); files.delete(a); } };
  const sandbox = { fs: io, AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) } };
  vm.createContext(sandbox);
  for (const name of ['StartupPreferences', 'CaptureModeSettings']) {
    vm.runInContext(js(source('common/' + name)) + ';globalThis.' + name + '=' + name, sandbox);
  }
  return { ...sandbox, files, storage, ctx: { filesDir: '/sandbox' }, fail: value => { failure = value; }, sandbox };
}
test('default remember is on and all four modes survive process restart with stale old memory', () => {
  for (const mode of ['local', 'remote', 'ai', 'srv']) {
    const f = fixture(); assert.equal(f.StartupPreferences.load(f.ctx).remember, true);
    assert.equal(f.StartupPreferences.enterMode(f.ctx, mode), true);
    const cold = fixture(new Map(f.files)); cold.storage.set('appMode', 'wrong');
    const config = cold.StartupPreferences.restore(cold.ctx);
    assert.equal(config.lastMode, mode); assert.equal(config.remember, true);
    assert.equal(cold.storage.get('appMode'), mode);
  }
});
test('turning remember off preserves last mode, and entering another mode preserves off', () => {
  const f = fixture(); const p = f.StartupPreferences;
  p.enterMode(f.ctx, 'ai'); assert.equal(p.setRemember(f.ctx, false), true);
  assert.equal(p.load(f.ctx).lastMode, 'ai'); assert.equal(p.load(f.ctx).remember, false);
  p.enterMode(f.ctx, 'srv'); const cold = fixture(new Map(f.files));
  assert.equal(cold.StartupPreferences.load(cold.ctx).lastMode, 'srv');
  assert.equal(cold.StartupPreferences.load(cold.ctx).remember, false);
  cold.StartupPreferences.setRemember(cold.ctx, true);
  assert.equal(cold.StartupPreferences.load(cold.ctx).lastMode, 'srv');
});
test('legacy appMode migrates only without file; missing remember defaults true; corrupt file never overwritten', () => {
  const f = fixture(); f.storage.set('appMode', 'remote'); const p = f.StartupPreferences;
  assert.equal(p.load(f.ctx).lastMode, 'remote'); f.storage.set('appMode', 'local');
  assert.equal(p.load(f.ctx).lastMode, 'remote');
  f.files.set(p.filePath(f.ctx), '{"lastMode":"ai"}'); assert.equal(p.load(f.ctx).remember, true);
  f.files.set(p.filePath(f.ctx), '{broken'); assert.equal(p.load(f.ctx).lastMode, '');
  assert.equal(f.files.get(p.filePath(f.ctx)), '{broken');
});
test('write/open/rename failures report false, keep disk preference and runtime main mode', () => {
  for (const failure of ['open', 'write', 'rename']) {
    const f = fixture(); const p = f.StartupPreferences; p.enterMode(f.ctx, 'remote'); f.fail(failure);
    assert.equal(p.enterMode(f.ctx, 'local'), false); assert.equal(p.setRemember(f.ctx, false), false);
    assert.equal(p.load(f.ctx).lastMode, 'remote'); assert.equal(p.load(f.ctx).remember, true);
    assert.equal(f.storage.get('appMode'), 'remote');
  }
});
test('real settings switch method rolls UI back and prompts on failure', () => {
  const f = fixture(); let prompts = 0;
  f.StartupPreferences.enterMode(f.ctx, 'local'); f.fail('rename');
  const raw = source('pages/CaptureSettings');
  const method = raw.slice(raw.indexOf('  private changeRememberMode('), raw.indexOf('  private load():'));
  vm.runInContext('class Page {' + js(method) + '}; globalThis.page = new Page()', f.sandbox);
  const page = f.sandbox.page; page.rememberMode = true;
  page.getUIContext = () => ({ getHostContext: () => f.ctx, getPromptAction: () => ({ showToast() { prompts++; } }) });
  page.changeRememberMode(false); assert.equal(page.rememberMode, true); assert.equal(prompts, 1);
});
test('real Splash dispatcher honors on/off and preserves existing service bootstrap routing', () => {
  const raw = source('pages/Splash');
  const method = raw.slice(raw.indexOf('  private scheduleDispatch()'), raw.indexOf('  aboutToDisappear()'));
  for (const mode of ['local', 'remote', 'ai', 'srv']) for (const remember of [true, false]) {
    const f = fixture(); f.StartupPreferences.enterMode(f.ctx, mode); f.StartupPreferences.setRemember(f.ctx, remember);
    f.storage.set('serverUrl', 'https://example.test'); f.storage.set('aiModeEnabled', true); f.storage.set('srvModeEnabled', true);
    let route; f.sandbox.router = { replaceUrl: v => { route = v.url; } }; f.sandbox.setTimeout = fn => { fn(); return 1; };
    vm.runInContext('class Page {' + js(method) + '};globalThis.page=new Page()', f.sandbox);
    f.sandbox.page.getUIContext = () => ({ getHostContext: () => f.ctx }); f.sandbox.page.scheduleDispatch();
    assert.equal(route, !remember ? 'pages/ModeSelect' : 'pages/NodeTest');
    assert.equal(f.storage.get('aiRunning'), undefined); assert.equal(f.storage.get('srvRunning'), undefined);
  }
});
test('capture selection and main mode are independent including share cold start', () => {
  const f = fixture(); f.StartupPreferences.enterMode(f.ctx, 'remote');
  const cold = fixture(new Map(f.files)); cold.storage.set('appMode', 'local');
  assert.equal(cold.CaptureModeSettings.isRemote(cold.ctx), true);
  cold.CaptureModeSettings.save(cold.ctx, false);
  assert.equal(cold.StartupPreferences.load(cold.ctx).lastMode, 'remote');
  assert.equal(cold.CaptureModeSettings.isRemote(cold.ctx), false);
  for (const name of ['pages/QuickNote', 'pages/ShareCapture']) {
    assert.doesNotMatch(source(name), /(?:setOrCreate\('appMode'|StartupPreferences\.(?:enterMode|setRemember))/);
  }
});
test('mode selection and connect persist before navigation; save-only does not change main mode', () => {
  const select = source('pages/ModeSelect');
  assert.ok(select.indexOf('StartupPreferences.enterMode(context, mode)') < select.indexOf('this.selectedCard = card;'));
  const login = source('pages/Login');
  assert.ok(login.indexOf('if (!connect)') < login.indexOf("StartupPreferences.enterMode(context, 'remote')"));
  assert.ok(login.indexOf("StartupPreferences.enterMode(context, 'remote')") < login.indexOf("await router.pushUrl({ url: 'pages/Index'"));
});
