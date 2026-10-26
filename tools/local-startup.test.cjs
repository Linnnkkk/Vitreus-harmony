const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/NodeTest.ets'), 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^  (?:private )?${name}\\(`, 'm'));
  const end = source.indexOf('\n  }', start);
  return source.slice(start, end + 4).replace(/private /g, '').replace(/AppStorage\.get<\w+>/g, 'AppStorage.get').replace(/: (?:boolean|number|void)/g, '');
}
function launch({ assets = true, ready = false, forced = false } = {}) {
  const state = { ignisReady: ready, forceImportPage: forced };
  const timers = []; const calls = [];
  const context = vm.createContext({ AppStorage: { get: k => state[k], setOrCreate: (k, v) => state[k] = v },
    setTimeout: (fn, delay) => { timers.push({ fn, delay }); return timers.length; }, clearTimeout: () => {} });
  vm.runInContext(`class Page { ${['aboutToAppear', 'isCurrent', 'showStartupManagement'].map(method).join('\n')} }; globalThis.page = new Page();`, context);
  const p = context.page;
  Object.assign(p, { generation: 0, compactStartup: false, forcedImport: false, recoveryTimer: -1,
    hasObsidianAssets: () => assets, serverAlive: () => ready,
    scheduleReadyPage: delay => calls.push(['route', delay]), startNode: () => calls.push(['start']), typeStatus: () => {} });
  p.aboutToAppear(); return { p, calls, timers };
}
test('imported cold launch uses compact UI but still runs real startup/deployment', () => {
  const h = launch(); assert.equal(h.p.compactStartup, true); assert.deepEqual(h.calls, [['start']]);
  h.timers[0].fn(); assert.equal(h.p.compactStartup, false);
});
test('warm imported launch preserves existing ready route instead of depending on old log file', () => {
  const h = launch({ ready: true }); assert.equal(h.p.compactStartup, true); assert.deepEqual(h.calls, [['route', 800]]);
});
test('missing assets and forced import keep management UI', () => {
  for (const opts of [{ assets: false }, { forced: true, ready: true }]) {
    assert.equal(launch(opts).p.compactStartup, false);
  }
});
test('stale recovery callback cannot change returned page', () => {
  const h = launch(); h.p.generation++; h.timers[0].fn(); assert.equal(h.p.compactStartup, true);
});
test('failures expose management; native deployment and readiness checks remain', () => {
  assert.match(source, /this\.showStartupManagement\(\);\s*this\.typeStatus\('启动失败/);
  assert.match(source, /await this\.deployIgnis\(\)/);
  assert.match(source, /raw\.includes\('Server running'\)/);
  assert.match(source, /this\.scheduleReadyPage\(this\.compactStartup \? 180 : 550\)/);
  assert.match(source, /Button\('打开运行管理'\)/);
});
