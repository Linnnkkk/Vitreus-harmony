const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const root = path.join(__dirname, '../entry/src/main/ets');
function fixture(options = {}) {
  const state = new Map(); const calls = []; let record;
  let config = { enabled: true, vaultName: 'PARA', credentialId: 'abc123', url: 'https://dav.example/dav/PARA' };
  let member = true;
  const sandbox = {
    AppStorage: { get: k => state.get(k) },
    RemoteServerSettings: { restore() {} },
    WebDavSettings: { load: () => config, connectionKey: c => JSON.stringify(c) },
    WebDavCredentialStore: { load: async () => { calls.push('credential'); if(options.onCredential) options.onCredential(); return {user:'fixture',pwd:'secret'}; } },
    RemoteCredentialStore: { load: async () => undefined },
    VipService: { isVip: () => member }, CapturePathSettings: { load: () => ({}) },
    RemoteCapture: { normalizeServer: x => { if(!x) throw Error('missing'); return x; }, load: () => record, persist: (_,op) => { record=op; }, archive() {} },
    createNativeRemoteRequester: () => async () => ({}),
    createWebDavCaptureRequester: (c,u,p,id) => { calls.push(['dav',c.url,id]); return async () => ({status:200,body:'ok'}); },
    RemoteCaptureEngine: class {
      constructor(_,request) {this.request=request;}
      async listVaults() { await this.request('GET','/api/vault/list',''); return [{id:'webdav:abc123',name:'PARA'}]; }
      async prepare(op,target) { op.vault=target.id; op.stage='prepared'; }
      async save(op) { await this.request('POST','/api/fs/writeFile','{}'); op.stage='done'; calls.push('save'); }
      async undo() { calls.push('undo'); }
    },
  };
  const raw = fs.readFileSync(path.join(root,'common/RemoteCaptureService.ets'),'utf8').replace(/^import .*;\n/gm,'').replace('export class','class');
  vm.createContext(sandbox); vm.runInContext(stripTypeScriptTypes(raw)+';globalThis.service=RemoteCaptureService;',sandbox);
  return { service:sandbox.service, calls,state, setConfig:c=>{config=c;}, config:()=>config, setMember:v=>{member=v;}, record:()=>record };
}
test('cold share/quick capture can list enabled WebDAV without an Ignis URL or Node process',async()=>{
  const f=fixture(); const list=await f.service.list({});
  assert.equal(list.length,1); assert.equal(list[0].id,'webdav:abc123'); assert.match(list[0].name,/WebDAV/);
  assert.equal(f.calls.length,0, 'selection does not expose/load the credential');
});
test('share and quick saves use WebDAV identity and never select a same-name local vault',async()=>{
  for(const kind of ['quick','share']) { const f=fixture(); const op=await f.service.capture({},'fixture content',false,true,kind,{id:'webdav:abc123',name:'PARA'});
    assert.equal(op.stage,'done'); assert.equal(op.vault,'webdav:abc123'); assert.equal(op.serverURL,'https://webdav-abc123.capture.invalid');
    assert.deepEqual(f.calls.filter(Array.isArray),[['dav','https://dav.example/dav/PARA','webdav:abc123']]);
    assert.equal(JSON.stringify(op).includes('secret'),false);
  }
});
test('expired membership or disabled configuration blocks WebDAV capture',async()=>{
  const expired=fixture(); expired.setMember(false); await assert.rejects(expired.service.list({}),/会员/);
  await assert.rejects(expired.service.capture({},'x',false,true,'quick',{id:'webdav:abc123',name:'PARA'}),/会员/);
  const disabled=fixture(); disabled.setConfig({...disabled.config(),enabled:false});
  await assert.rejects(disabled.service.capture({},'x',false,true,'share',{id:'webdav:abc123',name:'PARA'}),/停用/);
});
test('configuration changed while loading credentials prevents any WebDAV request',async()=>{
  let f; f=fixture({onCredential:()=>f.setConfig({...f.config(),url:'https://changed.example/dav'})});
  await assert.rejects(f.service.capture({},'x',false,true,'quick',{id:'webdav:abc123',name:'PARA'}),/变更/);
  assert.equal(f.calls.some(Array.isArray),false);
});
test('changed WebDAV URL cannot redirect undo to another server with the same credential alias',async()=>{
  const f=fixture();const op=await f.service.capture({},'x',false,true,'quick',{id:'webdav:abc123',name:'PARA'});
  f.setConfig({...f.config(),url:'https://other.example/dav/PARA'});
  await assert.rejects(f.service.undo({},op),/变更/);assert.equal(f.calls.includes('undo'),false);
});
test('both UI loaders call shared target listing without requiring Ignis server first',()=>{
  for(const [name,start,end] of [['QuickNote','  private async loadRemoteVaults','  private remoteName'],['ShareCapture','  private async loadTargets','  private async saveSelected']]) {
    const src=fs.readFileSync(path.join(root,'pages/'+name+'.ets'),'utf8'); const body=src.slice(src.indexOf(start),src.indexOf(end));
    assert.match(body,/RemoteCaptureService.list/); assert.doesNotMatch(body,/RemoteCaptureService.server\(\) === ''/);
  }
});
