// obsidian:// 回调投递：插件 OAuth / 登录流程最后常以 obsidian://<action>?k=v 重定向回来。
// Obsidian 前端在 registerUriHook 里把 window.OBS_ACT 绑到协议分发器（1.12.7 / 1.13.7 / 1.14.4 均核对过），
// 传入 {action, ...query} 即可触发插件用 registerObsidianProtocolHandler 注册的处理函数。
// 这里复刻 Obsidian 内部的 URL 解析（obsidian://vault/<库>/<文件> 与 obsidian://<action>?query#hash）。

export function isObsidianUri(url: string): boolean {
  return url.length > 11 && url.substring(0, 11).toLowerCase() === 'obsidian://';
}

// 生成注入主页面执行的脚本，把一条 obsidian:// 地址投递给 Obsidian
export function obsidianUriScript(url: string): string {
  const arg: string = JSON.stringify(url);
  return "(function(u){try{" +
    "var e=u.substr(11),o;" +
    "if(e.indexOf('vault/')===0){var t=e.substr(6).split('/').map(function(x){return decodeURIComponent(x);});o={action:'open',vault:t[0],file:t.slice(1).join('/')};}" +
    "else{var q={},n=e.indexOf('?'),i=e.indexOf('#',Math.max(0,n));" +
    "if(i>=0){q.hash=e.substr(i+1);e=e.substr(0,i);}" +
    "var s='';if(n>=0){s=e.substr(n+1);e=e.substr(0,n);}" +
    "s.split('&').forEach(function(p){if(!p)return;var k=p.indexOf('='),a=k<0?p:p.substr(0,k),v=k<0?null:p.substr(k+1);q[decodeURIComponent(a)]=v!==null?decodeURIComponent(v):'true';});" +
    "while(e.length>0&&e.charAt(e.length-1)==='/'){e=e.substr(0,e.length-1);}" +
    "q.action=e;o=q;}" +
    "if(typeof window.OBS_ACT==='function'){window.OBS_ACT(o);}else{console.log('[vt] OBS_ACT missing');}" +
    "}catch(err){console.log('[vt] obsidian-uri fail '+err);}})(" + arg + ");";
}
