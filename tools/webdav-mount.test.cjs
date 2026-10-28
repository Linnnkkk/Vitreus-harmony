const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const text = fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/common/WebDavMount.ets'),'utf8');
const body = text.slice(text.indexOf('  static async verify'),text.lastIndexOf('\n}'))
 .replace('static async','async').replace(': common.UIAbilityContext','').replace(': Promise<string>','')
 .replace(' as string','').replace(' as MountedVault[]','').replace(': MountedVault','');
function harness(list, member=true, enabled=true) {
 let destroyed=0;
 const ctx={WebDavSettings:{load:()=>({enabled,vaultName:'PARA'})},VipService:{isVip:()=>member},http:{RequestMethod:{GET:'GET'},HttpDataType:{STRING:'string'},createHttp:()=>({request:async()=>({responseCode:200,result:JSON.stringify(list)}),destroy:()=>destroyed++})}};
 vm.createContext(ctx);vm.runInContext(`class Mount { ${body} }; globalThis.mount = new Mount();`,ctx);
 return {run:()=>ctx.mount.verify({}),destroyed:()=>destroyed};
}
test('a same-name local vault cannot masquerade as a remote mount',async()=>{
 const h=harness([{id:'PARA',remote:false}]);await assert.rejects(h.run(),/未挂载/);assert.equal(h.destroyed(),1);
});
test('verified remote mount returns its ID',async()=>{
 const h=harness([{id:'PARA',remote:true}]);assert.equal(await h.run(),'PARA');assert.equal(h.destroyed(),1);
});
test('membership and disabled settings are checked before remote opening',async()=>{
 await assert.rejects(harness([],false).run(),/会员/);assert.equal(await harness([],true,false).run(),'');
});
