// Container-only guards, NOT an ArkTS compiler or device visual test.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');const path=require('node:path');
const root=path.join(__dirname,'../entry/src/main/ets');
test('local popup injected scripts parse and server/AI lamp obeys OR semantics',()=>{
 const source=fs.readFileSync(path.join(root,'pages/LocalWeb.ets'),'utf8');
 const scripts=[...source.matchAll(/runJavaScript\(`([\s\S]*?)`\)/g)].map(x=>x[1]);assert.ok(scripts.length>=2);
 for(const s of scripts)new vm.Script(s);
 const m=source.match(/function syncLamp\(\)\{.*?\}\}window\.__vtAiSync=/);assert.ok(m);
 for(const srv of [false,true])for(const ai of [false,true]){const button={style:{}};vm.runInNewContext(m[0].replace('window.__vtAiSync=','')+';syncLamp();',{S:{running:srv},A:{known:true,running:ai},document:{getElementById:()=>button}});assert.equal(button.textContent,srv||ai?'◉':'○');}
 assert.match(source,/import \{ pasteboard, BusinessError \}/);
 assert.match(source,/JSON\.stringify\(\{ running: true/);
 assert.match(source,/text\.indexOf\('\"pairingCode\"'\)/);
});
test('server username is encoded as data, never evaluated as code',()=>{
 const user='"};globalThis.auditMarker=1;//';const context={window:{}};
 vm.runInNewContext('window.__vtSrvState='+JSON.stringify({running:true,user})+';',context);
 assert.equal(context.auditMarker,undefined);assert.equal(context.window.__vtSrvState.user,user);
});
test('agent setup guide is separately copyable during preview and carries safety boundaries',()=>{
 const page=fs.readFileSync(path.join(root,'pages/AiConnectPage.ets'),'utf8');
 const copy=page.slice(page.indexOf('private async copyAgentSetup'),page.indexOf('private async copyCommand'));
 assert.ok(!copy.includes('connectorPublished'));
 assert.match(copy,/this.agentSetupPrompt/);
 assert.ok(page.indexOf("Text('让 AI 帮我配置')")<page.indexOf("this.platformGuide('Claude Code')"));
 assert.match(page,/height\(46\)\.padding\(\{ left: 16, right: 16 \}\)/);
 assert.match(page,/不要要求我把配对 JSON/);assert.match(page,/不要安装旧拟名/);assert.match(page,/@liiink\/vitreus-ai-connector@1\.3\.9-beta\.1/);
});
test('AI visual background has cancellation and page conditionally mounts it',()=>{
 const source=fs.readFileSync(path.join(root,'components/AiNetworkBackground.ets'),'utf8');
 const page=fs.readFileSync(path.join(root,'pages/AiConnectPage.ets'),'utf8');
 assert.match(source,/clearInterval\(this.timer\)/);assert.match(source,/aboutToDisappear[\s\S]*?this.stop\(\)/);
 assert.match(page,/if \(this.pageVisible\) \{\s*AiNetworkBackground/);
 assert.match(page,/detailsExpanded/);assert.match(page,/accessExpanded/);
});
