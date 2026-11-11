// Run the real QuickCapture vault-root logic against a temp directory with platform APIs mocked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/common/QuickCapture.ets'), 'utf8')
  .replace(/^import .*$/mg, '').replace(/^export /mg, '');
const js = stripTypeScriptTypes(source);

function setup({ configUri = '', activated = true } = {}) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'qc-root-'));
  const sandbox = path.join(base, 'sandbox'); fs.mkdirSync(path.join(sandbox, 'vaults'), { recursive: true });
  const oldRoot = path.join(base, 'Download'); fs.mkdirSync(path.join(oldRoot, 'Old', '.obsidian'), { recursive: true });
  const custom = path.join(base, '测试'); fs.mkdirSync(path.join(custom, 'Notes', '.obsidian'), { recursive: true });
  fs.mkdirSync(path.join(custom, '.ignis-remote-vaults'));
  const uri = configUri === 'custom' ? 'file://docs' + custom : configUri;
  const state = { vaultRootPath: oldRoot, activeVaultPath: path.join(oldRoot, 'Old'), activeVault: 'Old' };
  let activations = 0;
  const ctx = {
    console, JSON, Date, Math, Object, Array, String, Number, Error, Promise,
    AppStorage: { get: k => state[k], setOrCreate: (k, v) => { state[k] = v; } },
    hilog: { info() {}, error() {}, warn() {} },
    fs: {
      accessSync: p => (activated || !p.startsWith(custom)) && fs.existsSync(p),
      listFileSync: p => fs.readdirSync(p),
      statSync: p => fs.statSync(p),
      readTextSync: p => fs.readFileSync(p, 'utf8'),
      mkdirSync: p => fs.mkdirSync(p)
    },
    fileUri: { FileUri: class { constructor(u) { this.path = u.replace(/^file:\/\/docs/, ''); } } },
    VaultRootSettings: {
      load: () => ({ version: 1, uri }),
      activate: async u => { activations++; activated = true; return u.replace(/^file:\/\/docs/, ''); }
    },
    VipService: { isVip: () => false }, CapturePathSettings: {}, CapturePathTemplate: {}, picker: {}
  };
  vm.createContext(ctx);
  vm.runInContext(js + '\nglobalThis.QC = QuickCapture;', ctx);
  return { QC: ctx.QC, state, custom, oldRoot, context: { filesDir: sandbox }, activations: () => activations };
}

test('default root keeps existing behaviour', () => {
  const t = setup();
  assert.equal(t.QC.resolveVault(t.context), path.join(t.oldRoot, 'Old'));
});

test('custom root already active in this process is listed synchronously', () => {
  const t = setup({ configUri: 'custom' });
  const names = Array.from(t.QC.listVaults(t.context), v => v.name);
  assert.deepEqual(names, ['Notes']);
});

test('stale remembered vault from the old root falls back to a vault inside the custom root', () => {
  const t = setup({ configUri: 'custom' });
  assert.equal(t.QC.resolveVault(t.context), path.join(t.custom, 'Notes'));
});

test('cold process: nothing listed before activation, prepareRoot activates then lists', async () => {
  const t = setup({ configUri: 'custom', activated: false });
  assert.equal(t.QC.listVaults(t.context).length, 0);
  assert.equal(await t.QC.prepareRoot(t.context), true);
  assert.equal(t.activations(), 1);
  assert.equal(await t.QC.resolveVaultAsync(t.context), path.join(t.custom, 'Notes'));
  assert.equal(t.activations(), 1);
  assert.equal(t.QC.currentRoot(t.context), t.custom);
});

test('custom root never falls back to the old root or sandbox when unavailable', () => {
  const t = setup({ configUri: 'custom', activated: false });
  assert.equal(t.QC.resolveVault(t.context), '');
  assert.equal(t.QC.currentRoot(t.context), '');
});

test('root changed after Node started is rejected', async () => {
  const t = setup({ configUri: 'custom' });
  t.state.nodeVaultConfigUri = '';
  await assert.rejects(t.QC.prepareRoot(t.context), /笔记库位置已更改/);
});
