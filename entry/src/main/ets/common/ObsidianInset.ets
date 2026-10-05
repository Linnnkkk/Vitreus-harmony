// Shared ArkWeb injection for desktop Obsidian on PAD-like windows.
// The native side supplies a vp value (0 = no inset needed).
// 关键：不在注入时刻判断“是不是桌面版”——onPageEnd 触发时 Obsidian 还没渲染出 DOM，
// 当时探测 .workspace 必然为空，会误判成非桌面并把边距清零（真机 PAD 无效的根因）。
// 改成纯 CSS 选择器：body 不带 is-mobile 的 .app-container 才下移，DOM 何时出现都生效；
// 手机版 Obsidian（body.is-mobile）不受影响，避免双重空白。
export function getObsidianInsetScript(insetVp: number): string {
  const safe = Math.max(0, Math.round(insetVp));
  const css = safe > 0
    // 不用 padding-top：左上角侧边栏按钮(.sidebar-toggle-button)与 ribbon 角块是
    // position:absolute;top:0，相对 .app-container 的内边距盒定位，padding 推不动它们
    // （真机实测：内容下移了、侧栏按钮还压在状态栏上）。改成整体平移容器本身。
    // .titlebar 是 position:fixed，单独下移。
    ? 'body:not(.is-mobile) .app-container{position:relative!important;top:' + safe + 'px!important;height:calc(100% - ' + safe + 'px)!important;}' +
      'body:not(.is-mobile) .titlebar{top:' + safe + 'px!important;}'
    : '';
  return `(function(){
    var head=document.head||document.documentElement;
    if(!head){return;}
    var style=document.getElementById('vitreus-obsidian-inset');
    if(!style){ style=document.createElement('style'); style.id='vitreus-obsidian-inset'; head.appendChild(style); }
    style.textContent=${JSON.stringify(css)};
    window.__vitreusObsidianInset={inset:${safe},mobile:!!(document.body&&document.body.classList.contains('is-mobile'))};
  })();`;
}
