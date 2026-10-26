const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages', name + '.ets'), 'utf8');
test('native close is silent before panel creation and after open; user close notifies only once', () => {
  const s = source('LocalWeb');
  const start = s.indexOf('function close(notify)');
  const end = s.indexOf('function syncLamp()', start);
  assert.ok(start > 0 && end > start);
  let messages = 0;
  const c = vm.createContext({ mask: null, panel: null, window: {}, send: () => messages++ });
  vm.runInContext(s.slice(start, end), c);
  c.window.__vtSrvClose();
  assert.equal(messages, 0);
  let open = true;
  c.mask = { style: {} };
  c.panel = { style: {}, getAttribute: () => open ? 'true' : null, removeAttribute: () => { open = false; } };
  c.window.__vtSrvClose();
  assert.equal(messages, 0);
  assert.equal(open, false);
  open = true;
  c.close(); c.close();
  assert.equal(messages, 1);
});
for (const name of ['LocalWeb', 'Index']) {
  const guards = [...source(name).matchAll(/if \(event.targetUrl.toLowerCase\(\).startsWith\('vitreus:'\)\) \{[\s\S]*?\n\s*\}/g)].map(m => m[0]);
  test(name + ' main and chained popups reject internal URLs without affecting external/OAuth URLs', () => {
    assert.equal(guards.length, 2);
    for (const guard of guards) {
      const run = new Function('event', guard + '\nreturn "continue";');
      for (const url of ['vitreus://ai-hide', 'VITREUS://srv-close', 'vitreus://ai-refresh']) {
        const values = [];
        assert.equal(run({ targetUrl: url, handler: { setWebController: v => values.push(v) } }), undefined);
        assert.deepEqual(values, [null]);
      }
      for (const url of ['https://example.org/login', 'obsidian://callback', 'about:blank', '']) {
        assert.equal(run({ targetUrl: url, handler: { setWebController() { throw Error('unexpected interception'); } } }), 'continue');
      }
    }
  });
}
