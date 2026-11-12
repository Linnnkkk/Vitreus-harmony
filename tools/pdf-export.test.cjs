'use strict';
// Execute the real production class; only Harmony SDK APIs and timers are fixtures.
// No device, picker, network, or file-system writes are performed by these tests.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
process.env.ESBUILD_BINARY_PATH ||= '/tmp/ignis-build-deps-20261028/node_modules/@esbuild/linux-arm64/bin/esbuild';
const { transformSync } = require('/home/coder/workspace/Developing/ignis-study/node_modules/esbuild');
const sourcePath = path.join(__dirname, '../entry/src/main/ets/common/PdfExport.ets');
const source = fs.readFileSync(sourcePath, 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export class PdfExport\b/, 'class PdfExport');
const code = transformSync(source + '\nglobalThis.PdfExport = PdfExport;', { loader: 'ts', target: 'es2020' }).code;
const documentUrl = 'https://vault.example/obsidian';
const savedUri = 'file://docs/storage/Users/currentUser/Download/actual-name.pdf';
const pdf = new Uint8Array(Buffer.from('%PDF-1.7\nfixture body\n%%EOF\n'));
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function fixture(overrides = {}) {
  const settings = { bytes: pdf, uris: [savedUri], ready: '"ready"', ...overrides };
  const events = [], replies = [], loads = [], configs = [], pickerOptions = [], timers = new Map();
  let nextTimer = 0, currentUrl = documentUrl, available = true, caller = documentUrl;
  let stored = Buffer.alloc(0);
  function failure(stage) { if (settings.fail === stage) throw Error(stage + ' failed'); }
  function timer(kind, fn, delay) { const id = ++nextTimer; timers.set(id, { kind, fn, delay }); return id; }
  const main = {
    getUrl: () => currentUrl,
    getLastJavascriptProxyCallingFrameUrl: () => caller,
    runJavaScript: async script => {
      events.push('reply');
      vm.runInNewContext(script, { window: { __vitreusPdfResult: (id, result) => replies.push({ id, ...JSON.parse(JSON.stringify(result)) }) } });
    }
  };
  const sandbox = {
    webview: { WebviewController: class {
      loadData(...args) { events.push('load'); loads.push(args); }
      loadUrl(url) { events.push('blank:' + url); }
      async runJavaScript(script) {
        if (script.includes('String(window.__vtPdfReady')) {
          events.push('poll');
          if (settings.pollPromise) return settings.pollPromise;
          failure('poll'); return settings.ready;
        }
        events.push('prepare'); failure('prepare');
      }
      async createPdf(config) {
        events.push('createPdf'); configs.push(JSON.parse(JSON.stringify(config)));
        failure('createPdf');
        if (settings.createPromise) return settings.createPromise;
        return { pdfArrayBuffer: () => settings.bytes };
      }
    } },
    picker: {
      DocumentSaveOptions: class {},
      DocumentViewPicker: class {
        constructor(context) { assert.equal(context, abilityContext); }
        async save(options) {
          events.push('picker'); pickerOptions.push(options); failure('picker');
          if (settings.pickerError) throw settings.pickerError;
          return settings.pickerPromise || settings.uris;
        }
      }
    },
    fs: {
      OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
      openSync(uri, mode) {
        events.push('open'); failure('open'); assert.equal(uri, savedUri); assert.equal(mode, 7); return { fd: 17 };
      },
      writeSync(fd, buffer) {
        events.push('write'); failure('write'); assert.equal(fd, 17);
        stored = Buffer.from(new Uint8Array(buffer));
        return settings.partial ? stored.length - 1 : stored.length;
      },
      statSync(fd) {
        events.push('stat'); failure('stat'); assert.equal(fd, 17);
        return { size: stored.length + (settings.mismatch ? 1 : 0) };
      },
      fsyncSync(fd) { events.push('fsync'); failure('fsync'); assert.equal(fd, 17); },
      closeSync(file) { events.push('close'); failure('close'); assert.equal(file.fd, 17); }
    },
    setTimeout: (fn, delay) => timer('timeout', fn, delay), clearTimeout: id => timers.delete(id),
    setInterval: (fn, delay) => timer('interval', fn, delay), clearInterval: id => timers.delete(id)
  };
  const abilityContext = { fixture: true };
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: sourcePath });
  const instance = new sandbox.PdfExport(main, () => abilityContext, () => available,
    url => typeof url === 'string' && url.startsWith('https://vault.example/'));
  function start(options, id = 1) {
    instance.export(id, JSON.stringify({ html: '<html><head></head><body>Real document</body></html>',
      baseUrl: documentUrl, filename: 'note.pdf', options }));
  }
  async function fire(kind) {
    const entry = [...timers.entries()].find(([, value]) => value.kind === kind);
    assert.ok(entry, 'expected an active ' + kind);
    if (kind === 'timeout') timers.delete(entry[0]);
    entry[1].fn(); await flush();
  }
  async function prepare() { instance.onPageEnd(); await flush(); }
  async function render(options) { start(options); await prepare(); await fire('interval'); }
  return { instance, settings, events, replies, loads, configs, pickerOptions, timers, start, fire, prepare, render,
    stored: () => stored, navigate: url => { currentUrl = url; }, setAvailable: value => { available = value; },
    setCaller: value => { caller = value; } };
}
function failed(f, message, canceled = false) {
  assert.equal(f.replies.length, 1);
  assert.equal(f.replies[0].ok, false);
  assert.equal(f.replies[0].path, '');
  assert.equal(f.replies[0].canceled, canceled);
  assert.match(f.replies[0].error, message);
  assert.equal(f.timers.size, 0);
}

test('export/onPageEnd/poll/save writes exactly the PDF view, closes, then replies with picker URI', async () => {
  const backing = new Uint8Array(pdf.length + 8); backing.fill(255); backing.set(pdf, 3);
  const f = fixture({ bytes: backing.subarray(3, 3 + pdf.length) });
  f.start();
  assert.equal(f.replies.length, 0); assert.equal(f.events.includes('picker'), false);
  assert.match(f.loads[0][0], /<head><meta name="vitreus-pdf-job" content="1">/);
  assert.deepEqual(f.loads[0].slice(1), ['text/html', 'UTF-8', documentUrl]);
  await f.prepare();
  assert.equal(f.replies.length, 0); assert.equal(f.events.includes('createPdf'), false);
  await f.fire('interval');
  assert.deepEqual(f.stored(), Buffer.from(pdf));
  assert.deepEqual(f.replies, [{ id: 1, ok: true, path: savedUri, error: '', canceled: false }]);
  assert.deepEqual(f.events, ['load', 'prepare', 'poll', 'createPdf', 'picker', 'open', 'write', 'stat', 'fsync', 'close', 'reply', 'blank:about:blank']);
  assert.deepEqual(Array.from(f.pickerOptions[0].newFileNames), ['note.pdf']);
  assert.equal(f.timers.size, 0);
});

for (const uris of [[], ['']]) {
  test('picker cancellation ' + JSON.stringify(uris) + ' returns canceled without opening a file', async () => {
    const f = fixture({ uris }); await f.render(); failed(f, /canceled/, true);
    assert.equal(f.events.includes('open'), false);
  });
}
test('picker cancellation error code returns canceled without reporting success', async () => {
  const f = fixture({ pickerError: { code: 13900042, message: 'user canceled picker' } });
  await f.render(); failed(f, /user canceled/, true); assert.equal(f.events.includes('open'), false);
});
for (const [name, bytes] of [['empty', new Uint8Array()], ['short', new Uint8Array([37, 80, 68, 70, 45])],
  ['invalid signature', new Uint8Array(Buffer.from('NOT-PDF-DATA'))]]) {
  test('createPdf ' + name + ' buffer never opens picker or disk', async () => {
    const f = fixture({ bytes }); await f.render(); failed(f, /invalid or empty/);
    assert.equal(f.events.includes('picker'), false); assert.equal(f.events.includes('open'), false);
  });
}
for (const stage of ['createPdf', 'picker', 'open', 'write', 'stat', 'fsync', 'close']) {
  test(stage + ' failure never reports success', async () => {
    const f = fixture({ fail: stage }); await f.render(); failed(f, new RegExp(stage + ' failed'));
    if (['write', 'stat', 'fsync', 'close'].includes(stage)) assert.equal(f.events.filter(e => e === 'close').length, 1);
    if (stage === 'createPdf') assert.equal(f.events.includes('picker'), false);
  });
}
for (const issue of ['partial', 'mismatch']) {
  test(issue + ' write is closed but never fsynced or reported successful', async () => {
    const f = fixture({ [issue]: true }); await f.render(); failed(f, /incomplete/);
    assert.equal(f.events.includes('close'), true); assert.equal(f.events.includes('fsync'), false);
  });
}

test('page changes before poll: no PDF generation, picker, disk, or reply to replacement page', async () => {
  const f = fixture(); f.start(); await f.prepare(); f.navigate('https://vault.example/other'); await f.fire('interval');
  assert.equal(f.events.includes('createPdf'), false); assert.equal(f.events.includes('open'), false);
  assert.deepEqual(f.replies, []); assert.equal(f.timers.size, 0);
});
for (const stage of ['createPdf', 'picker']) {
  test('page changes during pending ' + stage + ': late result cannot write or reply', async () => {
    const pending = deferred();
    const f = fixture({ [stage === 'createPdf' ? 'createPromise' : 'pickerPromise']: pending.promise });
    await f.render(); assert.equal(f.events.includes(stage), true);
    f.navigate('https://vault.example/replaced');
    pending.resolve(stage === 'createPdf' ? { pdfArrayBuffer: () => pdf } : [savedUri]); await flush();
    assert.equal(f.events.includes('open'), false); assert.deepEqual(f.replies, []);
    await f.fire('timeout'); assert.equal(f.timers.size, 0);
  });
}
test('unavailable view while picker is pending cannot write', async () => {
  const pending = deferred(), f = fixture({ pickerPromise: pending.promise }); await f.render();
  f.setAvailable(false); pending.resolve([savedUri]); await flush();
  assert.equal(f.events.includes('open'), false); assert.equal(f.replies.some(r => r.ok), false);
  await f.fire('timeout');
});

test('concurrent export is rejected while original job completes once', async () => {
  const f = fixture(); f.start(); f.start(undefined, 2);
  assert.equal(f.loads.length, 1); assert.match(f.replies[0].error, /in progress/); assert.equal(f.replies[0].id, 2);
  await f.prepare(); await f.fire('interval');
  assert.equal(f.replies.filter(r => r.ok).length, 1); assert.equal(f.replies[1].id, 1);
});
test('repeated page-end and overlapping polls generate and save only once', async () => {
  const pending = deferred(), f = fixture({ pollPromise: pending.promise }); f.start();
  await f.prepare(); await f.prepare(); await f.fire('interval'); await f.fire('interval');
  assert.equal(f.events.filter(e => e === 'prepare').length, 1);
  assert.equal(f.events.filter(e => e === 'poll').length, 1);
  pending.resolve('ready'); await flush();
  assert.equal(f.events.filter(e => e === 'createPdf').length, 1);
  assert.equal(f.events.filter(e => e === 'write').length, 1); assert.equal(f.replies.length, 1);
});
test('waiting resource polls never save; deadline fails and clears all timers', async () => {
  const f = fixture({ ready: 'waiting' }); f.start();
  assert.equal([...f.timers.values()][0].delay, 120000);
  await f.prepare(); assert.equal([...f.timers.values()].find(t => t.kind === 'interval').delay, 150);
  await f.fire('interval'); assert.equal(f.events.includes('createPdf'), false);
  await f.fire('timeout'); failed(f, /timed out/);
});
for (const stage of ['createPdf', 'picker']) {
  test('timeout during pending ' + stage + ' rejects late completion and blocks a second save', async () => {
    const pending = deferred(), f = fixture({ [stage === 'createPdf' ? 'createPromise' : 'pickerPromise']: pending.promise });
    await f.render(); await f.fire('timeout'); failed(f, /timed out/);
    f.start(undefined, 2); assert.match(f.replies[1].error, /in progress/);
    pending.resolve(stage === 'createPdf' ? { pdfArrayBuffer: () => pdf } : [savedUri]); await flush();
    assert.equal(f.events.includes('open'), false); assert.equal(f.replies.some(r => r.ok), false);
    f.settings.createPromise = undefined; f.settings.pickerPromise = undefined;
    await f.render(); assert.equal(f.replies.at(-1).ok, true);
  });
}
for (const fail of ['prepare', 'poll']) {
  test(fail + ' JavaScript failure returns renderer error without disk writes', async () => {
    const f = fixture({ fail }); f.start(); await f.prepare();
    if (fail === 'poll') await f.fire('interval');
    failed(f, fail === 'prepare' ? /Cannot prepare/ : /unavailable/); assert.equal(f.events.includes('open'), false);
  });
}
test('resource error state fails without generating a PDF', async () => {
  const f = fixture({ ready: '"error:Image failed to load"' }); await f.render(); failed(f, /Image failed/);
  assert.equal(f.events.includes('createPdf'), false);
});

test('default A4 config and explicit landscape, scale, background and margins reach createPdf', async () => {
  const defaults = fixture(); await defaults.render();
  assert.deepEqual(defaults.configs[0], { width: 8.27, height: 11.69, marginTop: 0.4, marginBottom: 0.4,
    marginLeft: 0.4, marginRight: 0.4, shouldPrintBackground: true });
  const f = fixture(); await f.render({ pageSize: 'A4', landscape: true, scale: 1.25,
    printBackground: false, margins: { top: 0, bottom: 0.2, left: 0.3, right: 0.6 } });
  assert.deepEqual(f.configs[0], { width: 11.69, height: 8.27, marginTop: 0, marginBottom: 0.2,
    marginLeft: 0.3, marginRight: 0.6, shouldPrintBackground: false, scale: 1.25 });
});
test('custom micron size converts to inches and missing margins retain defaults', async () => {
  const f = fixture(); await f.render({ pageSize: { width: 254000, height: 508000 }, margins: { left: 0 } });
  assert.equal(f.configs[0].width, 10); assert.equal(f.configs[0].height, 20);
  assert.equal(f.configs[0].marginLeft, 0); assert.equal(f.configs[0].marginTop, 0.4);
});
for (const [label, options, error] of [
  ['unsupported size', { pageSize: 'unknown' }, /Unsupported PDF page size/],
  ['zero width', { pageSize: { width: 0, height: 25400 } }, /dimensions/],
  ['negative scale', { scale: -1 }, /scale/], ['zero scale', { scale: 0 }, /scale/],
  ['too large scale', { scale: 2.01 }, /scale/],
  ['negative margin', { margins: { left: -0.01 } }, /margins/],
  ['horizontal half-page margin', { margins: { right: 8.27 / 2 } }, /margins/],
  ['landscape vertical half-page margin', { landscape: true, margins: { top: 8.27 / 2 } }, /margins/]
]) {
  test('invalid config: ' + label + ' fails before rendering', () => {
    const f = fixture(); f.start(options); failed(f, error); assert.equal(f.loads.length, 0);
  });
}
