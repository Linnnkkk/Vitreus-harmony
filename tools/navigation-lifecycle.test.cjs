// Execute extracted production methods with fake platform dependencies/timers.
// This is an isolated behavior regression suite, not a HarmonyOS/router integration test.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const pages = path.join(__dirname, '../entry/src/main/ets/pages');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, `production method ${name} exists`);
  const end = source.indexOf('\n  }', start);
  return source.slice(start, end + 4)
    .replace(/\bprivate /g, '')
    .replace(/AppStorage\.get<\w+>/g, 'AppStorage.get')
    .replace(/ as (?:common\.UIAbilityContext|Error)/g, '')
    .replace(/: (?:Promise<void>|boolean|string|number|void|ReadOptions)\b/g, '')
    .replace(/: Promise<void>/g, '');
}
function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
function harness(page, names, overrides = {}) {
  const source = fs.readFileSync(path.join(pages, page + '.ets'), 'utf8');
  const timers = new Map(); const retired = []; const routes = []; const state = {}; let seq = 0;
  const ctx = {
    console, Date, ArrayBuffer, Uint8Array,
    setTimeout: f => { timers.set(++seq, f); return seq; },
    clearTimeout: id => { if (timers.has(id)) retired.push(timers.get(id)); timers.delete(id); },
    setInterval: f => { timers.set(++seq, f); return seq; },
    clearInterval: id => timers.delete(id),
    AppStorage: { get: k => state[k], setOrCreate: (k, v) => { state[k] = v; } },
    router: { replaceUrl: async x => { routes.push(x.url); }, pushUrl: x => { routes.push(x.url); } },
    ServiceRestore: { once: async () => {} },
    // Persistence semantics are exercised by startup-preferences.test; this suite isolates routing.
    StartupPreferences: { enterMode: (_context, mode) => { state.appMode = mode; return true; } },
    getContext: () => ({ filesDir: '/sandbox' }),
    fs: { unlinkSync: () => {} },
    QuickCapture: { saveVaultRoot: () => {} }, startNodeServer: () => {}, hapticSelect: () => {},
    ...overrides
  };
  vm.createContext(ctx);
  vm.runInContext(`class Page { ${names.map(n => method(source, n)).join('\n')} }; globalThis.instance = new Page();`, ctx);
  const p = ctx.instance;
  Object.assign(p, {
    pageAlive: true, bgVisible: true, generation: 0, starting: false, startupPending: false, navigationStarted: false,
    readyTimer: -1, importTimer: -1, pollTimer: -1, typeTimer: -1, routeTimer: -1,
    updateNoticeTimer: -1, selectedCard: '', webReady: false, statusPath: '',
    getUIContext: () => ({ getHostContext: () => ({}) }),
    bootLog: () => {}, typeStatus: () => {}, hasObsidianAssets: () => false,
    bundleStale: () => false, reimportPending: () => false,
    deployIgnis: async () => '/entry.js', ensureVaultRootAsync: async () => '/vault', startPolling: () => {}
  });
  return { p, state, routes, timers, retired, ctx, fire() { const batch = [...timers.values()]; timers.clear(); for (const fn of batch) fn(); } };
}
const nodeMethods = ['showStartupManagement', 'isCurrent', 'clearReadyTimer', 'scheduleReadyPage', 'enterReadyPage', 'retry', 'resumePendingStartup', 'startNode', 'serverAlive', 'onPageShow', 'onPageHide', 'aboutToDisappear'];
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };
test('ready timeout is canceled on hide/disappear and stale callback cannot route', async () => {
  for (const lifecycle of ['onPageHide', 'aboutToDisappear']) {
    const h = harness('NodeTest', nodeMethods);
    h.p.scheduleReadyPage(550); h.p.scheduleReadyPage(800);
    assert.equal(h.timers.size, 1);
    h.p[lifecycle](); assert.equal(h.timers.size, 0);
    h.p.pageAlive = true; // a later show must not revive a queued old generation
    for (const cb of h.retired) cb();
    await flush(); assert.deepEqual(h.routes, []);
  }
});
test('retry wins pending auto timeout; restore and replace happen once', async () => {
  const gate = deferred(); let restores = 0;
  const h = harness('NodeTest', nodeMethods, { ServiceRestore: { once: () => { restores++; return gate.promise; } } });
  h.p.webReady = true; h.state.bootMode = 'ai';
  h.p.scheduleReadyPage(550); h.p.retry(); h.p.retry();
  h.fire(); gate.resolve(); await flush();
  assert.equal(restores, 1); assert.deepEqual(h.routes, ['pages/AiConnectPage']);
});
test('restore completion after leaving (even returning) never replaces old target', async () => {
  const gate = deferred(); const h = harness('NodeTest', nodeMethods, { ServiceRestore: { once: () => gate.promise } });
  const pending = h.p.enterReadyPage(); h.p.onPageHide(); h.p.pageAlive = true;
  gate.resolve(); await pending; assert.deepEqual(h.routes, []);
});
test('failed replace unlocks explicit retry', async () => {
  let attempts = 0;
  const h = harness('NodeTest', nodeMethods, { router: { replaceUrl: async () => { if (++attempts === 1) throw Error('router'); } } });
  await h.p.enterReadyPage(); assert.equal(h.p.navigationStarted, false);
  await h.p.enterReadyPage(); assert.equal(attempts, 2);
});
test('startNode is single-flight while deployment is pending and clears lock on failure', async () => {
  const gate = deferred(); let deploys = 0, starts = 0;
  const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
  h.p.deployIgnis = () => { deploys++; return gate.promise; };
  const first = h.p.startNode(); await h.p.startNode(); h.p.retry();
  assert.equal(deploys, 1); gate.reject(Error('deploy')); await first;
  assert.equal(h.p.starting, false); assert.equal(starts, 0);
  h.p.deployIgnis = async () => '/entry.js'; await h.p.startNode(); assert.equal(starts, 1);
});
for (const phase of ['deploy', 'vault']) test(`leave during ${phase} await prevents native startup and polling`, async () => {
  const gate = deferred(); let starts = 0, polls = 0, vaults = 0;
  const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
  h.p.deployIgnis = () => phase === 'deploy' ? gate.promise : Promise.resolve('/entry.js');
  h.p.ensureVaultRootAsync = () => { vaults++; return phase === 'vault' ? gate.promise : Promise.resolve('/vault'); };
  h.p.startPolling = () => { polls++; };
  const pending = h.p.startNode(); await flush(); h.p.onPageHide(); h.p.pageAlive = true;
  gate.resolve('/done'); await pending;
  assert.equal(starts, 0); assert.equal(polls, 0); assert.equal(vaults, phase === 'deploy' ? 0 : 1);
});
for (const phase of ['deploy', 'vault']) {
  for (const showBeforeResolve of [true, false]) test(`${phase}: hide/show ${showBeforeResolve ? 'before' : 'after'} await settles resumes once`, async () => {
    const gate = deferred(); let deploys = 0, activeDeploys = 0, maxDeploys = 0, vaults = 0, starts = 0;
    const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
    h.p.deployIgnis = async () => {
      deploys++; activeDeploys++; maxDeploys = Math.max(maxDeploys, activeDeploys);
      try { return phase === 'deploy' && deploys === 1 ? await gate.promise : '/entry.js'; }
      finally { activeDeploys--; }
    };
    h.p.ensureVaultRootAsync = () => ++vaults === 1 && phase === 'vault' ? gate.promise : Promise.resolve('/vault');
    const pending = h.p.startNode(); await flush(); h.p.onPageHide();
    if (showBeforeResolve) { h.p.onPageShow(); h.p.onPageShow(); assert.equal(deploys, 1); }
    gate.resolve('/done'); await pending; await flush();
    if (!showBeforeResolve) { assert.equal(starts, 0); h.p.onPageShow(); await flush(); }
    await flush();
    assert.equal(starts, 1); assert.equal(maxDeploys, 1); assert.equal(h.p.starting, false);
    assert.equal(h.p.startupPending, false); assert.equal(h.p.generation, 1);
    h.p.onPageHide(); h.p.onPageShow(); await flush();
    assert.equal(starts, 1, 'ordinary management return must not start again');
  });
  test(`${phase}: actual departure never starts, interrupted failure can be retried`, async () => {
    for (const reject of [false, true]) {
      const gate = deferred(); let starts = 0;
      const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
      h.p.deployIgnis = () => phase === 'deploy' ? gate.promise : Promise.resolve('/entry.js');
      h.p.ensureVaultRootAsync = () => phase === 'vault' ? gate.promise : Promise.resolve('/vault');
      const pending = h.p.startNode(); await flush(); h.p.aboutToDisappear();
      if (reject) gate.reject(Error('interrupted')); else gate.resolve('/done');
      await pending; await flush(); assert.equal(starts, 0); assert.equal(h.p.starting, false);
      assert.equal(h.p.startupPending, false);
      h.p.onPageShow(); await flush(); assert.equal(starts, 0);
      h.p.deployIgnis = async () => '/entry.js'; h.p.ensureVaultRootAsync = async () => '/vault';
      h.p.retry(); await flush(); await flush(); assert.equal(starts, 1);
    }
  });
}
test('resumed deployment failure stops automatic attempts and permits explicit retry', async () => {
  const gate = deferred(); let deploys = 0, starts = 0;
  const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
  h.p.deployIgnis = () => ++deploys === 1 ? gate.promise : Promise.reject(Error('deploy'));
  const pending = h.p.startNode(); h.p.onPageHide(); h.p.onPageShow();
  gate.resolve('/entry.js'); await pending; await flush();
  assert.equal(deploys, 2); assert.equal(starts, 0); assert.equal(h.p.starting, false);
  h.p.onPageShow(); await flush(); assert.equal(deploys, 2);
  h.p.deployIgnis = async () => '/entry.js'; h.p.retry(); await flush(); await flush(); assert.equal(starts, 1);
});
test('picker-covered await never starts in background and resumes on show', async () => {
  const gate = deferred(); let starts = 0;
  const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
  h.p.ensureVaultRootAsync = () => gate.promise;
  const pending = h.p.startNode(); await flush(); h.p.pickerActive = true; h.p.onPageHide();
  h.p.pickerActive = false; gate.resolve('/vault'); await pending;
  assert.equal(starts, 0); assert.equal(h.p.generation, 0);
  h.p.ensureVaultRootAsync = async () => '/vault'; h.p.onPageShow(); await flush(); await flush();
  assert.equal(starts, 1);
});
test('picker return before await settles keeps the same generation and starts once', async () => {
  const gate = deferred(); let starts = 0, deploys = 0;
  const h = harness('NodeTest', nodeMethods, { startNodeServer: () => { starts++; } });
  h.p.deployIgnis = async () => { deploys++; return '/entry.js'; };
  h.p.ensureVaultRootAsync = () => gate.promise;
  const pending = h.p.startNode(); await flush(); h.p.pickerActive = true; h.p.onPageHide();
  h.p.onPageShow(); h.p.pickerActive = false; gate.resolve('/vault'); await pending;
  assert.equal(starts, 1); assert.equal(deploys, 1); assert.equal(h.p.generation, 0);
  h.p.onPageShow(); await flush(); assert.equal(starts, 1);
});
test('system picker hide preserves current request but route destruction invalidates it', () => {
  const h = harness('NodeTest', nodeMethods);
  h.p.pickerActive = true;
  h.p.onPageHide();
  assert.equal(h.p.pageAlive, true);
  assert.equal(h.p.generation, 0);
  h.p.aboutToDisappear();
  assert.equal(h.p.pageAlive, false);
  assert.equal(h.p.generation, 1);
});
const modeMethods = ['selectCard', 'clearRouteTimer', 'onPageHide', 'aboutToDisappear'];
function clickCard(h, card) {
  const source = fs.readFileSync(path.join(pages, 'ModeSelect.ets'), 'utf8');
  const callbacks = [...source.matchAll(/\.onClick\(\(\) => \{([^{}]*)\}\)/g)];
  const callback = callbacks.find(m => m[1].includes(`this.selectCard('${card}'`));
  assert.ok(callback, `actual ${card} click callback exists`);
  // Execute the actual UI callback too: pre-guard AppStorage writes must be observable.
  vm.runInContext(`(function () { ${callback[1]} }).call(instance)`, h.ctx);
}
test('actual UI callbacks: rejected AI click cannot overwrite accepted local destination', () => {
  const h = harness('ModeSelect', modeMethods);
  clickCard(h, 'local'); clickCard(h, 'ai');
  assert.equal(h.state.bootMode, 'local'); assert.equal(h.state.appMode, 'local');
  h.fire(); assert.deepEqual(h.routes, ['pages/NodeTest']);
});
test('actual UI callbacks persist each accepted mode after server mode', () => {
  for (const mode of ['local', 'ai', 'srv', 'remote']) {
    const h = harness('ModeSelect', modeMethods); h.state.bootMode = 'srv';
    clickCard(h, mode); assert.equal(h.state.bootMode, mode);
    h.fire(); assert.deepEqual(h.routes, [mode === 'remote' ? 'pages/Login' : 'pages/NodeTest']);
  }
});
for (const first of ['local', 'srv', 'ai', 'remote']) test(`accepted ${first} click owns bootMode despite rapid second click`, () => {
  const h = harness('ModeSelect', modeMethods);
  h.p.selectCard(first, first, first === 'remote' ? 'pages/Login' : 'pages/NodeTest');
  h.p.selectCard(first === 'ai' ? 'local' : 'ai', 'ai', 'pages/NodeTest');
  assert.equal(h.state.bootMode, first); assert.equal(h.state.appMode, first);
  assert.equal(h.timers.size, 1); h.fire(); assert.equal(h.routes.length, 1);
});
test('ModeSelect clears route timer on both exit hooks; stale callback cannot push', () => {
  for (const lifecycle of ['onPageHide', 'aboutToDisappear']) {
    const h = harness('ModeSelect', modeMethods);
    h.p.selectCard('local', 'local', 'pages/NodeTest'); h.p[lifecycle]();
    assert.equal(h.timers.size, 0); h.p.pageAlive = true;
    for (const cb of h.retired) cb();
    assert.deepEqual(h.routes, []);
  }
});
