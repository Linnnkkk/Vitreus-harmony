const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');const {stripTypeScriptTypes}=require('node:module');
const root=path.join(__dirname,'../entry/src/main/ets');
const raw=fs.readFileSync(path.join(root,'components/ServiceVaultPicker.ets'),'utf8');
function fixture(options={}){
 let saves=[];const data={availableVaults:[{id:'Local',remote:false},{id:'PARA',remote:true}],activeVault:'PARA',srvDefaultVault:'',aiDefaultVault:'',srvResolvedVault:'PARA',aiResolvedVault:'PARA'};
 let ids=['PARA'];
 const context={Curve:{EaseInOut:0},ServiceVaultApi:{status:async()=>data,set:async(kind,vault)=>{saves.push({kind,vault});return {...data,[kind+'DefaultVault']:vault};}},AiLanApi:{status:async()=>({access:{vaultIds:ids}}),hasAccessPolicy:()=>true},...options};
 let source=raw.slice(0,raw.indexOf('  @Builder')).replace(/^import .*;\n/gm,'').replace(/@Component\n/,'').replace('export struct ServiceVaultPicker','class ServiceVaultPicker').replace(/@(Prop|State)(?: @Watch\('[^']+'\))? /g,'');
 vm.createContext(context);vm.runInContext(stripTypeScriptTypes(source+'}\nglobalThis.p=new ServiceVaultPicker();'),context);const p=context.p;p.getUIContext=()=>({animateTo:(_,fn)=>fn()});p.alive=true;p.visible=true;
 return{p,saves,setIds:v=>ids=v};
}
test('server picker includes local and WebDAV targets with shared default state',async()=>{const f=fixture();await f.p.load();assert.equal(f.p.vaults.length,2);await f.p.save('PARA');assert.deepEqual(f.saves,[{kind:'srv',vault:'PARA'}]);assert.equal(f.p.status.srvDefaultVault,'PARA');});
test('AI default picker never expands existing authorization',async()=>{const f=fixture();f.p.kind='ai';await f.p.load();assert.deepEqual(Array.from(f.p.vaults,x=>x.id),['PARA']);await f.p.save('Local');assert.equal(f.saves.length,0);await f.p.save('PARA');assert.equal(f.saves.length,1);});
test('revocation between load and save blocks previously listed AI target',async()=>{const f=fixture();f.p.kind='ai';await f.p.load();f.setIds([]);await f.p.save('PARA');assert.equal(f.saves.length,0);});
test('hidden picker ignores a late list and reloads on return',async()=>{let release;const f=fixture({ServiceVaultApi:{status:()=>new Promise(r=>release=r)}});const request=f.p.load();f.p.visible=false;f.p.onVisibilityChanged();release({availableVaults:[]});await request;assert.equal(f.p.status,null);assert.equal(f.p.requestBusy,false);});
function panelFixture(data,authorized=[]){
 const source=fs.readFileSync(path.join(root,'pages/LocalWeb.ets'),'utf8');
 const code=source.slice(source.indexOf('function vaultPicker('),source.indexOf('function renderAi'));
 const sent=[];
 const element=()=>({style:{},children:[],options:[],appendChild(child){this.children.push(child);this.options.push(child);},setAttribute(){}});
 const context={window:{__vtVaultState:{data,authorized}},document:{createElement:element},h:text=>({textContent:text}),send:act=>sent.push(act)};
 vm.createContext(context);vm.runInContext(code,context);
 return {render:kind=>context.vaultPicker(kind),sent};
}
test('floating selector keeps an unavailable configured default visible without granting AI access',()=>{
 const f=panelFixture({availableVaults:[{id:'Local',remote:false},{id:'PARA',remote:true}],activeVault:'Local',srvDefaultVault:'Missing',aiDefaultVault:'Local',srvResolvedVault:'Local',aiResolvedVault:'PARA'},['PARA']);
 const server=f.render('srv').children[1];assert.equal(server.value,'Missing');assert.equal(server.options.at(-1).disabled,true);assert.match(server.options.at(-1).textContent,/不可用/);
 const ai=f.render('ai').children[1];assert.equal(ai.options.find(o=>o.value==='Local').disabled,true);assert.equal(ai.options.find(o=>o.value==='PARA').disabled,undefined);
 ai.value='PARA';ai.onchange();assert.deepEqual(f.sent,['vault-set?kind=ai&id=PARA']);
});
test('floating selector shows failed reads and offers retry instead of endless loading',()=>{
 const f=panelFixture(null);const box=f.render('srv');assert.equal(box.children[1].textContent,'笔记库读取失败');
 const retry=box.children[2];retry.onclick();assert.deepEqual(f.sent,['vault-refresh']);assert.equal(retry.disabled,true);
});
test('floating selector follows active vault and preserves encoded WebDAV IDs',()=>{
 const f=panelFixture({availableVaults:[{id:'远程 & notes',remote:true}],activeVault:'远程 & notes',srvDefaultVault:'',srvResolvedVault:'远程 & notes'});
 const box=f.render('srv'),select=box.children[1];assert.equal(select.value,'');assert.match(select.options[0].textContent,/远程 & notes/);assert.match(select.options[1].textContent,/WebDAV/);
 select.value='远程 & notes';select.onchange();assert.equal(f.sent[0],'vault-set?kind=srv&id='+encodeURIComponent('远程 & notes'));assert.equal(select.disabled,true);
});
test('floating panel has independent shared default selectors and native active-vault reporting',()=>{const source=fs.readFileSync(path.join(root,'pages/LocalWeb.ets'),'utf8');assert.match(source,/vaultPicker\('srv'\)/);assert.match(source,/vaultPicker\('ai'\)/);assert.match(source,/ServiceVaultApi.set\(kind, vault\)/);assert.match(source,/action: 'active', vault: vault/);assert.match(source,/__vaultConfig&&window.__vaultConfig.id/);});

function deferred(){let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j;});return{promise,resolve,reject};}
async function waitForPosts(f,count=1){for(let i=0;i<20&&f.posts().length<count;i++)await Promise.resolve();assert.equal(f.posts().length,count);}
function nativeFixture(options={}){
 const source=fs.readFileSync(path.join(root,'pages/LocalWeb.ets'),'utf8');
 const methods=source.slice(source.indexOf('  private vaultPanelBusy:'),source.indexOf('  private lastSrvAddr:'));
 const snapshots={window:{__vaultConfig:{id:'远程 & notes'},__currentVaultId:'远程 & notes'},location:{origin:'http://127.0.0.1:6791'},document:{hidden:false}};
 const calls=[],timers=new Map();let serial=0;
 const context={WebDavSettings:{consumeAutoOpen(){}},ServiceVaultApi:{status:async()=>{calls.push('status');return options.status?options.status():{activeVault:snapshots.window.__currentVaultId};},set:async()=>options.save?options.save():{}},AiLanApi:{status:async()=>options.aiStatus?options.aiStatus():({access:{vaultIds:[]}})},
  http:{RequestMethod:{POST:'POST'},HttpDataType:{STRING:'STRING'},createHttp:()=>({request:async(url,request)=>{calls.push(JSON.parse(request.extraData));return options.response?options.response():{responseCode:200,result:JSON.stringify({activeVault:snapshots.window.__currentVaultId})};},destroy:()=>calls.push('destroy')})},
  setInterval:(fn,ms)=>{assert.equal(ms,1700);timers.set(++serial,fn);return serial;},clearInterval:id=>timers.delete(id)};
 vm.createContext(context);vm.createContext(snapshots);
 vm.runInContext(stripTypeScriptTypes('class Native {'+methods+'} globalThis.p=new Native();'),context);
 const p=context.p;Object.assign(p,{getUIContext:()=>({getHostContext:()=>({})}),pageAlive:true,localVisible:true,srvEpoch:0,webController:{runJavaScript:async code=>options.read?options.read(code):vm.runInContext(code,snapshots)},safeRun:code=>calls.push(code)});
 return{p,calls,timers,snapshots,posts:()=>calls.filter(x=>typeof x==='object')};
}
test('native reads only matching successful bootstrap IDs and JSON string results',async()=>{
 const f=nativeFixture();assert.equal(await f.p.readActiveVault(),'远程 & notes');
 f.snapshots.window.__currentVaultId='Pending';await f.p.syncActiveVault();assert.equal(f.posts().length,0);
 f.snapshots.window.__vaultConfig=null;await f.p.syncActiveVault();assert.equal(f.posts().length,0);
 const wrapped=nativeFixture({read:async()=>JSON.stringify(JSON.stringify({id:'quoted "库"'}))});assert.equal(await wrapped.p.readActiveVault(),'quoted "库"');
});
test('failed HTTP, wrong ack and malformed responses retry until a matching 200 ack',async()=>{
 for(const response of [()=>{throw Error('network');},()=>({responseCode:503,result:'{}'}),()=>({responseCode:200,result:'<html>'}),()=>({responseCode:200,result:'{"activeVault":"other"}'})]){
  let fail=true;const f=nativeFixture({response:()=>fail?response():{responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})}});
  await f.p.syncActiveVault();assert.equal(f.p.activeVaultAck,'');fail=false;await f.p.syncActiveVault();assert.equal(f.p.activeVaultAck,'远程 & notes');
  await f.p.syncActiveVault();assert.equal(f.posts().length,2);assert.equal(f.calls.filter(x=>x==='destroy').length,2);
 }
});
test('native tick serializes pending requests and records ack only after success',async()=>{
 const response=deferred(),f=nativeFixture({response:()=>response.promise});const first=f.p.syncActiveVault();assert.equal(first,f.p.syncActiveVault());await Promise.resolve();assert.equal(f.p.activeVaultAck,'');
 response.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await first;assert.equal(f.posts().length,1);assert.equal(f.p.activeVaultAck,'远程 & notes');
});
test('hide while JavaScript is pending prevents POST; hide during HTTP prevents ack',async()=>{
 const read=deferred(),f=nativeFixture({read:()=>read.promise});const first=f.p.syncActiveVault();f.p.localVisible=false;f.p.stopActiveVaultPoll();read.resolve(JSON.stringify({id:'A'}));await first;assert.equal(f.posts().length,0);assert.equal(f.p.activeVaultAck,'');
 const response=deferred(),g=nativeFixture({response:()=>response.promise});const second=g.p.syncActiveVault();await waitForPosts(g);g.p.localVisible=false;g.p.stopActiveVaultPoll();response.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await second;assert.equal(g.p.activeVaultAck,'');assert.equal(g.calls.at(-1),'destroy');
});
test('document epochs serialize old and new reports so an old POST cannot overwrite a newer ack',async()=>{
 const old=deferred();let server='',count=0;const f=nativeFixture({response:async()=>{const vault=f.posts().at(-1).vault;if(++count===1)await old.promise;server=vault;return {responseCode:200,result:JSON.stringify({activeVault:vault})};}});
 const first=f.p.syncActiveVault();await waitForPosts(f);f.p.stopActiveVaultPoll();
 f.snapshots.window.__currentVaultId='B';f.snapshots.window.__vaultConfig={id:'B'};
 assert.equal(f.p.syncActiveVault(),first);assert.equal(f.posts().length,1);
 old.resolve();await first;assert.equal(f.p.activeVaultAck,'');assert.equal(f.p.activeVaultPending,null);
 await f.p.syncActiveVault();assert.equal(server,'B');assert.equal(f.p.activeVaultAck,'B');assert.equal(f.posts().length,2);
});
test('vault changed during POST does not ack the previous selection',async()=>{
 const response=deferred(),f=nativeFixture({response:()=>response.promise});const first=f.p.syncActiveVault();await waitForPosts(f);f.snapshots.window.__currentVaultId='New';f.snapshots.window.__vaultConfig={id:'New'};response.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await first;assert.equal(f.p.activeVaultAck,'');
});
test('panel refresh waits for the in-flight active sync before reading follow state',async()=>{
 const response=deferred(),f=nativeFixture({response:()=>response.promise});const pending=f.p.syncActiveVault(),refresh=f.p.refreshVaultPanel();await waitForPosts(f);assert.equal(f.calls.includes('status'),false);
 response.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await pending;await refresh;assert.equal(f.calls.includes('status'),true);assert.ok(f.calls.indexOf('status')>f.calls.indexOf('destroy'));
});
test('panel refresh does not read or fill state after its document is replaced',async()=>{
 const response=deferred(),f=nativeFixture({response:()=>response.promise});const refresh=f.p.refreshVaultPanel();await waitForPosts(f);f.p.stopActiveVaultPoll();response.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await refresh;assert.equal(f.calls.includes('status'),false);
});
test('poll start/stop resets ack and timer; hidden pages never start work',async()=>{
 const f=nativeFixture();f.p.startActiveVaultPoll();assert.equal(f.timers.size,1);await f.p.activeVaultPending;assert.equal(f.p.activeVaultAck,'远程 & notes');f.p.stopActiveVaultPoll();assert.equal(f.timers.size,0);assert.equal(f.p.activeVaultAck,'');
 f.p.localVisible=false;f.p.startActiveVaultPoll();assert.equal(f.timers.size,0);assert.equal(f.posts().length,1);
});
test('returning to a previously acked vault retries after another vault report failed',async()=>{
 let fail=false;const f=nativeFixture({response:()=>({responseCode:fail?503:200,result:JSON.stringify({activeVault:f.snapshots.window.__currentVaultId})})});
 await f.p.syncActiveVault();fail=true;f.snapshots.window.__vaultConfig={id:'B'};f.snapshots.window.__currentVaultId='B';await f.p.syncActiveVault();assert.equal(f.p.activeVaultAck,'');
 fail=false;f.snapshots.window.__vaultConfig={id:'远程 & notes'};f.snapshots.window.__currentVaultId='远程 & notes';await f.p.syncActiveVault();assert.equal(f.posts().length,3);
});
test('panel resamples a vault switch that occurred during an existing poll',async()=>{
 const old=deferred();let reports=0;const f=nativeFixture({response:()=>++reports===1?old.promise:{responseCode:200,result:JSON.stringify({activeVault:'B'})}});
 const pending=f.p.syncActiveVault();await waitForPosts(f);f.snapshots.window.__vaultConfig={id:'B'};f.snapshots.window.__currentVaultId='B';const refresh=f.p.refreshVaultPanel();old.resolve({responseCode:200,result:JSON.stringify({activeVault:'远程 & notes'})});await pending;await refresh;
 assert.equal(f.posts().length,2);assert.equal(f.posts()[1].vault,'B');assert.equal(f.p.activeVaultAck,'B');assert.ok(f.calls.indexOf('status')>f.calls.lastIndexOf('destroy'));
});
test('late panel refresh cannot overwrite a newly saved default',async()=>{
  const oldAi=deferred(),entered=deferred();let reads=0,aiReads=0,current='Old';
  const f=nativeFixture({status:async()=>({srvDefaultVault:++reads===1?'Old':current}),save:async()=>{current='New';return{};},aiStatus:async()=>{if(++aiReads===1){entered.resolve();return oldAi.promise;}return{access:{vaultIds:[]}};}});
  const stale=f.p.refreshVaultPanel();await entered.promise;await f.p.setPanelVault('srv','New');oldAi.resolve({access:{vaultIds:[]}});await stale;
  const published=f.calls.filter(x=>typeof x==='string'&&x.startsWith('window.__vtVaultState='));
  assert.equal(published.length,1);assert.match(published[0],/"srvDefaultVault":"New"/);
});
test('main document hooks reset native epoch and legacy active iframe reporting is absent',()=>{
 const source=fs.readFileSync(path.join(root,'pages/LocalWeb.ets'),'utf8');
 assert.doesNotMatch(source,/trackActive|vault-active/);assert.match(source,/onPageBegin\(\(\) => \{\s*this.stopActiveVaultPoll\(\);/);assert.match(source,/onPageEnd\(\(event\) => \{\s*this.startActiveVaultPoll\(\);/);
 for(const hook of ['onPageHide','aboutToDisappear'])assert.match(source,new RegExp(hook+'\\(\\) \\{\\s*this.stopActiveVaultPoll\\(\\);'));
});
