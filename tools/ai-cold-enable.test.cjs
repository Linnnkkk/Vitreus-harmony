// Execute production page/bootstrap/restore code with isolated platform stubs.
// This verifies behavior in Node, not a HarmonyOS device or native deployment.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = name => fs.readFileSync(path.join(root, name + '.ets'), 'utf8');

function method(code, name) {
  const start = code.search(new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, `production method ${name} exists`);
  const end = code.indexOf('\n  }', start);
  assert.notEqual(end, -1, `production method ${name} ends`);
  return code.slice(start, end + 4)
    .replace(/\bprivate /g, '')
    .replace(/AppStorage\.get<\w+>/g, 'AppStorage.get')
    .replace(/ as (?:common\.UIAbilityContext|Error)/g, '')
    .replace(/: WebDavConfig \| undefined/g, '')
    .replace(/: Promise<(?:void|boolean)>/g, '')
    .replace(/: (?:boolean|number|void)\b/g, '');
}

function harness({ vip = true, ready = false, access = true, online = true } = {}) {
  const state = { ignisReady: ready, aiModeEnabled: false, aiRunning: false, bootMode: 'local' };
  const routes = [];
  const calls = { enable: 0, refresh: 0, polls: 0, lease: 0 };
  let running = false;
  const context = {};
  const ctx = {
    AppStorage: { get: key => state[key], setOrCreate: (key, value) => { state[key] = value; } },
    VipService: { isVip: () => vip },
    router: {
      replaceUrl: async route => { routes.push({ url: route.url, intent: state.aiModeEnabled }); },
      pushUrl: route => { routes.push({ url: route.url, intent: state.aiModeEnabled }); }
    },
    AiLanApi: {
      status: async () => ({ running, access: access ? { vaultIds: ['test-vault'], allowWrite: false } : undefined }),
      hasAccessPolicy: status => status.access !== undefined,
      enable: async () => { calls.enable++; running = true; return { running }; },
      disable: async () => { running = false; return { running }; }
    },
    LanShareApi: { status: async () => ({ running: false }), getLanIp: () => online ? '192.0.2.1' : '' },
    BackgroundLease: { reconcile: async () => { calls.lease++; return true; } },
    WebDavSettings: { load: () => undefined },
    WebDavMount: { verify: async () => '' }
  };
  vm.createContext(ctx);
  const restore = source('common/ServiceRestore')
    .replace(/^import .*;\n/gm, '')
    .replace('export class', 'class')
    .replace('private static task: Promise<void> | null = null;', 'static task = null;')
    .replace(/private static /g, 'static ')
    .replace(/context: common\.UIAbilityContext/g, 'context')
    .replace(/: Promise<void>/g, '')
    .replace(/AppStorage\.get<\w+>/g, 'AppStorage.get');
  const pageMethods = ['changeRunning', 'ensureServiceReady', 'onPageShow'];
  const nodeMethods = ['enterReadyPage', 'isCurrent'];
  vm.runInContext(`${restore}
    class AiPage { ${pageMethods.map(name => method(source('pages/AiConnectPage'), name)).join('\n')} }
    class NodePage { ${nodeMethods.map(name => method(source('pages/NodeTest'), name)).join('\n')} }
    globalThis.ai = new AiPage(); globalThis.boot = new NodePage();`, ctx);
  Object.assign(ctx.ai, {
    busy: false, pageAlive: true, pageVisible: true, epoch: 0, statusRevision: 0,
    getUIContext: () => ({ getHostContext: () => context }),
    refresh: () => { calls.refresh++; }, startPoll: () => { calls.polls++; }
  });
  Object.assign(ctx.boot, {
    pageAlive: true, bgVisible: true, navigationStarted: false, generation: 0,
    clearReadyTimer: () => {}, getUIContext: () => ({ getHostContext: () => context }),
    showStartupManagement: () => { assert.fail('bootstrap unexpectedly failed'); }
  });
  return { state, routes, calls, ai: ctx.ai, boot: ctx.boot, running: () => running };
}

test('one cold VIP enable persists intent before bootstrap and restores AI to running', async () => {
  const h = harness();
  await h.ai.changeRunning(true);
  assert.equal(h.calls.enable, 0, 'the cold page delegates activation to bootstrap');
  assert.equal(h.routes[0]?.url, 'pages/NodeTest');
  h.state.ignisReady = true; // platform stub: Node preparation has completed
  await h.boot.enterReadyPage();
  assert.equal(h.calls.enable, 1, 'real ServiceRestore must enable AI after the first toggle');
  assert.equal(h.running(), true);
  assert.equal(h.state.aiRunning, true);
  assert.equal(h.state.aiModeEnabled, true);
  assert.equal(h.routes[0].intent, true, 'intent must exist before the NodeTest route');
  assert.deepEqual(h.routes.map(route => route.url), ['pages/NodeTest', 'pages/AiConnectPage']);
  assert.equal(h.calls.lease, 1);
  await h.boot.enterReadyPage();
  assert.equal(h.calls.enable, 1, 'repeat ready callback does not enable again');
});

test('cold non-VIP enable routes to membership without recording intent or starting AI', async () => {
  const h = harness({ vip: false });
  await h.ai.changeRunning(true);
  assert.deepEqual(h.routes, [{ url: 'pages/VipPanelPage', intent: false }]);
  assert.equal(h.state.aiModeEnabled, false);
  assert.equal(h.state.bootMode, 'local');
  assert.equal(h.calls.enable, 0);
  assert.equal(h.running(), false);
});

for (const ready of [false, true]) {
  test(`configuration show with ready=${ready} does not record intent or enable AI`, () => {
    const h = harness({ ready });
    h.ai.onPageShow();
    h.ai.onPageShow();
    assert.equal(h.state.aiModeEnabled, false);
    assert.equal(h.state.bootMode, 'local');
    assert.equal(h.calls.enable, 0);
    assert.equal(h.running(), false);
    assert.deepEqual(h.routes, []);
    assert.equal(h.calls.refresh, ready ? 2 : 0);
    assert.equal(h.calls.polls, ready ? 2 : 0);
  });
}

for (const options of [{ access: false }, { online: false }]) {
  test(`cold intent still respects restore authorization/network guard: ${JSON.stringify(options)}`, async () => {
    const h = harness(options);
    await h.ai.changeRunning(true);
    h.state.ignisReady = true;
    await h.boot.enterReadyPage();
    assert.equal(h.calls.enable, 0);
    assert.equal(h.state.aiRunning, false);
    assert.equal(h.running(), false);
  });
}
