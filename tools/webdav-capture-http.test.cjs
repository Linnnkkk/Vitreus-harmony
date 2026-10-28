// Executes production requester and capture engine; only SDK/network/disk are replaced.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {stripTypeScriptTypes}=require('node:module');
const root=path.join(__dirname,'../entry/src/main/ets/common');
function fixture(){
 const files=new Map(), records=new Map(), calls=[]; let member=true,version=1,drop=false;
 const collection='<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';
 const response=(statusCode,body='',headers={})=>({statusCode,headers,toString:()=>body});
 const sandbox={URL,console,Date,Math,JSON,Map,Set,Error,encodeURIComponent,decodeURIComponent,
  fs:{accessSync:p=>records.has(p),readTextSync:p=>records.get(p),OpenMode:{READ_WRITE:1,CREATE:2,TRUNC:4},openSync:p=>({fd:p}),writeSync:(p,b)=>records.set(p,b),closeSync(){},renameSync:(a,b)=>{records.set(b,records.get(a));records.delete(a);}},
  url:{URL}, util:{TextEncoder,Base64Helper:class{encodeToStringSync(v){return Buffer.from(v).toString('base64');}}},
  VipService:{isVip:()=>member},AppStorage:{get:()=>undefined},
  WebDavSettings:{normalizeUrl:x=>x.replace(/\/+$/,'')},
  QuickCapture:{formatEntryAt:(text)=>'- '+text},
  WebClip:{pickUrl:text=>text.startsWith('https://')?text:'',skipped:()=>({ok:false}),fetch:async()=>({ok:true,title:'Fixture page',body:'Captured body',metadata:{site:'fixture',author:'',published:'',description:'',canonical:''}})},
  rcp:{Request:class{constructor(target,method,headers){Object.assign(this,{url:target,method,headers});}},createSession:()=>({close(){},fetch:async req=>{
    calls.push(req); const target=new URL(req.url);const name=decodeURIComponent(target.pathname.replace('/dav/PARA/',''));
    if(req.method==='PROPFIND')return response(207,collection,{'content-type':'application/xml'});
    if(req.method==='MKCOL')return response(201);
    const value=files.get(name);
    if(req.method==='GET')return value?response(200,value.body,{'content-type':'text/markdown','etag':value.etag}):response(404);
    if(req.headers['If-None-Match']==='*'&&value)return response(412);
    if(req.headers['If-Match']&&(!value||req.headers['If-Match']!==value.etag))return response(412);
    if(req.method==='PUT'){files.set(name,{body:req.content,etag:'"v'+version+++'"'});if(drop){drop=false;throw Error('lost response fixture');}return response(201);}
    if(req.method==='DELETE'){files.delete(name);return response(204);}
    return response(405);
  }})}
 };
 vm.createContext(sandbox);
 for(const name of ['CapturePathTemplate','RemoteCapture','WebDavProbe','WebDavCaptureHttp']){
  let src=fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/^import .*;\n/gm,'').replace(/export (class|function|interface|type)/g,'$1');
  src=stripTypeScriptTypes(src);
  const expose=name==='RemoteCapture'?'RemoteCapture,RemoteCaptureEngine':name==='WebDavCaptureHttp'?'createWebDavCaptureRequester':name;
  vm.runInContext(src+';Object.assign(globalThis,{'+expose+'});',sandbox);
 }
 const request=sandbox.createWebDavCaptureRequester({enabled:true,url:'https://dav.example/dav/PARA',vaultName:'PARA'},'fixture','secret','webdav:abc');
 const engine=new sandbox.RemoteCaptureEngine({filesDir:'/fixture'},request);
 const op=(text,kind='quick')=>({version:1,id:'fixture'+version++,text,isTask:false,addTime:true,kind,capturedAt:Date.now(),serverURL:'https://webdav-abc.capture.invalid',stage:'new',vault:'',quickPath:'',quickHeading:'',clipPath:'',clipBody:'',entry:'',before:'',after:'',existed:false,templates:{quickNotePath:'',quickNoteHeading:'',clipPath:''},premium:true});
 return{files,calls,engine,request,op,setMember:v=>member=v,dropNext:()=>drop=true};
}
test('production engine writes quick note to configured WebDAV and appends on next save',async()=>{
 const f=fixture();const vault=(await f.engine.listVaults())[0];const first=f.op('first');await f.engine.prepare(first,vault);await f.engine.save(first);
 assert.equal(first.stage,'done');assert.equal(f.files.get('Inbox.md').body,'# Inbox\n\n- first\n');
 const second=f.op('second');await f.engine.prepare(second,vault);await f.engine.save(second);
 assert.equal(f.files.get('Inbox.md').body,'# Inbox\n\n- first\n- second\n');
 const puts=f.calls.filter(x=>x.method==='PUT');assert.equal(puts[0].headers['If-None-Match'],'*');assert.match(puts[1].headers['If-Match'],/^"v/);
});
test('production share engine writes clipping body and index, and undo restores both',async()=>{
 const f=fixture();const vault=(await f.engine.listVaults())[0];const op=f.op('https://article.example/a','share');await f.engine.prepare(op,vault);await f.engine.save(op);
 assert.ok(op.clipPath);assert.match(f.files.get(op.clipPath).body,/Captured body/);assert.match(f.files.get('Inbox.md').body,/\[\[/);
 await f.engine.undo(op);assert.equal(op.stage,'undone');assert.equal(f.files.size,0);
});
test('changed ETag rejects stale write and unexpected path or vault never reaches transport',async()=>{
 const f=fixture();f.files.set('Inbox.md',{body:'original',etag:'"1"'});
 const route='/api/fs/readFile?vault=webdav%3Aabc&path=Inbox.md&encoding=utf8';await f.request('GET',route,'');f.files.set('Inbox.md',{body:'other device',etag:'"2"'});
 const r=await f.request('POST','/api/fs/writeFile',JSON.stringify({vault:'webdav:abc',path:'Inbox.md',content:'overwrite',encoding:'utf8'}));assert.equal(r.status,412);assert.equal(f.files.get('Inbox.md').body,'other device');
 const count=f.calls.length;const bad=await f.request('GET','/api/fs/readFile?vault=local&path=..%2Fsecret.md&encoding=utf8','');assert.equal(bad.status,403);assert.equal(f.calls.length,count);
});
test('lost PUT response is recovered by exact after-image without duplicate append',async()=>{
 const f=fixture();const vault=(await f.engine.listVaults())[0];const op=f.op('once');await f.engine.prepare(op,vault);f.dropNext();await assert.rejects(f.engine.save(op));assert.equal(op.stage,'indexUnknown');
 const writes=f.calls.filter(x=>x.method==='PUT').length;await f.engine.save(op);assert.equal(op.stage,'done');assert.equal(f.calls.filter(x=>x.method==='PUT').length,writes);assert.equal(f.files.get('Inbox.md').body.match(/once/g).length,1);
});
test('expired membership blocks real reads and writes without network traffic',async()=>{
 const f=fixture();f.setMember(false);const r=await f.request('GET','/api/vault/list','');assert.equal(r.status,403);assert.equal(f.calls.length,0);
});
