import { webview } from '@kit.ArkWeb';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { requestAppPermissionsOnce } from '../common/AppPermissions';
import { getStatusbarHeightVp } from '../common/SafeArea';
import { LanShareApi, LanShareStatus } from '../common/LanShareApi';
import { VipService } from '../common/VipService';

// 本地模式全屏壳：ignis server 就在本机 6791，无需登录/Basic Auth
// 沉浸式：无返回键/无日志面板，切模式靠网页内悬浮球 ‹（对齐 VPS 模式）
@Entry
@Component
struct LocalWeb {
  private webController: webview.WebviewController = new webview.WebviewController();
  private url: string = 'http://127.0.0.1:6791';
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;
  // 状态栏高度(vp)：横屏平板时钟会压住 Obsidian 顶部UI(issue#1)，Web 从状态栏下开始布局
  @State private sbH: number = 0;

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    getStatusbarHeightVp(ctx).then((h: number) => { this.sbH = h; });
    // 伺服器面板依赖的持久键（与 LanServerPage 幂等共持）
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    PersistentStorage.persistProp('lanSharePort', 0);
  }

  // ── 伺服器面板：状态回推（网页侧 __vtSrvSync 渲染）──
  private pushSrvState(): void {
    LanShareApi.status().then((st: LanShareStatus | null) => {
      let js: string;
      if (st !== null && st.running) {
        js = '{running:true,addr:"' + LanShareApi.fullAddr(st) + '",user:"' + st.user + '",vip:' + VipService.isVip() + '}';
      } else {
        const u = AppStorage.get<string>('lanShareUser') ?? '';
        js = '{running:false,addr:"",user:"' + u + '",vip:' + VipService.isVip() + '}';
      }
      this.webController.runJavaScript('window.__vtSrvState=' + js + ';window.__vtSrvSync&&window.__vtSrvSync();');
      AppStorage.setOrCreate('srvRunning', st !== null && st.running);
    });
  }

  // 会话开关也要保活（DATA_TRANSFER）：熄屏不断线；关/退出即停
  private async srvKeepAlive(on: boolean): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (on) {
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
          operationType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0
        });
        await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(ctx);
      }
    } catch (e) {
      const err = e as BusinessError;
      console.error('[lan-panel] keepalive ' + on + ' failed: ' + err.code);
    }
  }

  onBackPress(): boolean {
    console.info('[LocalWeb] onBackPress fired');
    const now = Date.now();
    // 防抖：一次左滑多次触发，500ms 内只处理一次
    if (now - this.lastBackTime < 500) {
      return true;
    }
    this.lastBackTime = now;
    // ★ 死页兜底（对齐 Index）：JS 探测回调 400ms 不来（Web 未就绪/回调异常）→
    //   直接走退出流程。否则探测链路一断，侧划彻底无反应（issue 用户反馈场景）
    let probeAnswered: boolean = false;
    setTimeout(() => {
      if (!probeAnswered) {
        this.exitFlow();
      }
    }, 400);
    // 有弹窗/面板 → Esc 关闭；主页无弹窗 → 双击退出
    this.webController.runJavaScript(
      "(function(){var h=document.querySelector('.modal-container,.modal-bg,.modal,.suggestion-container,.suggestion,.menu,.prompt,.dropdown-menu,.notice');if(h){var o={key:'Escape',code:'Escape',keyCode:27,which:27,bubbles:true,cancelable:true};document.dispatchEvent(new KeyboardEvent('keydown',o));document.dispatchEvent(new KeyboardEvent('keyup',o));return '1';}return '0';})()",
      (err: BusinessError, result: string) => {
        probeAnswered = true;
        if (err) {
          console.error('[LocalWeb] probe error: ' + JSON.stringify(err));
        }
        // result 回传格式在不同版本不稳定（'0' / '"0"' / 0）——规范化后再判断
        const ans = String(result ?? '').replace(/["']/g, '').trim();
        console.info('[LocalWeb] probe ans=' + ans);
        if (ans === '0') {
          this.exitFlow();
        }
      }
    );
    return true;
  }

  // 双击退出流程（Esc 探测无弹窗 / 死页兜底 共用）
  private exitFlow(): void {
    const t = Date.now();
    if (t - this.exitTime < 2000) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.terminateSelf();
    } else {
      this.exitTime = t;
      this.getUIContext().getPromptAction().showToast({ message: '再按一次退出', duration: 2000 });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Blank().height(this.sbH)
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
          // 注入伺服器面板（悬浮球第三按钮 ◉/○ 点击弹出：会话开关+地址复制+账密设置）
          this.webController.runJavaScript(`(function(){if(window.__vtSrvP)return;window.__vtSrvP=1;var S=window.__vtSrvState||{running:false,addr:'',user:'',vip:false};var mask=null,panel=null;function ensurePanel(){if(mask)return;mask=document.createElement('div');mask.id='vt-srv-mask';mask.style.cssText='position:fixed;left:0;top:0;right:0;bottom:0;background:rgba(10,10,30,0.55);z-index:2147483640;display:none;';panel=document.createElement('div');panel.id='vt-srv-panel';panel.style.cssText='position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:86vw;max-width:330px;background:#FFFFFF;border-radius:18px;padding:20px 18px;z-index:2147483641;font-family:system-ui,-apple-system,sans-serif;box-shadow:0 12px 40px rgba(0,0,0,0.35);box-sizing:border-box;';document.body.appendChild(mask);document.body.appendChild(panel);tap(mask,close);panel.addEventListener('pointerup',function(e){e.stopPropagation();});panel.addEventListener('click',function(e){e.stopPropagation();});}function close(){if(mask)mask.style.display='none';}window.__vtSrvPanel=function(){ensurePanel();render();mask.style.display='block';};window.__vtSrvSync=function(){S=window.__vtSrvState||S;var b=document.getElementById('vt-c');if(b){b.textContent=S.running?'\u25C9':'\u25CB';b.style.color=S.running?'#9BE8B4':'#8F9BD8';}if(mask&&mask.style.display==='block')render();};function h(txt,color,size,wt){var e=document.createElement('div');e.textContent=txt;e.style.cssText='color:'+(color||'#333')+';font-size:'+(size||13)+'px;font-weight:'+(wt||'400')+';line-height:1.5;margin:2px 0;';return e;}function tap(el,fn){el.addEventListener('pointerup',function(ev){ev.stopPropagation();ev.preventDefault();fn();});el.addEventListener('click',function(ev){ev.preventDefault();ev.stopPropagation();});}function btn(txt,bg,cb,small){var e=document.createElement('button');e.textContent=txt;e.type='button';e.style.cssText='display:block;width:100%;border:0;border-radius:'+(small?10:12)+'px;padding:'+(small?'8px':'11px')+' 0;font-size:'+(small?13:15)+'px;font-weight:600;color:#fff;background:'+bg+';margin-top:8px;cursor:pointer;text-align:center;font-family:inherit;';tap(e,cb);return e;}function render(){panel.innerHTML='';var head=document.createElement('div');head.style.cssText='display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;';var ti=h('\u4F3A\u670D\u5668','#1E2150',17,'700');head.appendChild(ti);var x=document.createElement('div');x.textContent='\u00D7';x.type='button';x.style.cssText='font-size:24px;color:#9AA3D8;cursor:pointer;padding:0 6px;line-height:1;';tap(x,close);head.appendChild(x);panel.appendChild(head);if(S.running){panel.appendChild(h('\u25CF \u8FD0\u884C\u4E2D','#1F8A4C',13,'600'));var addr=h(S.addr||'(\u83B7\u53D6\u5730\u5740\u4E2D...)','#1E2150',18,'700');addr.style.cssText+='word-break:break-all;margin:10px 0 4px;';panel.appendChild(addr);panel.appendChild(h('\u5C40\u57DF\u7F51\u8BBE\u5907\u6D4F\u89C8\u5668\u8F93\u5165\u4E0A\u9762\u5730\u5740\u5373\u53EF\u8BBF\u95EE','#8F9BD8',11));panel.appendChild(btn('\u590D\u5236\u5730\u5740','#5F6BD8',copyAddr));panel.appendChild(btn('\u5173\u95ED\u4F3A\u670D\u5668','#B8BDD8',function(){location.href='vitreus://srv-toggle';},true));}else if(S.vip){panel.appendChild(h('\u25CB \u5DF2\u505C\u6B62','#8F9BD8',13));if(S.user){panel.appendChild(h('\u8D26\u53F7\uFF1A'+S.user+'\uFF08Digest \u52A0\u5BC6\uFF0C\u5BC6\u7801\u4E0D\u4E0A\u7EBF\uFF09','#8F9BD8',11));panel.appendChild(btn('\u5F00\u542F\u4F3A\u670D\u5668','#5F6BD8',function(){location.href='vitreus://srv-toggle';}));}else{panel.appendChild(h('\u9996\u6B21\u5F00\u542F\u9700\u8BBE\u7F6E\u8BBF\u95EE\u8D26\u53F7\u5BC6\u7801','#8F9BD8',12));var iu=document.createElement('input');iu.id='vt-srv-u';iu.placeholder='\u8D26\u53F7';iu.style.cssText='width:100%;box-sizing:border-box;border:1px solid #D8DCF2;border-radius:10px;padding:10px;font-size:14px;margin-top:8px;outline:none;';var ip=document.createElement('input');ip.id='vt-srv-p';ip.type='password';ip.placeholder='\u5BC6\u7801\uFF08\u81F3\u5C114\u4F4D\uFF09';ip.style.cssText=iu.style.cssText;panel.appendChild(iu);panel.appendChild(ip);panel.appendChild(btn('\u4FDD\u5B58\u5E76\u5F00\u542F','#5F6BD8',function(){var u=(document.getElementById('vt-srv-u').value||'').trim();var p=document.getElementById('vt-srv-p').value||'';if(!u||p.length<4){alert('\u8BF7\u586B\u8D26\u53F7\u548C\u81F3\u5C114\u4F4D\u5BC6\u7801');return;}location.href='vitreus://srv-cred?u='+encodeURIComponent(u)+'&p='+encodeURIComponent(p);}));}}else{panel.appendChild(h('\u4F3A\u670D\u5668\u6A21\u5F0F\u662F Vitreus \u4F1A\u5458\u529F\u80FD','#1E2150',14,'600'));panel.appendChild(h('\u7184\u5C4F\u5728\u7EBF\uFF0C\u5C40\u57DF\u7F51\u8BBE\u5907\u6D4F\u89C8\u5668\u76F4\u8FDE\u3002','#8F9BD8',12));panel.appendChild(btn('\u4E86\u89E3\u4F1A\u5458','#5F6BD8',function(){close();location.href='vitreus://srv-buy';}));}panel.appendChild(h('\u4EC5\u672C\u6B21\u6709\u6548\uFF08App \u9000\u51FA\u5373\u505C\uFF09\u00B7 Digest \u52A0\u5BC6\u00B7 \u5185\u7F51\u4F20\u8F93','#B4BACF',10));}function copyAddr(){var t=S.addr||'';if(!t)return;function fb(){var ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();try{document.execCommand('copy');}catch(e){}document.body.removeChild(ta);}try{navigator.clipboard.writeText(t).then(function(){},fb);}catch(e){fb();}var b=h('\u5DF2\u590D\u5236','#1F8A4C',12);b.style.cssText+='text-align:center;margin-top:4px;';panel.appendChild(b);setTimeout(function(){if(b.parentNode)b.parentNode.removeChild(b);},1500);}})();`);
          // 初始状态回推（面板/按钮图标就位后）
          setTimeout(() => { this.pushSrvState(); }, 600);
          // 注入悬浮球：‹ 左箭头（与返回键统一），点击回模式选择（vitreus://switch → ModeSelect）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(20,20,60,0.92);color:#fff;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.textContent='\u27F3';b.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(250,247,241,0.95);color:#1E2150;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);var sv=document.createElement('div');sv.id='vt-c';var svOn=window.__vtSrvState&&window.__vtSrvState.running;sv.textContent=svOn?'\u25C9':'\u25CB';sv.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(20,20,60,0.92);color:'+(svOn?'#9BE8B4':'#8F9BD8')+';font-size:18px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(sv);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top=(window.innerHeight/2-22)+'px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else if(t==='vt-c'){if(window.__vtSrvPanel)window.__vtSrvPanel();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},2000);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},3000);})();`);
        })
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              AppStorage.setOrCreate('navBack', true); router.replaceUrl({ url: 'pages/ModeSelect' }); setTimeout(() => { AppStorage.setOrCreate('navBack', false); }, 600);
            } else if (url.includes('srv-cred')) {
              // 面板内首次设置账密：存凭证 + enable + 回推
              const qi = url.indexOf('?');
              const q = qi >= 0 ? url.substring(qi + 1) : '';
              const um = q.match(/(?:^|&)u=([^&]*)/);
              const pm = q.match(/(?:^|&)p=([^&]*)/);
              const cu = um !== null ? um[1] : '';
              const cp = pm !== null ? pm[1] : '';
              const u = cu !== '' ? decodeURIComponent(cu) : '';
              const p = cp !== '' ? decodeURIComponent(cp) : '';
              if (u !== '' && p.length >= 4) {
                AppStorage.setOrCreate('lanShareUser', u);
                AppStorage.setOrCreate('lanSharePass', p);
                const credPort: number = AppStorage.get<number>('lanSharePort') ?? 0;
                LanShareApi.enable(u, p, credPort).then((st: LanShareStatus | null) => {
                  if (st !== null && st.running) {
                    this.srvKeepAlive(true);
                  }
                  this.pushSrvState();
                });
              }
            } else if (url.includes('srv-toggle')) {
              // 会话开关（不动 srvModeEnabled）：开=enable+保活，关=disable+停保活
              LanShareApi.status().then((st: LanShareStatus | null) => {
                if (st !== null && st.running) {
                  LanShareApi.disable().then(() => {
                    this.srvKeepAlive(false);
                    this.pushSrvState();
                  });
                } else {
                  const tu = AppStorage.get<string>('lanShareUser') ?? '';
                  const tp = AppStorage.get<string>('lanSharePass') ?? '';
                  if (tu !== '' && tp !== '') {
                    const togPort: number = AppStorage.get<number>('lanSharePort') ?? 0;
                    LanShareApi.enable(tu, tp, togPort).then((st2: LanShareStatus | null) => {
                      if (st2 !== null && st2.running) {
                        this.srvKeepAlive(true);
                      }
                      this.pushSrvState();
                    });
                  } else {
                    this.pushSrvState(); // 无凭证：回推后面板显示设置表单
                  }
                }
              });
            } else if (url.includes('srv-buy')) {
              router.pushUrl({ url: 'pages/VipPanelPage' });
            }
            return true;
          }
          return false;
        })
        .width('100%')
        .layoutWeight(1)
      }
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
