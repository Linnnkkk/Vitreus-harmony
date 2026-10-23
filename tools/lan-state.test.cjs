const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '../entry/src/main/ets/pages');
const lan = fs.readFileSync(path.join(root, 'LanServerPage.ets'), 'utf8');
const local = fs.readFileSync(path.join(root, 'LocalWeb.ets'), 'utf8');
// Execute the actual ArkTS method bodies, erasing only their type annotations.
function method(source, name) {
  const match = source.match(new RegExp('^  (?:private )?(?:async )?' + name + '\\([^\\n]*', 'm'));
  assert.ok(match, name);
  const start = match.index;
  const end = source.indexOf('\n  }', start) + 4;
  return source.slice(start, end).replace(/\bprivate /g, '')
    .replace(/: (?:Promise<void>|LanShareStatus \| null|AiLanStatus \| null|common\.UIAbilityContext|boolean|string|number|void)/g, '')
    .replace(/ as common\.UIAbilityContext/g, '').replace(/AppStorage\.get<\w+>/g, 'AppStorage.get');
}
function deferred() { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return {promise,resolve,reject}; }
const tick = () => new Promise(resolve => setImmediate(resolve));
function harness(source, names) {
  const state = { lanShareUser: 'u', lanSharePass: 'pass', lanSharePort: 1234, srvModeEnabled: false };
  const calls = []; let vip = true;
  const api = { status: async()=>null, enable: async()=>({running:true,port:1234}), disable:async()=>({running:false}), tlsPreferred:()=>false, fullAddr:()=> 'http://lan:1234' };
  const context = {AppStorage:{get:k=>state[k],setOrCreate:(k,v)=>{state[k]=v;}},LanShareApi:api,AiLanApi:{status:async()=>null},VipService:{isVip:()=>vip},BackgroundLease:{reconcile:ctx=>calls.push(['lease',ctx])},router:{pushUrl:()=>calls.push(['route'])},hapticLight:()=>{},hapticSuccess:()=>{},JSON};
  vm.createContext(context);
  vm.runInContext('class Page {' + names.map(n=>method(source,n)).join('\n') + '} globalThis.Page = Page;',context);
  const page = new context.Page();
  Object.assign(page,{pageAlive:true,pageEpoch:0,statusSeq:0,operationRevision:0,operationBusy:false,busy:false,running:false,lanIp:'192.168.1.1',port:0,fingerprint:'',runTls:false,showCredForm:true,localVisible:true,srvBusy:false,srvEpoch:0,srvStatusSeq:0,aiEpoch:0,aiBusy:false,pendingCredUser:'new',pendingCredPass:'pass'});
  const host = {marker:'captured'};
  page.getUIContext = ()=>({getHostContext:()=>host,getPromptAction:()=>({showToast:()=>calls.push(['toast'])})});
  page.safeRun = js=>calls.push(['js',js]);page.pushAiState=()=>{};
  return {page,api,state,calls,host,setVip:v=>vip=v};
}
const lanMethods=['refreshStatus','doEnable','doDisable'];
const localMethods=['srvCurrent','srvAction','confirmSrvCred','pushSrvState'];
test('LAN newest refresh wins even when earlier request resolves last',async()=>{
 const h=harness(lan,lanMethods),a=deferred(),b=deferred();let n=0;h.api.status=()=>++n===1?a.promise:b.promise;
 h.page.refreshStatus();h.page.refreshStatus();b.resolve({running:true,port:9});await tick();a.resolve({running:false,port:0});await tick();
 assert.equal(h.page.running,true);assert.equal(h.state.srvRunning,true);assert.equal(h.page.port,9);
});
test('LAN status arriving after hide cannot mutate runtime or UI',async()=>{
 const h=harness(lan,lanMethods),a=deferred();h.api.status=()=>a.promise;h.page.refreshStatus();h.page.pageAlive=false;h.page.pageEpoch++;a.resolve({running:true,port:9});await tick();assert.equal(h.page.running,false);assert.equal(h.state.srvRunning,undefined);
});
test('LAN refresh cannot overwrite completed user operation',async()=>{
 const h=harness(lan,lanMethods),a=deferred();h.api.status=()=>a.promise;h.page.refreshStatus();await h.page.doEnable('u','pass');a.resolve({running:false,port:0});await tick();assert.equal(h.page.running,true);assert.equal(h.state.srvRunning,true);
});
for (const name of ['doEnable','doDisable']) test(`LAN ${name} after leaving updates outcome/lease but not UI`,async()=>{
 const h=harness(lan,lanMethods),a=deferred();h.api[name==='doEnable'?'enable':'disable']=()=>a.promise;
 const work=h.page[name]('u','pass');h.page.pageAlive=false;h.page.pageEpoch++;h.page.getUIContext=()=>{throw Error('old context');};const before={running:h.page.running,busy:h.page.busy,port:h.page.port};
 a.resolve({running:name==='doEnable',port:99});await work;
 assert.deepEqual({running:h.page.running,busy:h.page.busy,port:h.page.port},before);assert.equal(h.state.srvRunning,name==='doEnable');assert.equal(h.state.srvModeEnabled,name==='doEnable');assert.equal(h.calls.filter(c=>c[0]==='lease').length,1);assert.equal(h.calls.find(c=>c[0]==='lease')[1],h.host);
});
test('LAN failed disable does not change saved enable intent',async()=>{
 const h=harness(lan,lanMethods);h.state.srvModeEnabled=true;h.api.disable=async()=>({running:true});await h.page.doDisable();assert.equal(h.state.srvModeEnabled,true);
});
test('LAN TLS restart does not promote temporary runtime into saved enable intent',async()=>{
 const h=harness(lan,lanMethods);await h.page.doEnable('u','pass',false);assert.equal(h.state.srvModeEnabled,false);assert.equal(h.state.srvRunning,true);
});
test('LAN rejected operation releases lock',async()=>{
 const h=harness(lan,lanMethods);h.api.enable=async()=>{throw Error('network');};await h.page.doEnable('u','pass');assert.equal(h.page.busy,false);assert.equal(h.page.operationBusy,false);
});
test('LocalWeb non-VIP credential save cannot create global purchase-enable intent',async()=>{
 const h=harness(local,localMethods);h.setVip(false);let enables=0;h.api.enable=async()=>{enables++;};await h.page.srvAction('credentials');assert.equal(h.state.lanShareUser,'new');assert.equal(h.state.vipPendingEnable,undefined);assert.equal(enables,0);assert.equal(h.page.srvBusy,false);assert.equal(h.state.srvModeEnabled,false);
});
test('LocalWeb unknown toggle status does not enable',async()=>{
 const h=harness(local,localMethods);let enables=0;h.api.enable=async()=>{enables++;};await h.page.srvAction('toggle');assert.equal(enables,0);assert.equal(h.page.srvBusy,false);
});
test('LocalWeb double click and credentials/TLS share one lock',async()=>{
 const h=harness(local,localMethods),a=deferred();let statuses=0,enables=0;h.api.status=()=>{statuses++;return a.promise;};h.api.enable=async()=>{enables++;return {running:true,port:9};};const work=h.page.srvAction('toggle');await h.page.srvAction('toggle');await h.page.srvAction('credentials');await h.page.srvAction('tls');assert.equal(statuses,1);a.resolve({running:false});await work;assert.equal(enables,1);assert.equal(h.page.srvBusy,false);assert.equal(h.state.srvModeEnabled,false);
});
test('LocalWeb leaving before status resolves prevents issuing mutation',async()=>{
 const h=harness(local,localMethods),a=deferred();let enables=0;h.api.status=()=>a.promise;h.api.enable=async()=>{enables++;};const work=h.page.srvAction('toggle');h.page.localVisible=false;h.page.srvEpoch++;a.resolve({running:false});await work;assert.equal(enables,0);assert.equal(h.page.srvBusy,false);
});
test('LocalWeb issued result after leaving updates runtime and captured lease only',async()=>{
 const h=harness(local,localMethods),a=deferred();h.api.enable=()=>a.promise;let pushes=0;h.page.pushSrvState=()=>pushes++;const work=h.page.srvAction('credentials');h.page.pageAlive=false;h.page.srvEpoch++;h.page.getUIContext=()=>{throw Error('old page');};a.resolve({running:true,port:90});await work;assert.equal(h.state.srvRunning,true);assert.equal(h.state.srvModeEnabled,false);assert.equal(pushes,0);assert.equal(h.calls.find(c=>c[0]==='lease')[1],h.host);
});
test('LocalWeb old status response cannot overwrite action outcome',async()=>{
 const h=harness(local,localMethods),a=deferred();h.api.status=()=>a.promise;h.page.pushSrvState();h.page.pushSrvState=()=>{};await h.page.srvAction('credentials');a.resolve({running:false});await tick();assert.equal(h.state.srvRunning,true);assert.equal(h.calls.filter(c=>c[0]==='js').length,0);
});
test('LocalWeb rejection releases shared lock',async()=>{
 const h=harness(local,localMethods);h.api.status=async()=>{throw Error('network');};await h.page.srvAction('toggle');assert.equal(h.page.srvBusy,false);
});
