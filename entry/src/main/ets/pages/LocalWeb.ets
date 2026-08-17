import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';

// 本地模式全屏壳：ignis server 就在本机 6791，无需登录/Basic Auth
// 沉浸式：无返回键/无日志面板，切模式靠网页内悬浮球 ‹（对齐 VPS 模式）
@Entry
@Component
struct LocalWeb {
  private webController: webview.WebviewController = new webview.WebviewController();
  private url: string = 'http://127.0.0.1:6791';
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;

  onBackPress(): boolean {
    const now = Date.now();
    // 防抖：一次左滑多次触发，500ms 内只处理一次
    if (now - this.lastBackTime < 500) {
      return true;
    }
    this.lastBackTime = now;
    // 有弹窗/面板 → Esc 关闭；主页无弹窗 → 双击退出
    this.webController.runJavaScript(
      "(function(){var h=document.querySelector('.modal-container,.modal-bg,.modal,.suggestion-container,.suggestion,.menu,.prompt,.dropdown-menu,.notice');if(h){var o={key:'Escape',code:'Escape',keyCode:27,which:27,bubbles:true,cancelable:true};document.dispatchEvent(new KeyboardEvent('keydown',o));document.dispatchEvent(new KeyboardEvent('keyup',o));return '1';}return '0';})()",
      (err: BusinessError, result: string) => {
        if (result === '0') {
          const t = Date.now();
          if (t - this.exitTime < 2000) {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            ctx.terminateSelf();
          } else {
            this.exitTime = t;
            this.getUIContext().getPromptAction().showToast({ message: '再按一次退出', duration: 2000 });
          }
        }
      }
    );
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: this.url, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .imageAccess(true)
        .mediaPlayGestureAccess(true)
        .fileAccess(true)
        .onPermissionRequest((event: OnPermissionRequestEvent) => {
          if (event) {
            event.request.grant(event.request.getAccessibleResource());
          }
        })
        .onConsole((e: OnConsoleEvent): boolean => {
          console.info('[web:' + e.message.getMessageLevel() + '] ' + e.message.getMessage());
          return false;
        })
        .onErrorReceive((e: OnErrorReceiveEvent) => {
          const req: WebResourceRequest = e.request;
          if (req !== null && req !== undefined) {
            console.info('[web:net-err] ' + req.getRequestUrl() + ' → ' + e.error.getErrorInfo());
          }
        })

        .onPageEnd((event) => {
          // 注入悬浮球：‹ 左箭头（与返回键统一），点击回模式选择（vitreus://switch → ModeSelect）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;function init(){if(!document.body||document.getElementById('vt-sw'))return;var b=document.createElement('div');b.id='vt-sw';b.textContent='‹';b.style.cssText='position:fixed;width:34px;height:34px;border-radius:17px;background:rgba(20,20,60,0.55);color:#fff;font-size:26px;text-align:center;line-height:32px;z-index:2147483647;box-shadow:0 2px 8px rgba(0,0,0,0.3);user-select:none;-webkit-user-select:none;touch-action:none;cursor:pointer;transition:left .3s,opacity .3s,top .3s;';document.body.appendChild(b);b.style.left=(window.innerWidth-46)+'px';b.style.top='60px';var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(b.style.left)||0;var cx=cur+17;if(cx<window.innerWidth/2){S.atRight=false;b.style.left='-24px';}else{S.atRight=true;b.style.left=(window.innerWidth-10)+'px';}b.style.opacity='0.4';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;b.style.left=S.atRight?(window.innerWidth-44)+'px':'10px';b.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2000);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=b.getBoundingClientRect();b._vx=r.left;b._vy=r.top;b.style.transition='none';b.style.left=r.left+'px';b.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(0,Math.min(window.innerWidth-34,b._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-34,b._vy+dy));b.style.left=nx+'px';b.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;b.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{window.location.href='vitreus://switch';}}else{snap();}}b.addEventListener('mousedown',down);b.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},700);}init();window.__vtGuard=window.__vtGuard||setInterval(function(){if(!document.getElementById('vt-sw'))init();},3000);})();`);
        })
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              router.replaceUrl({ url: 'pages/ModeSelect' });
            }
            return true;
          }
          return false;
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
