// Executes production ArkTS helpers/methods with only SDK I/O replaced in memory.
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
    .replace(/ as (?:Record<string, Object>|common\.UIAbilityContext|BusinessError|Uint8Array \| undefined|RemoteServerConfig|string)/g, '')
    .replace(/new Map<[^>]+>/g, 'new Map').replace(/new Set<[^>]+>/g, 'new Set')
    .replace(/AppStorage.get<string>/g, 'AppStorage.get')
    .replace(/: (?:Promise<[^>]+>|Map<[^>]+>|Set<[^>]+>|Array<[^>]+>|asset\.AssetMap|common\.UIAbilityContext|RemoteCredential \| undefined|RemoteCredential|RemoteServerConfig \| undefined|StartupPreference|string|boolean|number|void)(?=\s*[,;)=\{])/g, '');
}
function fixture(assetOverrides = {}) {
  const files = new Map(), storage = new Map(); let failRename = false;
  const io = { OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 }, accessSync: p => files.has(p),
    readTextSync: p => { if (!files.has(p)) throw Error('missing'); return files.get(p); },
    openSync: p => ({ fd: p }), writeSync: (p, s) => files.set(p, s), closeSync() {},
    renameSync: (a, b) => { if (failRename) throw Error('disk'); files.set(b, files.get(a)); files.delete(a); },
    unlinkSync: p => files.delete(p) };
  const asset = { Tag: { ALIAS: 'alias', SECRET: 'secret', RETURN_TYPE: 'return', ACCESSIBILITY: 'access', SYNC_TYPE: 'sync' },
    ReturnType: { ALL: 1 }, Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, SyncType: { THIS_DEVICE: 1 },
    query: async () => [], remove: async () => {}, update: async () => {}, add: async () => {}, ...assetOverrides };
  const sandbox = { fs: io, asset, util: { TextEncoder, TextDecoder: class { decodeToString(v) { return new TextDecoder().decode(v); } } },
    hilog: { warn() {}, error() {} }, AppStorage: { get: k => storage.get(k), setOrCreate: (k,v) => storage.set(k,v) } };
  vm.createContext(sandbox);
  for (const name of ['RemoteCredentialStore','RemoteServerSettings','StartupPreferences','CaptureModeSettings']) {
    vm.runInContext(js(source('common/' + name)) + ';globalThis.' + name + '=' + name, sandbox);
  }
  return { ...sandbox, files, storage, ctx: { filesDir: '/sandbox' }, fail: () => { failRename = true; } };
}
const rows = (user='old') => [new Map([['secret', new TextEncoder().encode(user + '\0password')]])];
test('unselected capture follows main mode; explicit choice survives restart and never changes main mode', () => {
  const f=fixture(); const modes=f.CaptureModeSettings;
  for (const mode of ['', 'local', 'ai', 'srv']) {
    const fresh=fixture(); fresh.storage.set('appMode',mode); assert.equal(fresh.CaptureModeSettings.isRemote(fresh.ctx),false);
  }
  f.storage.set('appMode','remote'); assert.equal(modes.isRemote(f.ctx),true);
  assert.equal(modes.save(f.ctx,false),true); assert.equal(modes.isRemote(f.ctx),false);
  assert.equal(f.storage.get('appMode'),'remote');
  const restarted=fixture(); for (const [k,v] of f.files) restarted.files.set(k,v);
  restarted.storage.set('appMode','remote'); assert.equal(restarted.CaptureModeSettings.isRemote(restarted.ctx),false);
  assert.equal(modes.save(f.ctx,true),true); f.storage.set('appMode','local'); assert.equal(modes.isRemote(f.ctx),true);
});
test('capture persistence failure reports failure without changing selection', () => {
  const f=fixture(); f.CaptureModeSettings.save(f.ctx,false); f.fail();
  assert.equal(f.CaptureModeSettings.save(f.ctx,true),false); assert.equal(f.CaptureModeSettings.isRemote(f.ctx),false);
});
test('clear removes related credentials and persists tombstone; pending/draft/notes untouched',async()=>{
  let removes=0; const f=fixture({remove:async()=>{removes++;}});
  assert.equal(f.RemoteServerSettings.save(f.ctx,'https://example.test'),true);
  for(const name of ['remote-capture.json','quick_note_draft.txt','notes.md']) f.files.set('/sandbox/'+name,'keep');
  f.RemoteCredentialStore.remember('https://example.test','u','p');
  assert.equal(await f.RemoteServerSettings.clear(f.ctx),true); assert.equal(removes,1);
  assert.equal(f.RemoteCredentialStore.memory('https://example.test'),undefined);
  f.storage.set('serverUrl','https://stale.test'); f.RemoteServerSettings.restore(f.ctx);
  assert.equal(f.storage.get('serverUrl'),'');
  for(const name of ['remote-capture.json','quick_note_draft.txt','notes.md']) assert.equal(f.files.get('/sandbox/'+name),'keep');
  const cold=fixture(); for(const [k,v] of f.files)cold.files.set(k,v); cold.storage.set('serverUrl','https://stale.test');
  cold.RemoteServerSettings.restore(cold.ctx); assert.equal(cold.storage.get('serverUrl'),'');
});
test('asset errors and disk failures do not claim clear success; NOT_FOUND is success',async()=>{
  const f=fixture({remove:async()=>{throw {code:24000003};}}); f.RemoteServerSettings.save(f.ctx,'https://example.test');
  assert.equal(await f.RemoteServerSettings.clear(f.ctx),false); assert.equal(f.RemoteServerSettings.load(f.ctx).server,'https://example.test');
  const g=fixture({remove:async()=>{throw {code:24000002};}});g.RemoteServerSettings.save(g.ctx,'https://example.test');
  assert.equal(await g.RemoteServerSettings.clear(g.ctx),true);
  const h=fixture();h.RemoteServerSettings.save(h.ctx,'https://example.test');h.fail();
  assert.equal(await h.RemoteServerSettings.clear(h.ctx),false);
});
test('failed credential deletion allows fresh loading without reviving pre-clear cache',async()=>{
  let queries=0;const f=fixture({remove:async()=>{throw {code:24000003}},query:async()=>{queries++;return rows('stored');}});
  f.RemoteCredentialStore.remember('https://example.test','cached','old');
  assert.equal(await f.RemoteCredentialStore.forget('https://example.test'),false);
  assert.equal(f.RemoteCredentialStore.memory('https://example.test'),undefined);
  assert.equal((await f.RemoteCredentialStore.load('https://example.test')).user,'stored');
  assert.equal(queries,1);
});
test('failed older deletion cannot unblock a newer successful deletion',async()=>{
  let release;let removes=0;const f=fixture({remove:()=>++removes===1?new Promise((_,reject)=>{release=reject}):Promise.resolve(),query:async()=>rows()});
  const first=f.RemoteCredentialStore.forget('https://example.test');await Promise.resolve();
  const second=f.RemoteCredentialStore.forget('https://example.test');release({code:24000003});
  assert.equal(await first,false);assert.equal(await second,true);
  assert.equal(await f.RemoteCredentialStore.load('https://example.test'),undefined);
});
test('late credential load cannot refill cache or return stale secret after clear or remember',async()=>{
  let release;const f=fixture({query:()=>new Promise(r=>release=r)});const c=f.RemoteCredentialStore;
  const loading=c.load('https://example.test');await c.forget('https://example.test');release(rows());
  assert.equal(await loading,undefined);assert.equal(c.memory('https://example.test'),undefined);
  let finish; const g=fixture({query:()=>new Promise(r=>finish=r)});const pending=g.RemoteCredentialStore.load('https://example.test');
  g.RemoteCredentialStore.remember('https://example.test','new','newpwd');finish(rows());
  assert.equal(await pending,undefined);assert.equal(g.RemoteCredentialStore.memory('https://example.test').user,'new');
});
test('queued save followed by clear leaves no credential resurrection',async()=>{
  let release;const calls=[]; const f=fixture({update:()=>{calls.push('save');return new Promise(r=>release=r)},remove:async()=>calls.push('clear')});
  const save=f.RemoteCredentialStore.save('https://example.test','u','p'); await Promise.resolve();
  const clear=f.RemoteCredentialStore.forget('https://example.test');release();await save;await clear;
  assert.deepEqual(calls,['save','clear']);assert.equal(f.RemoteCredentialStore.memory('https://example.test'),undefined);
});
function pageFixture(load) {
  const raw=source('pages/IgnisSettingsPage');
  const methods=raw.slice(raw.indexOf('  private openRemoteEntry()'),raw.indexOf('  private confirmClearRemote()'));
  const sandbox={RemoteCredentialStore:{load},AppStorage:{get:()=> 'https://example.test'}};vm.createContext(sandbox);
  vm.runInContext('class Page {'+js(methods)+'};globalThis.page=new Page()',sandbox);
  Object.assign(sandbox.page,{remoteServer:'https://example.test',remoteLoadEpoch:0,remoteEditEpoch:0,pageAlive:true,remoteExpanded:true,remoteUser:'',remotePwd:''});
  return sandbox.page;
}
test('real settings load method does not overwrite user edits or hidden/collapsed UI',async()=>{
  for(const action of ['edit','hide','collapse','server']) {
    let release;const p=pageFixture(()=>new Promise(r=>release=r));const pending=p.loadRemoteCredential();
    if(action==='edit'){p.remoteUser='typed';p.remotePwd='typed';p.remoteEdited();}
    if(action==='hide')p.pageAlive=false;if(action==='collapse')p.remoteExpanded=false;if(action==='server')p.remoteServer='';
    release({user:'old',pwd:'old'});await pending;assert.notEqual(p.remoteUser,'old');assert.notEqual(p.remotePwd,'old');
  }
});
test('real settings load still restores untouched inputs',async()=>{
  const p=pageFixture(async()=>({user:'saved',pwd:'secret'}));await p.loadRemoteCredential();
  assert.equal(p.remoteUser,'saved');assert.equal(p.remotePwd,'secret');assert.equal(p.credentialLoading,false);
});
test('reopening remote form reloads the complete credential pair for its saved server',async()=>{
  for (const stale of [{remoteUser:'saved',remotePwd:''},{remoteUser:'other-server',remotePwd:'other-secret'}]) {
    let release; const p=pageFixture(()=>new Promise(r=>release=r));
    Object.assign(p,stale,{remoteExpanded:false,remoteServer:'https://other.test'});
    p.openRemoteEntry();
    assert.equal(p.remoteServer,'https://example.test');
    assert.equal(p.remoteUser,'');assert.equal(p.remotePwd,'');assert.equal(p.credentialLoading,true);
    release({user:'saved',pwd:'secret'});await new Promise(resolve=>setImmediate(resolve));
    assert.equal(p.remoteUser,'saved');assert.equal(p.remotePwd,'secret');
  }
});
test('hide/show resumes interrupted credential load, but never overwrites an edited draft',async()=>{
  const raw=source('pages/IgnisSettingsPage');
  const methods=raw.slice(raw.indexOf('  onPageHide()'),raw.indexOf('  private openRemoteEntry()'));
  const lifecycle={};vm.createContext(lifecycle);
  vm.runInContext('class Page {'+js(methods)+'};globalThis.Page=Page',lifecycle);
  for(const edited of [false,true]) {
    const releases=[];const p=pageFixture(()=>new Promise(r=>releases.push(r)));
    p.onPageHide=lifecycle.Page.prototype.onPageHide;p.onPageShow=lifecycle.Page.prototype.onPageShow;
    Object.assign(p,{refreshPreviewVault(){},refreshRemoteLabel(){}});
    // The real show method reads membership; supply its SDK-free collaborator.
    lifecycle.VipService={isVip:()=>false};
    const first=p.loadRemoteCredential();if(edited){p.remoteUser='typed';p.remoteEdited();}
    p.onPageHide();p.onPageShow();releases[0]({user:'old',pwd:'old'});await first;
    if(edited){assert.equal(releases.length,1);assert.equal(p.remoteUser,'typed');}
    else {assert.equal(releases.length,2);assert.equal(p.credentialLoading,true);
      releases[1]({user:'stored',pwd:'secret'});await Promise.resolve();await Promise.resolve();
      assert.equal(p.remoteUser,'stored');assert.equal(p.remotePwd,'secret');assert.equal(p.credentialLoading,false);}
  }
});
test('entry defaults, capture wiring, confirmation and runtime About version are present',()=>{
  for(const name of ['pages/Splash','entryability/ShareAbility','entryability/EntryAbility']) {
    const s=source(name);assert.match(s,/persistProp\('appMode', ''\)/);assert.doesNotMatch(s,/persistProp\('appMode', 'remote'\)/);
  }
  for(const name of ['pages/QuickNote','pages/ShareCapture']) {
    const s=source(name);assert.match(s,/CaptureModeSettings.isRemote/);assert.match(s,/CaptureModeSettings.save/);
    assert.doesNotMatch(s,/AppStorage\.(?:set|setOrCreate)\('appMode'/);
  }
  const settings=source('pages/IgnisSettingsPage');assert.match(settings,/result.index === 1/);assert.match(settings,/!this.remoteSaving && !this.credentialLoading/);
  assert.match(source('pages/About'),/bundleManager.getBundleInfoForSelfSync/);assert.match(source('pages/About'),/info.versionName/);
});
