// 「用 Vitreus 打开」Markdown：执行生产代码（仅 SDK/磁盘/网络被替换），并核对各入口的接线。
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {stripTypeScriptTypes}=require('node:module');
const ets=path.join(__dirname,'../entry/src/main/ets');
const read=(rel)=>fs.readFileSync(path.join(ets,rel),'utf8');

function load(files,sandbox){
  for(const rel of files){
    let src=read(rel).replace(/^import .*;\n/gm,'').replace(/export (class|function|interface|type|const)/g,'$1');
    src=stripTypeScriptTypes(src);
    const names=[...src.matchAll(/^(?:class|const) (\w+)/gm)].map(m=>m[1]);
    vm.runInContext(src+';Object.assign(globalThis,{'+names.join(',')+'});',sandbox);
  }
}

// 内存文件系统：只实现 OpenMarkdown 用到的 fileIo 子集
function makeFs(){
  const files=new Map(), handles=new Map(); let nextFd=3; const state={failWrite:false};
  const api={
    OpenMode:{READ_ONLY:0,WRITE_ONLY:1,CREATE:64},
    accessSync:p=>files.has(p),
    openSync:(p,mode=0)=>{
      if(!(mode&64)&&!files.has(p)) throw new Error('ENOENT '+p);
      if((mode&64)&&!files.has(p)) files.set(p,Buffer.alloc(0));
      const fd=nextFd++; handles.set(fd,p); return {fd};
    },
    readSync:(fd,buf,opt)=>{
      const data=files.get(handles.get(fd)); const off=opt.offset||0;
      const n=Math.min(opt.length??buf.byteLength,buf.byteLength,Math.max(0,data.length-off));
      new Uint8Array(buf).set(data.subarray(off,off+n)); return n;
    },
    writeSync:(fd,ab)=>{ if(state.failWrite) throw new Error('disk full'); files.set(handles.get(fd),Buffer.from(ab)); return ab.byteLength; },
    closeSync:()=>{}, unlinkSync:p=>{files.delete(p);},
  };
  return {api,files,state};
}

function openMarkdown(){
  const mem=makeFs();
  const sandbox={console,Date,Math,JSON,Error,Uint8Array,ArrayBuffer,decodeURIComponent,encodeURIComponent,
    fs:mem.api,
    util:{TextDecoder:class{constructor(e,o){this.d=new TextDecoder(e,o);}decodeToString(b){return this.d.decode(b);}}}};
  vm.createContext(sandbox);
  load(['common/OpenMarkdown.ets'],sandbox);
  return {O:sandbox.OpenMarkdown,sandbox,mem};
}
const bytes=s=>new Uint8Array(Buffer.from(s,'utf8'));
const text=b=>Buffer.from(b).toString('utf8');

test('file name comes from the last URI segment, decoded and made safe',()=>{
  const {O}=openMarkdown();
  assert.equal(O.fileNameFromUri('file://docs/storage/Users/currentUser/Download/%E6%97%A5%E8%AE%B0.md'),'日记.md');
  assert.equal(O.fileNameFromUri('file://media/Documents/a%20b.md?x=1#frag'),'a b.md');
  assert.equal(O.fileNameFromUri('file://docs/x/note.markdown'),'note.markdown');
  assert.equal(O.fileNameFromUri('file://docs/x/README'),'README.md');
  assert.equal(O.sanitizeName('a/b:c*d?.md'),'a_b_c_d_.md');
  assert.equal(O.sanitizeName('...hidden.md'),'hidden.md');
  assert.equal(O.sanitizeName('   '),'未命名.md');
  const long=O.sanitizeName('x'.repeat(300)+'.md');
  assert.ok(long.length<=120&&long.endsWith('.md'));
});

test('duplicate names get a numbered sibling, never an overwrite',()=>{
  const {O}=openMarkdown();
  assert.equal(O.candidateName('a.md',1),'a.md');
  assert.equal(O.candidateName('a.md',2),'a (2).md');
  assert.equal(O.candidateName('a.b.md',3),'a.b (3).md');
});

test('local save: new file, identical content reused, different content renamed',()=>{
  const {O,mem}=openMarkdown();
  const vault='/vaults/PARA';
  assert.equal(O.saveToLocalVault(vault,{name:'n.md',bytes:bytes('# one')}),'n.md');
  assert.equal(text(mem.files.get(vault+'/n.md')),'# one');
  // same bytes again: reuse the existing file, create nothing
  assert.equal(O.saveToLocalVault(vault,{name:'n.md',bytes:bytes('# one')}),'n.md');
  assert.equal(mem.files.size,1);
  // different bytes under the same name: sibling, original untouched
  assert.equal(O.saveToLocalVault(vault,{name:'n.md',bytes:bytes('# two')}),'n (2).md');
  assert.equal(text(mem.files.get(vault+'/n.md')),'# one');
  assert.equal(O.saveToLocalVault(vault,{name:'n.md',bytes:bytes('# three')}),'n (3).md');
  // the second variant is recognised on a later open
  assert.equal(O.saveToLocalVault(vault,{name:'n.md',bytes:bytes('# two')}),'n (2).md');
  assert.equal(mem.files.size,3);
});

test('local save keeps bytes exactly (non-ASCII, CRLF) and leaves nothing behind on failure',()=>{
  const {O,mem}=openMarkdown();
  const data=bytes('标题\r\n正文 ✓\r\n');
  O.saveToLocalVault('/v',{name:'c.md',bytes:data});
  assert.deepEqual([...mem.files.get('/v/c.md')],[...data]);
  mem.state.failWrite=true;
  assert.throws(()=>O.saveToLocalVault('/v',{name:'d.md',bytes:bytes('x')}),/disk full/);
  assert.equal(mem.files.has('/v/d.md'),false,'a half-written file must be removed');
});

test('reading respects the size limit and returns the whole file across chunks',()=>{
  const {O,mem}=openMarkdown();
  const big=Buffer.alloc(150*1024,97); mem.files.set('/in/big.md',big);
  assert.equal(O.readBytes('/in/big.md').length,150*1024);
  assert.throws(()=>O.readBytes('/in/big.md',100*1024),/文件过大/);
  assert.throws(()=>O.readIncoming(''),/没有收到/);
  const incoming=O.readIncoming('/in/big.md');
  assert.equal(incoming.name,'big.md');
});

test('remote upload needs valid UTF-8',()=>{
  const {O}=openMarkdown();
  assert.equal(O.decodeText(bytes('中文 ok')),'中文 ok');
  assert.throws(()=>O.decodeText(new Uint8Array([0xff,0xfe,0x00])),/UTF-8/);
});

test('open request round-trips and rejects anything malformed or stale',()=>{
  const {O}=openMarkdown(); const now=1_000_000;
  const ok=(r)=>O.parseRequest(O.encodeRequest(r),now);
  // objects come from the vm realm: compare their JSON, not their prototypes
  assert.equal(JSON.stringify(ok({kind:'local',vault:'PARA',file:'a.md',at:now})),JSON.stringify({kind:'local',vault:'PARA',file:'a.md',at:now}));
  assert.equal(ok({kind:'webdav',vault:'',file:'a.md',at:now}).kind,'webdav');
  assert.equal(ok({kind:'server',vault:'v1',file:'a.md',at:now}).vault,'v1');
  assert.equal(ok({kind:'local',vault:'',file:'a.md',at:now}),undefined,'local needs a vault');
  assert.equal(ok({kind:'server',vault:'',file:'a.md',at:now}),undefined,'server needs a vault');
  assert.equal(ok({kind:'local',vault:'v',file:'',at:now}),undefined,'file is required');
  assert.equal(ok({kind:'other',vault:'v',file:'a.md',at:now}),undefined);
  assert.equal(ok({kind:'local',vault:'v',file:'a.md',at:now-3*60*1000}),undefined,'expired');
  assert.equal(ok({kind:'local',vault:'v',file:'a.md',at:now+3*60*1000}),undefined,'from the future');
  assert.equal(O.parseRequest('not json',now),undefined);
  assert.equal(O.parseRequest('',now),undefined);
  assert.equal(O.parseRequest(undefined,now),undefined);
  assert.equal(O.parseRequest('{"kind":"local","vault":1,"file":"a.md","at":1}',now),undefined);
});

test('the open script waits for the workspace and carries the file name as a JSON string',()=>{
  const {O}=openMarkdown();
  const script=O.openScript('a "quoted" 名字</script>.md');
  assert.match(script,/window\.OBS_ACT/);
  assert.match(script,/layoutReady/);
  assert.ok(script.includes(JSON.stringify('a "quoted" 名字</script>.md')),'file is embedded only as a JSON literal');
  // runs in a fake page: not ready twice, then ready
  let calls=[],tries=0; const timers=[];
  const win={setTimeout:(f)=>timers.push(f),console,JSON};
  Object.defineProperty(win,'OBS_ACT',{get:()=>tries>=2?(a=>calls.push(a)):undefined});
  Object.defineProperty(win,'app',{get:()=>({workspace:{layoutReady:tries>=2}})});
  const ctx=vm.createContext({window:win,setTimeout:win.setTimeout,console});
  vm.runInContext(script,ctx);
  assert.equal(calls.length,0); tries=1; timers.shift()(); assert.equal(calls.length,0);
  tries=2; timers.shift()();
  assert.equal(JSON.stringify(calls),JSON.stringify([{action:'open',file:'a "quoted" 名字</script>.md'}]));
});

// 远程库上传：用内存服务器实现 /api/fs/readFile 与 /api/fs/writeFile，执行真实的引擎代码
function remote({mismatchReadback=false,html=false,status500=false}={}){
  const files=new Map(),calls=[];
  const json=(status,obj)=>({status,body:JSON.stringify(obj),contentType:'application/json; charset=utf-8',error:''});
  const request=async(method,route,body)=>{
    calls.push(method+' '+route.split('?')[0]);
    if(html) return {status:200,body:'<html>login</html>',contentType:'text/html',error:''};
    const u=new URL(route,'http://x');
    if(method==='GET'){
      const p=u.searchParams.get('path');
      if(status500) return json(500,{error:'boom',code:'EIO'});
      return files.has(p)?{status:200,body:files.get(p),contentType:'text/plain; charset=utf-8',error:''}:json(404,{error:'nf',code:'ENOENT'});
    }
    const b=JSON.parse(body); files.set(b.path,mismatchReadback?b.content+'!':b.content); return json(200,{ok:true,mtime:1,size:b.content.length});
  };
  const sandbox={console,Date,Math,JSON,Map,Set,Error,URL,encodeURIComponent,decodeURIComponent,Uint8Array,ArrayBuffer,
    fs:{},util:{TextDecoder},AppStorage:{get:()=>undefined}};
  vm.createContext(sandbox);
  load(['common/OpenMarkdown.ets','common/CapturePathTemplate.ets','common/RemoteCapture.ets'],sandbox);
  return {engine:new sandbox.RemoteCaptureEngine({filesDir:'/x'},request),files,calls};
}

test('remote upload writes into the vault root, reuses identical content, renames different content',async()=>{
  const r=remote();
  assert.equal(await r.engine.uploadRootFile('V','n.md','# one'),'n.md');
  assert.equal(r.files.get('n.md'),'# one');
  assert.deepEqual(r.calls,['GET /api/fs/readFile','POST /api/fs/writeFile','GET /api/fs/readFile']);
  r.calls.length=0;
  assert.equal(await r.engine.uploadRootFile('V','n.md','# one'),'n.md');
  assert.deepEqual(r.calls,['GET /api/fs/readFile'],'identical content is not uploaded again');
  assert.equal(await r.engine.uploadRootFile('V','n.md','# two'),'n (2).md');
  assert.equal(r.files.get('n.md'),'# one','the existing note is never overwritten');
  assert.equal(r.files.get('n (2).md'),'# two');
});

test('remote upload fails loudly when the read-back differs, the server errors, or a login page answers',async()=>{
  await assert.rejects(()=>remote({mismatchReadback:true}).engine.uploadRootFile('V','a.md','x'),/回读不一致/);
  await assert.rejects(()=>remote({status500:true}).engine.uploadRootFile('V','a.md','x'),/HTTP 500/);
  await assert.rejects(()=>remote({html:true}).engine.uploadRootFile('V','a.md','x'),/登录网页/);
});

test('the system open-with entry, handoff and startup routing are wired',()=>{
  const manifest=read('../module.json5');
  const viewBlock=manifest.slice(manifest.indexOf('ohos.want.action.viewData'),manifest.indexOf('ohos.want.action.viewData')+900);
  // file-open entries use `type` (UTD/MIME) + linkFeature FileOpen; `utd` is the share-only field and is not matched by the file manager
  assert.match(viewBlock,/"type":\s*"general\.markdown"[\s\S]{0,120}"linkFeature":\s*"FileOpen"/);
  assert.match(viewBlock,/"type":\s*"text\/markdown"[\s\S]{0,120}"linkFeature":\s*"FileOpen"/);
  assert.doesNotMatch(viewBlock,/"utd"/,'must not use the share-only utd field for file open');
  assert.doesNotMatch(viewBlock,/plain-text|general\.text/,'only Markdown, not every text file');
  assert.match(read('entryability/ShareAbility.ets'),/want\.action === OpenMarkdown\.ACTION_VIEW/);
  assert.match(read('entryability/ShareAbility.ets'),/pages\/OpenMarkdownPage/);
  assert.match(fs.readFileSync(path.join(ets,'../resources/base/profile/main_pages.json'),'utf8'),/pages\/OpenMarkdownPage/);
  const entry=read('entryability/EntryAbility.ets');
  assert.match(entry,/acceptOpenRequest\(want\)/);
  assert.match(entry,/onNewWant\(want: Want[\s\S]{0,300}loadContent\('pages\/Splash'/);
  const splash=read('pages/Splash.ets');
  assert.ok(splash.indexOf("parseRequest(AppStorage.get<string>('openRequest'))")<splash.indexOf('StartupPreferences.restore(this.getUIContext'),'open request is checked before the remembered mode');
  assert.match(read('pages/NodeTest.ets'),/open\.kind === 'local'[\s\S]{0,400}webDavLocalVault/);
  assert.match(read('pages/NodeTest.ets'),/openLocal \? 'pages\/LocalWeb'/);
  assert.match(read('pages/LocalWeb.ets'),/deliverPendingOpen\(\);/);
  assert.match(read('pages/Index.ets'),/'vault=' \+ encodeURIComponent\(open\.vault\)/);
});
