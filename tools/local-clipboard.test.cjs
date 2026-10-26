'use strict';

// Execute the production methods, not a reimplementation of their guards.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/LocalWeb.ets'), 'utf8');
const readStart = source.indexOf('  private async readClipboardForWeb(');
assert.notEqual(readStart, -1);
const readMethod = source.slice(readStart, source.indexOf('\n  private injectObsidianInset(', readStart))
  .replace('private async readClipboardForWeb(id: number): Promise<void>', 'async function readClipboardForWeb(id)')
  .replace('(): boolean =>', '() =>')
  .replace("let text: string = '';", "let text = '';")
  .replace(' as common.UIAbilityContext', '');
const safeStart = source.indexOf('  private safeRun(');
const safeMethod = source.slice(safeStart, source.indexOf('\n  // 网页读剪贴板', safeStart))
  .replace('private safeRun(js: string): void', 'function safeRun(js)');
const safeRun = new Function('return (' + safeMethod + ')')();

function deferred() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

function harness(options = {}) {
  const calls = { permission: 0, data: 0, primary: 0, scripts: [] };
  const state = { url: 'http://127.0.0.1:6791/', throwUrl: false };
  const board = {
    async getData() {
      calls.data++;
      if (options.dataError) { throw new Error('pasteboard unavailable'); }
      if (options.data) { await options.data.promise; }
      return { getPrimaryText() { calls.primary++; return options.text ?? 'hello "clipboard"\n'; } };
    }
  };
  const read = new Function('ensurePermissions', 'pasteboard', 'hilog', 'return (' + readMethod + ')')(
    async () => {
      calls.permission++;
      if (options.permissionError) { throw new Error('permission unavailable'); }
      if (options.permission) { return options.permission.promise; }
      return options.granted !== false;
    },
    { getSystemPasteboard: () => board },
    { info() {}, warn() {}, error() {} }
  );
  const page = {
    pageAlive: true,
    localVisible: true,
    getUIContext: () => ({ getHostContext: () => ({}) }),
    webController: {
      getUrl() {
        if (state.throwUrl) { throw new Error('Web detached'); }
        return state.url;
      },
      runJavaScript(script) {
        if (options.scriptError) { throw new Error('Web detached'); }
        calls.scripts.push(script);
      }
    },
    safeRun,
    readClipboardForWeb: read
  };
  return { page, state, calls };
}

function reply(h) {
  assert.equal(h.calls.scripts.length, 1);
  let received;
  new Function('window', h.calls.scripts[0])({ __vtClipDone: (id, text) => { received = { id, text }; } });
  return received;
}

for (const url of ['http://127.0.0.1:6791', 'http://127.0.0.1:6791/', 'http://127.0.0.1:6791/vault?q=1#note']) {
  test('trusted URL: ' + url, async () => {
    const h = harness();
    h.state.url = url;
    await h.page.readClipboardForWeb(7);
    assert.deepEqual(reply(h), { id: 7, text: 'hello "clipboard"\n' });
    assert.equal(h.calls.data, 1);
  });
}

for (const url of [
  'https://example.com/', 'http://127.0.0.1:67910/', 'http://127.0.0.1:6791.evil/',
  'http://127.0.0.1:6791@evil.test/', 'http://user@127.0.0.1:6791/',
  'http://127.0.0.1:6791:80/', 'https://127.0.0.1:6791/', 'http://localhost:6791/',
  'http://127.0.0.1:6791\\@evil.test/', 'http://127.0.0.1:6791?@evil.test', '', 'about:blank'
]) {
  test('reject untrusted URL: ' + url, async () => {
    const h = harness();
    h.state.url = url;
    await h.page.readClipboardForWeb(7);
    assert.equal(h.calls.permission, 0);
    assert.equal(h.calls.data, 0);
    assert.deepEqual(h.calls.scripts, []);
  });
}

test('destroyed page does not request permission', async () => {
  const h = harness();
  h.page.pageAlive = false;
  await h.page.readClipboardForWeb(1);
  assert.equal(h.calls.permission, 0);
});

test('temporary hide during permission UI keeps pageAlive semantics', async () => {
  const permission = deferred();
  const h = harness({ permission });
  const pending = h.page.readClipboardForWeb(1);
  h.page.localVisible = false;
  permission.resolve(true);
  await pending;
  assert.equal(h.calls.data, 1);
  assert.equal(reply(h).id, 1);
});

for (const stage of ['permission', 'data']) {
  for (const change of ['navigate', 'destroy', 'getUrl throws']) {
    test(change + ' during ' + stage + ' blocks further read/refill', async () => {
      const gate = deferred();
      const h = harness({ [stage]: gate });
      const pending = h.page.readClipboardForWeb(1);
      // Flush permission continuation so getData has started for the data-stage cases.
      await Promise.resolve();
      await Promise.resolve();
      if (stage === 'data') { assert.equal(h.calls.data, 1); }
      if (change === 'navigate') { h.state.url = 'https://evil.test/'; }
      if (change === 'destroy') { h.page.pageAlive = false; }
      if (change === 'getUrl throws') { h.state.throwUrl = true; }
      gate.resolve(true);
      await pending;
      assert.equal(h.calls.data, stage === 'data' ? 1 : 0);
      assert.equal(h.calls.primary, 0);
      assert.deepEqual(h.calls.scripts, []);
    });
  }
}

test('getUrl throwing at entry is contained', async () => {
  const h = harness();
  h.state.throwUrl = true;
  await h.page.readClipboardForWeb(1);
  assert.equal(h.calls.permission, 0);
  assert.deepEqual(h.calls.scripts, []);
});

for (const option of ['permissionError', 'dataError', 'denied']) {
  test(option + ' returns empty text only to a live trusted page', async () => {
    const h = harness(option === 'denied' ? { granted: false } : { [option]: true });
    await h.page.readClipboardForWeb(3);
    assert.deepEqual(reply(h), { id: 3, text: '' });
    assert.equal(h.calls.data, option === 'dataError' ? 1 : 0);
  });
}

test('navigation before refill is checked again', async () => {
  const h = harness();
  let checks = 0;
  const originalGetUrl = h.page.webController.getUrl;
  h.page.webController.getUrl = () => {
    checks++;
    if (checks === 4) { h.state.url = 'https://evil.test/'; }
    return originalGetUrl();
  };
  await h.page.readClipboardForWeb(1);
  assert.equal(h.calls.primary, 1);
  assert.deepEqual(h.calls.scripts, []);
});

test('safeRun contains detached Web errors during refill', async () => {
  const h = harness({ scriptError: true });
  await h.page.readClipboardForWeb(1);
  assert.equal(h.calls.data, 1);
  assert.deepEqual(h.calls.scripts, []);
});

test('one-time pairing secret stays filtered', async () => {
  const h = harness({ text: '{"pairingCode":"test-only","fingerprint":"test-only","deviceId":"test-only"}' });
  await h.page.readClipboardForWeb(4);
  assert.deepEqual(reply(h), { id: 4, text: '' });
});
