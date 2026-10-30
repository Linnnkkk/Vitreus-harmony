const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
for(const name of ['AiConnectPage','LanServerPage']){
 const s=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages',name+'.ets'),'utf8');const a=s.indexOf('  onBackPress(): boolean {');const b=s.indexOf('\n  }',a);
 const body=s.slice(a,b+4).replace('onBackPress(): boolean','function onBackPress()');
 const run=(depth,overrides={})=>{const calls=[];const p={confirmWrite:false,confirmRevoke:false,srvSafetyShow:false,...overrides};const fn=new Function('router','return ('+body+')')({getLength:()=>depth,back:()=>calls.push('pop'),replaceUrl:x=>calls.push(x.url)});assert.equal(fn.call(p),true);return {calls,p};};
 test(name+' returns by pop when entered from home',()=>assert.deepEqual(run(2).calls,['pop']));
 test(name+' root entry falls back to home',()=>assert.deepEqual(run(1).calls,['pages/ModeSelect']));
 for(const flag of name==='AiConnectPage'?['confirmWrite','confirmRevoke']:['srvSafetyShow'])test(name+' closes '+flag+' before navigation',()=>{const r=run(2,{[flag]:true});assert.deepEqual(r.calls,[]);assert.equal(r.p[flag],false);});
}
