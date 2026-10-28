const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '../entry/src/main/ets');
function fixture(options = {}) {
  const state = new Map(Object.entries({ignisReady:true, lanShareUser:'u', lanSharePass:'p', appMode:'local', ...options.state}));
  const calls = [];
  const result = options.result === undefined ? {running:true, port:12345} : options.result;
  const ctx = {
    AppStorage:{get:k=>state.get(k), setOrCreate:(k,v)=>state.set(k,v)},
    VipService:{isVip:()=>options.vip !== false},
    LanShareApi:{getLanIp:()=>options.ip ?? '192.168.1.2', enable:async()=>{calls.push('srv-enable');return result;}, disable:async()=>{calls.push('srv-disable');return result;}},
    AiLanApi:{status:async()=>({}), hasAccessPolicy:()=>options.policy !== false, enable:async()=>{calls.push('ai-enable');return result;}, disable:async()=>{calls.push('ai-disable');return result;}},
    BackgroundLease:{reconcile:async()=>{calls.push('lease');return true;}}
  };
  let source=fs.readFileSync(path.join(root,'common/HomeServiceControl.ets'),'utf8')
    .replace(/^import .*;\n/gm,'').replace('export class','class')
    .replace(/AppStorage.get<(?:string|boolean|number)>/g,'AppStorage.get')
    .replace(/: common.UIAbilityContext|: string|: boolean|: Promise<string>/g,'');
  vm.createContext(ctx);vm.runInContext(source+';globalThis.control=HomeServiceControl;',ctx);
  return {state,calls,change:(kind,on)=>ctx.control.change({},kind,on)};
}
test('member can start each service without changing the remembered entry',async()=>{
  for(const kind of ['srv','ai']) {const f=fixture();assert.equal(await f.change(kind,true),'');assert.equal(f.state.get(kind+'Running'),true);assert.equal(f.state.get(kind+'ModeEnabled'),true);assert.equal(f.state.get('appMode'),'local');assert.deepEqual(f.calls,[kind+'-enable','lease']);}
});
test('expired member can stop a running service and clear restoration intent',async()=>{
  for(const kind of ['srv','ai']) {const f=fixture({vip:false,result:{running:false},state:{[kind+'ModeEnabled']:true}});assert.equal(await f.change(kind,false),'');assert.equal(f.state.get(kind+'ModeEnabled'),false);assert.equal(f.state.get(kind+'Running'),false);}
});
test('membership and network gate actual enable calls',async()=>{
  for(const kind of ['srv','ai']) {const f=fixture({vip:false});assert.equal(await f.change(kind,true),'vip');assert.deepEqual(f.calls,[]);const g=fixture({ip:''});assert.match(await g.change(kind,true),/Wi-Fi/);assert.deepEqual(g.calls,[]);}
});
test('missing credentials and access policy lead to existing setup pages',async()=>{
  const srv=fixture({state:{lanSharePass:''}});assert.equal(await srv.change('srv',true),'srvSetup');assert.deepEqual(srv.calls,[]);
  const ai=fixture({policy:false});assert.equal(await ai.change('ai',true),'aiSetup');assert.deepEqual(ai.calls,[]);
});
test('ambiguous errors never claim running or change saved intent',async()=>{
  for(const kind of ['srv','ai']) {const f=fixture({result:null});assert.match(await f.change(kind,true),/未确认/);assert.equal(f.state.get(kind+'Running'),undefined);assert.equal(f.state.get(kind+'ModeEnabled'),undefined);}
});
test('cold process requests startup, while disabling clears saved intent without network calls',async()=>{
  for(const kind of ['srv','ai']) {const f=fixture({state:{ignisReady:false}});assert.equal(await f.change(kind,true),'startup');assert.deepEqual(f.calls,[]);assert.equal(await f.change(kind,false),'');assert.equal(f.state.get(kind+'ModeEnabled'),false);}
});
