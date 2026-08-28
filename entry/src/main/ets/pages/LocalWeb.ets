import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { requestAppPermissionsOnce } from '../common/AppPermissions';

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
        .darkMode(WebDarkMode.Auto)
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
          // 网页加载完成后申请权限（一次启动只弹一轮，与 Index 远程页一致）
          const permCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          requestAppPermissionsOnce(permCtx);
          // 用户反馈：网页内按钮触发的手机振动体验差——覆盖 navigator.vibrate 让页面
          // 认为设备不支持振动（App 原生 Haptics.ets 不走此通道，不受影响）
          this.webController.runJavaScript("(function(){if(window.__vtNoVibe)return;window.__vtNoVibe=1;var off=function(){return false;};try{if(typeof Navigator!=='undefined'&&Navigator.prototype)Object.defineProperty(Navigator.prototype,'vibrate',{value:off,writable:true,configurable:true});}catch(e){}try{navigator.vibrate=off;}catch(e){}})()");
          // 注入悬浮球：‹ 左箭头（与返回键统一），点击回模式选择（vitreus://switch → ModeSelect）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(20,20,60,0.92);color:#fff;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.textContent='\u27F3';b.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(250,247,241,0.95);color:#1E2150;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top=(window.innerHeight/2-22)+'px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},2000);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},3000);})();`);
        })
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              AppStorage.setOrCreate('navBack', true); router.replaceUrl({ url: 'pages/ModeSelect' }); setTimeout(() => { AppStorage.setOrCreate('navBack', false); }, 600);
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
  // 页面转场：进入=淡入+上浮，退出=淡出（全 app 统一节奏）
  // 方向感转场：前进从右滑入（旧页左移淡出）；返回从左回位（旧页向右滑走）
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 200, curve: Curve.EaseOut })
      .translate({ x: 320 })
      .opacity(0.3)
      .translate({ x: 320 })
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
      .opacity(0)
      .translate({ x: -110 })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
      .opacity(0)
  }
}
