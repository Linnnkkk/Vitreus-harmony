const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');const {stripTypeScriptTypes}=require('node:module');
const raw=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/common/WebClip.ets'),'utf8').replace(/^import .*;\n/gm,'').replace(/export (class|interface)/g,'$1');
let pageHtml=''; let requested=''; let destroyed=0;
const ctx={console,http:{RequestMethod:{GET:'GET'},HttpDataType:{STRING:'STRING'},createHttp:()=>({request:async(url)=>{requested=url;return {responseCode:200,header:{'content-type':'text/html'},result:pageHtml};},destroy:()=>destroyed++})},hilog:{error(){}}};vm.createContext(ctx);vm.runInContext(stripTypeScriptTypes(raw)+';globalThis.clip=WebClip;',ctx);
test('WeChat lazy images preserve no-referrer across clipping cleanup',()=>{const result=ctx.clip.toText('<p>正文</p><img data-src="https://mmbiz.qpic.cn/mmbiz_png/fixture/640?wx_fmt=png&amp;x=1" alt="示例">','https://mp.weixin.qq.com/s/example');assert.match(result,/referrerpolicy="no-referrer"/);assert.match(result,/mmbiz.qpic.cn/);assert.match(result,/正文/);assert.doesNotMatch(result,/[\uE006\uE007]/);});
test('regular images keep markdown and lookalike hosts cannot opt into special policy',()=>{for(const host of ['images.example.com','mmbiz.qpic.cn.evil.example']){const result=ctx.clip.toText('<img src="https://'+host+'/photo.jpg" alt="photo">','https://example.com');assert.match(result,/!\[photo\]\(/);assert.doesNotMatch(result,/referrerpolicy/);}});
test('HTML output cannot inject attributes from image alt text',()=>{const result=ctx.clip.toText('<img src="https://mmbiz.qpic.cn/photo.png" alt="&quot; onerror=&quot;alert(1)">','https://mp.weixin.qq.com/s/test');assert.match(result,/alt="&quot; onerror=&quot;alert\(1\)"/);assert.doesNotMatch(result,/alt="" onerror=/);});

test('complete article fetch preserves image policy and text without returning original event handlers',async()=>{
 pageHtml='<html><head><meta property="og:title" content="公众号测试"></head><body><div id="js_content"><p>'+ '文章内容'.repeat(80) +'</p><img data-src="https://mmbiz.qpic.cn/mmbiz_png/fixture/640?wx_fmt=png" alt="图片" onerror="bad()"></div></body></html>';
 const result=await ctx.clip.fetch('https://mp.weixin.qq.com/s/fixture');
 assert.equal(result.ok,true);assert.equal(result.title,'公众号测试');assert.equal(requested,'https://mp.weixin.qq.com/s/fixture');assert.equal(destroyed,1);
 assert.match(result.body,/referrerpolicy="no-referrer"/);assert.doesNotMatch(result.body,/bad\(\)|onerror=/);
});
test('WeChat short lines stay compact with visible hard breaks and structural spacing',()=>{
 const html='<h2>活动</h2><p>本周六将正式开展</p><p>多件国宝大集结</p><p>值得闭眼冲</p><img src="https://mmbiz.qpic.cn/photo.png"><p>时间：周六</p><p>地点：昆山</p><ul><li>第一项</li><li>第二项</li></ul><pre><code>a\nb</code></pre>';
 const body=ctx.clip.toText(html,'https://mp.weixin.qq.com/s/test');
 assert.match(body,/## 活动\n\n本周六将正式开展  \n多件国宝大集结  \n值得闭眼冲\n\n<img/);
 assert.match(body,/时间：周六  \n地点：昆山\n\n- 第一项\n- 第二项/);
 assert.match(body,/```\na\nb\n```/);
 assert.doesNotMatch(body,/[\uE000-\uE00F]/);
});
test('linked WeChat image stays separate from following text without wrapping protected HTML as link text',()=>{
 const body=ctx.clip.toText('<a href="https://mp.weixin.qq.com/album"><img src="https://mmbiz.qpic.cn/photo.png" alt="图"></a><p>后文</p>','https://mp.weixin.qq.com/s/test');
 assert.match(body, /^<img[^>]+\/>\n\n后文$/);
 assert.doesNotMatch(body, /\[<img|[\uE006\uE007]/);
});
test('ordinary article paragraph separation is unchanged',()=>{
 assert.equal(ctx.clip.toText('<p>第一段</p><p>第二段</p>','https://example.com/article'),'第一段\n\n第二段');
});
test('mixed image output preserves existing 24 image budget',()=>{
 const html=Array.from({length:30},(_,i)=>'<img src="https://'+(i%2?'images.example':'mmbiz.qpic.cn')+'/photo'+i+'.png" alt="'+i+'">').join('');
 const body=ctx.clip.toText(html,'https://mp.weixin.qq.com/s/test');
 assert.equal((body.match(/referrerpolicy=/g)||[]).length,12);assert.equal((body.match(/!\[/g)||[]).length,12);assert.doesNotMatch(body,/[\uE006\uE007]/);
});
