// Shared ArkWeb injection for desktop Obsidian on PAD-like windows.
// The native side supplies a vp value; the page decides whether it is desktop Obsidian.
export function getObsidianInsetScript(insetVp: number): string {
  const safe = Math.max(0, insetVp);
  return `(function(){
    var inset=${safe};
    var body=document.body;
    var desktop=!!body && !body.classList.contains('is-mobile') &&
      !!document.querySelector('.workspace,.workspace-tab-header-container,.app-container');
    var style=document.getElementById('vitreus-obsidian-inset');
    if(!style){ style=document.createElement('style'); style.id='vitreus-obsidian-inset'; document.head.appendChild(style); }
    style.textContent=desktop ? '.app-container{--vitreus-safe-top:'+inset+'px;padding-top:var(--vitreus-safe-top)!important;box-sizing:border-box!important;}' : '.app-container{--vitreus-safe-top:0px;padding-top:0!important;}';
    window.__vitreusObsidianInset={desktop:desktop,inset:desktop?inset:0};
  })();`;
}
