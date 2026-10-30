const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
for(const name of ['LocalWeb','Index']){
 const source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages',name+'.ets'),'utf8');
 const script=source.split('\n').find(l=>l.includes('var S={drag:false'));
 function harness(){
  const S={drag:false,moved:false,hidden:false,autoSnap:0};let reload=0,back='',panel=0;
  const bar={style:{},getBoundingClientRect:()=>({left:5,top:5})};
  const downText=script.slice(script.indexOf('function down(e)'),script.indexOf('function move(e)'));
  const upText=script.slice(script.indexOf('function up(e)'),script.indexOf("bar.addEventListener('mousedown'"));
  const window={innerWidth:600,innerHeight:800,location:{set href(x){back=x;}},__vtSrvPanel:()=>panel++};
  const make=new Function('S','bar','window','location','pt','expand','snap','clearTimeout',downText+upText+';return {down,up};');
  const f=make(S,bar,window,{reload:()=>reload++},e=>({x:20,y:20}),()=>{},()=>{},()=>{});
  return {...f,S,result:()=>({reload,back,panel})};
 }
 test(name+': tapping SVG path uses refresh button ancestor and never navigates back',()=>{
  const h=harness();h.down({target:{closest:()=>({id:'vt-b'})},preventDefault(){}});h.up({target:{id:''}});assert.deepEqual(h.result(),{reload:1,back:'',panel:0});
 });
 test(name+': toolbar gaps do not navigate and actual return button still works',()=>{
  const h=harness();h.down({target:{closest:()=>null},preventDefault(){}});h.up({});assert.equal(h.result().back,'');
  h.down({target:{closest:()=>({id:'vt-a'})},preventDefault(){}});h.up({});assert.equal(h.result().back,'vitreus://switch');
 });
 test(name+': drag does not trigger a button action',()=>{
  const h=harness();h.down({target:{closest:()=>({id:'vt-b'})},preventDefault(){}});h.S.moved=true;h.up({});assert.equal(h.result().reload,0);
 });
}
