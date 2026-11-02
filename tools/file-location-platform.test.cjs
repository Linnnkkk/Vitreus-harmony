const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/LocalWeb.ets'),'utf8');
const start=source.indexOf("      // Tablets behave like a PC in every mode");const end=source.indexOf('\n    } catch (error)',start);const code=source.slice(start,end);
assert.ok(start>0&&end>start,'dispatch block not found');

async function dispatch(type){
  const calls=[];class Options{}class Picker{constructor(ctx){assert.equal(ctx,context)}async select(options){calls.push(['picker',options.defaultFilePathUri])}}
  const context={startAbility:async want=>calls.push(['manager',want])};
  const sandbox={deviceInfo:{deviceType:type},context,directoryUri:'file://test/Download/Vault/中文目录',picker:{DocumentSelectOptions:Options,DocumentViewPicker:Picker}};
  await vm.runInNewContext('(async()=>{'+code+'})()',sandbox);
  return {calls,sandbox};
}

// Phone is its own branch; tablet (pad or PC mode) and PC share one. Both open the file manager.
for(const type of ['2in1','desktop','tablet','phone'])test('file location dispatch for '+type,async()=>{
  const r=await dispatch(type);
  assert.equal(r.calls.length,1);
  assert.equal(r.calls[0][0],'manager');
  assert.equal(r.calls[0][1].bundleName,'com.huawei.hmos.filemanager');
  assert.equal(r.calls[0][1].abilityName,'MainAbility');
  assert.equal(r.calls[0][1].parameters.fileUri,r.sandbox.directoryUri);
});

test('tablets share the PC branch, not the phone branch and not the picker',()=>{
  const pc=code.indexOf("deviceInfo.deviceType === '2in1'");const phone=code.indexOf("deviceInfo.deviceType === 'phone'");
  assert.ok(pc>=0&&phone>pc);
  assert.match(code.slice(pc,phone),/deviceType === 'tablet'/);
  assert.doesNotMatch(source,/isInFreeWindowMode|isFreeformWindow/);
});

test('an unknown device type still falls back to the document picker',async()=>{
  const r=await dispatch('wearable');
  assert.equal(r.calls.length,1);assert.deepEqual(r.calls[0],['picker',r.sandbox.directoryUri]);
});
