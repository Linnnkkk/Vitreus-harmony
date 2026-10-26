// Execute the real ArkTS polling method with only platform I/O and timers mocked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/NodeTest.ets'), 'utf8');
const start = source.indexOf('  private startPolling(');
const end = source.indexOf('  private bootLog(', start);
assert.ok(start >= 0 && end > start, 'production method boundaries exist');
const method = source.slice(start, end)
  .replace('private startPolling(statusPath: string)', 'startPolling(statusPath)')
  .replace(/: ReadOptions/g, '')
  .replace(/: string/g, '');

function fixture() {
  const calls = { buffers: [], reads: [], views: [], closes: [], intervals: [], clears: [],
    assets: 0, writes: 0, routes: [], statuses: [], boot: [], prepares: [] };
  const storage = new Map();
  let content = '[ignis] waiting\n';
  let readError = false;
  let readLimit = Infinity;
  let exists = true;
  let assets = true;
  let log = '';
  let nextFd = 0;
  const sandbox = {
    ArrayBuffer: class extends ArrayBuffer {
      constructor(size) { super(size); calls.buffers.push(this); }
      slice() { throw Error('polling must not copy the buffer'); }
    },
    Uint8Array: class extends Uint8Array {
      constructor(buffer, offset, length) {
        super(buffer, offset, length);
        calls.views.push({ buffer, offset, length });
      }
    },
    fs: {
      OpenMode: { READ_ONLY: 1 },
      accessSync: () => exists,
      statSync: () => ({ size: Buffer.byteLength(content) }),
      openSync: () => ({ fd: ++nextFd }),
      readSync(fd, buffer, opts) {
        calls.reads.push({ fd, buffer, ...opts });
        if (readError) throw Error('read failed');
        const bytes = Buffer.from(content).subarray(opts.offset, opts.offset + Math.min(opts.length, readLimit));
        new Uint8Array(buffer).set(bytes);
        return bytes.length;
      },
      closeSync: file => calls.closes.push(file.fd)
    },
    setInterval(callback, delay) { calls.intervals.push({ callback, delay }); return calls.intervals.length; },
    clearInterval: id => calls.clears.push(id),
    AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
    webview: { WebviewController: { prepareForPageLoad: (...args) => calls.prepares.push(args) } }
  };
  vm.createContext(sandbox);
  vm.runInContext('class Page {' + method + '}; globalThis.page = new Page()', sandbox);
  const page = sandbox.page;
  Object.assign(page, {
    pageAlive: true, pollTimer: -1, webReady: false, compactStartup: false,
    hasObsidianAssets() { calls.assets++; return assets; },
    bootLog: stage => calls.boot.push(stage),
    typeStatus: status => calls.statuses.push(status),
    scheduleReadyPage: delay => calls.routes.push(delay)
  });
  Object.defineProperty(page, 'nodeLog', {
    get: () => log,
    set(value) { calls.writes++; log = value; }
  });
  return { page, calls, storage,
    poll: () => calls.intervals.at(-1).callback(),
    content: value => { content = value; },
    log: value => { log = value; },
    readError: value => { readError = value; },
    readLimit: value => { readLimit = value; },
    exists: value => { exists = value; },
    assets: value => { assets = value; }
  };
}

test('consecutive polls reuse one 64K buffer and decode only actual bytes, without slice', () => {
  const f = fixture();
  f.page.startPolling('/status');
  f.content('[ignis] ' + 'x'.repeat(70000)); f.poll();
  f.content('[js] short\n'); f.poll();
  assert.equal(f.calls.buffers.length, 1);
  assert.equal(f.calls.buffers[0].byteLength, 65536);
  assert.equal(f.calls.reads[0].buffer, f.calls.reads[1].buffer);
  assert.equal(f.calls.reads[0].offset, 70008 - 65536);
  assert.equal(f.calls.reads[0].length, 65536);
  assert.equal(f.calls.reads[1].offset, 0);
  assert.equal(f.calls.views[1].buffer, f.calls.buffers[0]);
  assert.equal(f.calls.views[1].offset, 0);
  assert.equal(f.calls.views[1].length, Buffer.byteLength('[js] short\n'));
  assert.equal(f.page.nodeLog, '[js] short');
  assert.deepEqual(f.calls.closes, [1, 2]);
  assert.equal(f.calls.intervals[0].delay, 300);
  f.content('[cpp] partial\n[ignis] not read');
  f.readLimit(Buffer.byteLength('[cpp] partial\n')); f.poll();
  assert.equal(f.page.nodeLog, '[cpp] partial');
  assert.equal(f.calls.views[2].length, Buffer.byteLength('[cpp] partial\n'));
  assert.equal(f.calls.buffers.length, 1);
});

test('each start owns a fresh buffer and replaces the previous timer; dead page does nothing', () => {
  const f = fixture();
  f.page.startPolling('/first'); f.poll();
  f.page.startPolling('/second'); f.poll();
  assert.equal(f.calls.buffers.length, 2);
  assert.notEqual(f.calls.reads[0].buffer, f.calls.reads[1].buffer);
  assert.deepEqual(f.calls.clears, [1]);
  assert.equal(f.page.statusPath, '/second');
  f.page.pageAlive = false; f.page.startPolling('/dead');
  assert.equal(f.calls.buffers.length, 2);
  assert.equal(f.calls.intervals.length, 2);
  assert.equal(f.page.statusPath, '/second');
});

test('read exception still closes the opened file and subsequent polls recover', () => {
  const f = fixture(); f.page.startPolling('/status');
  f.readError(true); assert.doesNotThrow(f.poll);
  assert.deepEqual(f.calls.closes, [1]);
  assert.equal(f.calls.writes, 0);
  f.readError(false); f.poll();
  assert.deepEqual(f.calls.closes, [1, 2]);
  assert.equal(f.page.nodeLog, '[ignis] waiting');
  assert.equal(f.calls.buffers.length, 1);
});

test('same log does not write state again but still checks assets and ready every poll', () => {
  const f = fixture(); f.page.startPolling('/status');
  f.content('Server running\n[ignis] same\n'); f.assets(false); f.poll();
  assert.equal(f.calls.writes, 1);
  assert.equal(f.page.webReady, true);
  assert.equal(f.storage.get('ignisReady'), true);
  assert.deepEqual(f.calls.routes, []);
  f.poll(); f.poll();
  assert.equal(f.calls.writes, 1);
  assert.equal(f.calls.assets, 3);
  assert.equal(f.calls.reads.length, 3);
  // Equal-size content with a newly ready server must not be skipped via metadata.
  const g = fixture(); g.page.startPolling('/status');
  g.content('xxxxxxxxx\n[ignis] same\n'); g.poll();
  g.content('listening\n[ignis] same\n'); g.poll();
  assert.equal(g.calls.writes, 1);
  assert.equal(g.page.webReady, true);
  assert.deepEqual(g.calls.routes, [550]);
});

test('log filtering retains last 40 node lines plus web hooks and ready route timing', () => {
  for (const compact of [false, true]) for (const ready of ['Server running', 'listening']) {
    const f = fixture(); f.page.compactStartup = compact;
    f.log('[ignis] old\n[web:info] keep\n[web:error] keep too');
    const lines = Array.from({ length: 45 }, (_, i) => '[ignis] line ' + i);
    f.content('noise\n' + lines.join('\n') + '\n' + ready + '\n');
    f.page.startPolling('/status'); f.poll(); f.poll();
    assert.equal(f.page.nodeLog, lines.slice(-40).concat(['[web:info] keep', '[web:error] keep too']).join('\n'));
    assert.equal(f.calls.writes, 1);
    assert.equal(f.page.webReady, true);
    assert.equal(f.storage.get('ignisReady'), true);
    assert.deepEqual(f.calls.routes, [compact ? 180 : 550]);
    assert.deepEqual(f.calls.statuses, ['启动完成']);
    assert.deepEqual(f.calls.boot, ['server running detected']);
    assert.deepEqual(f.calls.prepares, [['http://127.0.0.1:6791', true, 2]]);
    assert.equal(f.calls.assets, 2);
  }
});

test('missing and empty status files leave state untouched and polling alive', () => {
  const f = fixture(); f.page.startPolling('/status');
  f.exists(false); f.poll();
  f.exists(true); f.content(''); f.poll();
  assert.equal(f.calls.reads.length, 0);
  assert.equal(f.calls.writes, 0);
  assert.equal(f.calls.assets, 0);
  f.content('[cpp] recovered'); f.poll();
  assert.equal(f.page.nodeLog, '[cpp] recovered');
});
