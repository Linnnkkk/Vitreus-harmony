const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const path = require('node:path');
const src = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/common/VaultRootSettings.ets'), 'utf8');
function setup() {
  const files = new Map(); let fail = '';
  const io = { OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    accessSync: p => files.has(p),
    readTextSync(p) { if (!files.has(p)) throw Error('missing'); return files.get(p); },
    openSync(p) { if (fail === 'open') throw Error('open'); return {fd:p}; },
    writeSync(p, v) { if (fail === 'write') throw Error('write'); files.set(p,v); },
    closeSync() {},
    renameSync(a,b) { if (fail === 'rename') throw Error('rename'); files.set(b,files.get(a)); files.delete(a); },
    unlinkSync(p) { if (fail === 'unlink') throw Error('unlink'); files.delete(p); },
    statSync: () => ({isDirectory: () => true}), listFileSync: () => [] };
  const shares = { OperationMode: { READ_MODE:1, WRITE_MODE:2 }, activatePermission: async () => {} };
  let code = stripTypeScriptTypes(src.replace(/^import .*;\n/gm,''), {mode:'strip'}).replace(/export /g,'');
  const env = {fs:io, fileShare:shares, fileUri:{FileUri:class { constructor(uri){this.path=uri;} }}};
  vm.createContext(env); vm.runInContext(code+'\nthis.Settings = VaultRootSettings;',env);
  return { settings:env.Settings, files, ctx:{filesDir:'/app'}, fail: v => fail=v, shares };
}
test('default selection persists and survives process reconstruction', () => {
  const f=setup(); assert.equal(f.settings.load(f.ctx).uri,'');
  f.settings.save(f.ctx,{version:1,uri:'/chosen'});
  assert.equal(f.settings.load(f.ctx).uri,'/chosen');
  f.settings.save(f.ctx,{version:1,uri:''}); assert.equal(f.settings.load(f.ctx).uri,'');
});
test('write and rename failures preserve the previous selection', () => {
  for (const reason of ['open','write','rename']) {
    const f=setup(); f.settings.save(f.ctx,{version:1,uri:'/old'}); f.fail(reason);
    assert.throws(()=>f.settings.save(f.ctx,{version:1,uri:'/new'}));
    assert.equal(f.settings.load(f.ctx).uri,'/old');
  }
});
test('corrupt configuration fails closed rather than resetting', () => {
  for (const broken of ['{"version":1,"uri":42}', 'null', '{broken']) {
    const f=setup(); f.files.set('/app/vault-root-config.json',broken);
    assert.throws(()=>f.settings.load(f.ctx));
    assert.equal(f.files.get('/app/vault-root-config.json'),broken);
  }
});
test('activation rejects errors and checks directory after activating permission', async () => {
  const f=setup(); let called=false; f.shares.activatePermission=async p=>{called=true; assert.equal(p[0].operationMode,3);};
  assert.equal(await f.settings.activate('/chosen'),'/chosen'); assert.equal(called,true);
  f.shares.activatePermission=async()=>{throw Error('revoked');};
  await assert.rejects(f.settings.activate('/chosen'),/revoked/);
});
test('default does not activate; revoked configured directory never falls back', async () => {
  const f=setup(); let calls=0; f.shares.activatePermission=async()=>{calls++; throw Error('revoked');};
  assert.equal(await f.settings.resolveConfigured(f.ctx),''); assert.equal(calls,0);
  f.settings.save(f.ctx,{version:1,uri:'/chosen'});
  await assert.rejects(f.settings.resolveConfigured(f.ctx),/revoked/);
  assert.equal(f.settings.load(f.ctx).uri,'/chosen');
});

test('AI grants are cleared only when the vault root actually changes', () => {
  const f = setup(); const grants = '/app/ignis-data/ai-lan/access.json'; const record = '/app/ai-access-root.json';
  f.files.set(grants, '{"vaultIds":["Notes"],"allowWrite":true}');
  // Upgrade on the default root keeps existing grants and starts tracking.
  assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', ''), false);
  assert.ok(f.files.has(grants)); assert.equal(JSON.parse(f.files.get(record)).uri, '');
  // Same root again: untouched.
  assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', ''), false); assert.ok(f.files.has(grants));
  // Switching to a custom folder clears grants.
  assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', 'file://docs/x'), true);
  assert.ok(!f.files.has(grants)); assert.equal(JSON.parse(f.files.get(record)).uri, 'file://docs/x');
  // New grants on the custom root survive restarts; switching back clears them again.
  f.files.set(grants, '{}');
  assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', 'file://docs/x'), false); assert.ok(f.files.has(grants));
  assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', ''), true); assert.ok(!f.files.has(grants));
});

test('custom root without a record (switched before tracking existed) or corrupt record clears grants', () => {
  for (const preset of [undefined, '{broken']) {
    const f = setup(); const grants = '/app/ignis-data/ai-lan/access.json';
    f.files.set(grants, '{}');
    if (preset !== undefined) f.files.set('/app/ai-access-root.json', preset);
    assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', preset === undefined ? 'file://docs/x' : ''), true);
    assert.ok(!f.files.has(grants));
  }
});

test('failure to clear grants aborts startup instead of keeping stale grants', () => {
  const f = setup(); f.files.set('/app/ignis-data/ai-lan/access.json', '{}');
  f.settings.resetAiGrantsIfRootChanged('/app', '');
  f.fail('unlink');
  assert.throws(() => f.settings.resetAiGrantsIfRootChanged('/app', 'file://docs/x'));
  // Record not advanced, so the next start retries the clear.
  assert.equal(JSON.parse(f.files.get('/app/ai-access-root.json')).uri, '');
  f.fail(''); assert.equal(f.settings.resetAiGrantsIfRootChanged('/app', 'file://docs/x'), true);
  assert.ok(!f.files.has('/app/ignis-data/ai-lan/access.json'));
});
