import { webview } from '@kit.ArkWeb';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { requestAppPermissionsOnce } from '../common/AppPermissions';
import { getStatusbarHeightVp } from '../common/SafeArea';
import { LanShareApi, LanShareStatus } from '../common/LanShareApi';
import { VipService } from '../common/VipService';
import { SrvSafetyDialog } from '../common/SrvSafetyDialog';

// 本地模式全屏壳：ignis server 就在本机 6791，无需登录/Basic Auth
// 沉浸式：无返回键/无日志面板，切模式靠网页内悬浮球 ‹（对齐 VPS 模式）
@Entry
@Component
struct LocalWeb {
  private webController: webview.WebviewController = new webview.WebviewController();
  private url: string = 'http://127.0.0.1:6791';
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;
  // 伺服器凭证保存流程：安全提示弹窗 + 暂存（srv-cred-form / srv-cred 两入口共用，确认后 confirmSrvCred 落库）
  @State private srvSafetyShow: boolean = false;
  private pendingCredUser: string = '';
  private pendingCredPass: string = '';

  // 安全提示确认后：VIP 门禁自证 + 存凭证 + enable + 回推（原两分支的保存逻辑合并于此，单一事实源）
  private confirmSrvCred(): void {
    if (!VipService.isVip()) {
      this.pushSrvState(); // 非会员：回推面板显示引导分支
      return;
    }
    const u = this.pendingCredUser;
    const p = this.pendingCredPass;
    AppStorage.setOrCreate('lanShareUser', u);
    AppStorage.setOrCreate('lanSharePass', p);
    const port: number = AppStorage.get<number>('lanSharePort') ?? 0;
    LanShareApi.enable(u, p, port).then((st: LanShareStatus | null) => {
      if (st !== null && st.running) {
        AppStorage.setOrCreate('lanSharePort', st.port); // 端口持久：与伺服器模式页共用，地址不漂移
        AppStorage.setOrCreate('srvModeEnabled', true); // 开关语义统一：与伺服器页共用持久标志
        this.srvKeepAlive(true);
      }
      this.pushSrvState();
    });
  }
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
  private lastSrvAddr: string = '';
  private pushSrvState(): void {
    LanShareApi.status().then((st: LanShareStatus | null) => {
      let js: string;
      if (st !== null && st.running) {
        this.lastSrvAddr = LanShareApi.fullAddr(st);
        js = '{running:true,addr:"' + this.lastSrvAddr + '",user:"' + st.user + '",vip:' + VipService.isVip() + '}';
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

  onPageShow() {
    // 从购买页/会员页返回：重推面板状态（VIP 变更后悬浮球按钮与面板文案同步刷新，
    // 否则购买成功后悬浮球仍显示旧状态，须退出本地模式重进才恢复）
    setTimeout(() => { this.pushSrvState(); }, 200);
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
        // issue#1 终态方案：Web 顶进状态栏（主题色自然延伸），状态栏区盖毛玻璃条（替代死板的白/黑底块）
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
          this.webController.runJavaScript(`(function(){if(window.__vtSrvP)return;window.__vtSrvP=1;var S=window.__vtSrvState||{running:false,addr:'',user:'',vip:false};var mask=null,panel=null;var st=document.createElement('style');st.textContent='.vtinput::placeholder{color:#767FBE!important}.vtinput{background:rgba(255,255,255,0.10)!important;border:1px solid rgba(255,255,255,0.25)!important;color:#F0F2FA!important}@keyframes vtbreath{0%,100%{opacity:1;box-shadow:0 0 8px 2px rgba(155,232,180,.55)}50%{opacity:.55;box-shadow:0 0 3px 1px rgba(155,232,180,.25)}}@keyframes vtin{from{opacity:0;transform:translate(-50%,-40%) scale(.78)}to{opacity:1;transform:translate(-50%,-50%) scale(1)}}.vtbtn{transition:transform .12s ease,filter .12s ease}.vtbtn:active{transform:scale(.965);filter:brightness(1.15)}';document.head.appendChild(st);function ensurePanel(){if(mask)return;mask=document.createElement('div');mask.id='vt-srv-mask';mask.style.cssText='position:fixed;left:0;top:0;right:0;bottom:0;background:rgba(8,10,26,0.62);z-index:2147483640;display:none;';panel=document.createElement('div');panel.id='vt-srv-panel';panel.style.cssText='position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:86vw;max-width:330px;background:rgba(34,38,82,0.42);-webkit-backdrop-filter:blur(26px) saturate(1.4);backdrop-filter:blur(26px) saturate(1.4);border:1px solid rgba(255,255,255,0.28);border-radius:20px;padding:22px 20px;z-index:2147483641;font-family:system-ui,-apple-system,sans-serif;box-shadow:0 18px 52px rgba(0,0,0,0.5),inset 0 1px 0 rgba(255,255,255,0.18);box-sizing:border-box;animation:vtin .3s cubic-bezier(.34,1.56,.64,1);';document.body.appendChild(mask);document.body.appendChild(panel);mask._vtcb=close;var frm=document.createElement('iframe');frm.name='vtfrm';frm.setAttribute('style','display:none!important;position:fixed;left:-9999px;top:-9999px;width:0;height:0;border:0;');document.body.appendChild(frm);}function close(){if(mask)mask.style.display='none';if(panel)panel.style.display='none';}window.__vtSrvClose=function(){if(mask)mask.style.display='none';if(panel)panel.style.display='none';};window.__vtSrvPanel=function(){ensurePanel();render();mask.style.display='block';if(panel)panel.style.display='';};window.__vtSrvSync=function(){S=window.__vtSrvState||S;var b=document.getElementById('vt-c');if(b){b.textContent=S.running?'◉':'○';b.style.color=S.running?'#9BE8B4':'#E8EAF4';}if(mask&&mask.style.display==='block')render();};function h(txt,color,size,wt){var e=document.createElement('div');e.textContent=txt;e.style.cssText='color:'+(color||'#AAB4E8')+';font-size:'+(size||13)+'px;font-weight:'+(wt||'400')+';line-height:1.55;margin:2px 0;';return e;}function delegate(ev){var el=ev.target;while(el&&el!==document.body){if(el._vtcb){if(el._vtT&&Date.now()-el._vtT<400)return;el._vtT=Date.now();ev.stopPropagation();ev.preventDefault();el._vtcb();return;}el=el.parentNode;}}document.addEventListener('pointerdown',delegate,true);document.addEventListener('pointerdown',function(ev){var el=ev.target;while(el&&el!==document.body){if(el.className==='vtbtn'){el.style.transform='scale(.93)';el.style.filter='brightness(1.2)';setTimeout(function(){el.style.transform='';el.style.filter='';},320);break;}el=el.parentNode;}},true);document.addEventListener('touchstart',delegate,true);function btn(txt,bg,act,small){var e=document.createElement('a');e.href='vitreus://'+act;e.target='vtfrm';e.textContent=txt;e.className='vtbtn';e.style.cssText='display:flex;align-items:center;justify-content:center;width:100%;height:'+(small?38:46)+'px;border-radius:'+(small?11:13)+'px;font-size:'+(small?13:15)+'px;font-weight:600;color:#fff;background:'+bg+';margin-top:10px;cursor:pointer;font-family:inherit;text-decoration:none;box-shadow:0 6px 18px rgba(95,107,216,.28);';return e;}function render(){panel.innerHTML='';var head=document.createElement('div');head.style.cssText='display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;padding-bottom:10px;border-bottom:1px solid rgba(122,136,232,0.16);';var ti=h('伺服器','#FFFFFF',17,'700');head.appendChild(ti);var x=document.createElement('a');x.href='vitreus://srv-close';x.target='vtfrm';x.className='vtbtn';x.textContent='×';x.style.cssText='font-size:24px;color:#767FBE;cursor:pointer;padding:0 6px;line-height:1;text-decoration:none;';head.appendChild(x);panel.appendChild(head);if(S.running){var dot=document.createElement('span');dot.style.cssText='display:inline-block;width:9px;height:9px;border-radius:50%;background:#9BE8B4;margin-right:7px;animation:vtbreath 1.8s ease-in-out infinite;vertical-align:1px;';var rl=h('',' #1F8A4C',13,'600');rl.insertBefore(dot,rl.firstChild);rl.style.cssText+='margin-top:12px;';panel.appendChild(rl);var addr=h(S.addr||'(获取地址中...)','#9BE8B4',18,'700');addr.style.cssText+='word-break:break-all;margin:12px 0 4px;letter-spacing:.5px;';panel.appendChild(addr);panel.appendChild(h('局域网设备浏览器输入上面地址即可访问','#767FBE',11));panel.appendChild(btn('复制地址','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-copy'));panel.appendChild(btn('关闭伺服器','linear-gradient(90deg,#3A4078,#32375F)','srv-toggle',true));}else if(S.vip){panel.appendChild(h('○ 已停止','#8F9BD8',13,'600'));if(S.user){panel.appendChild(h('账号：'+S.user+'（Digest 加密，密码不上线）','#767FBE',11));panel.appendChild(btn('开启伺服器','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-toggle'));}else{panel.appendChild(h('首次开启需设置访问账号密码','#8F9BD8',12));var iu=document.createElement('input');iu.id='vt-srv-u';iu.placeholder='账号';iu.className='vtinput';iu.style.cssText='width:100%;box-sizing:border-box;border-radius:12px;padding:11px 12px;font-size:14px;margin-top:10px;outline:none;';var ip=document.createElement('input');ip.className='vtinput';ip.id='vt-srv-p';ip.type='password';ip.placeholder='密码（至少4位）';ip.style.cssText=iu.style.cssText;panel.appendChild(iu);panel.appendChild(ip);panel.appendChild(btn('保存并开启','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-cred-form'));}}else{panel.appendChild(h('伺服器模式是 Vitreus 会员功能','#FFFFFF',14,'600'));panel.appendChild(h('熄屏在线，局域网设备浏览器直连。','#8F9BD8',12));panel.appendChild(btn('了解会员','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-buy'));}var ft=h('开关持久保存（重启 App 自动恢复）· Digest 加密· 内网传输','#5A649E',10);ft.style.cssText+='margin-top:14px;padding-top:10px;border-top:1px solid rgba(122,136,232,0.12);';panel.appendChild(ft);}})();`);
          // 初始状态回推（面板/按钮图标就位后）
          setTimeout(() => { this.pushSrvState(); }, 600);
          // 注入悬浮球：‹ 左箭头（与返回键统一），点击回模式选择（vitreus://switch → ModeSelect）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;var fst=document.createElement('style');fst.textContent='@keyframes vtfabB{0%,100%{box-shadow:0 0 12px 3px rgba(155,232,180,.55),0 2px 8px rgba(0,0,0,.3)}50%{box-shadow:0 0 4px 1px rgba(155,232,180,.15),0 2px 8px rgba(0,0,0,.3)}}';document.head.appendChild(fst);function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;white-space:nowrap;flex-wrap:nowrap;max-width:none;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='white-space:nowrap;height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.textContent='\u27F3';b.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);var sv=document.createElement('div');sv.id='vt-c';var svOn=window.__vtSrvState&&window.__vtSrvState.running;sv.textContent=svOn?'\u25C9':'\u25CB';sv.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:'+(svOn?'#9BE8B4':'#E8EAF4')+';font-size:18px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(sv);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.width=W+'px';bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top=(window.innerHeight/2-22)+'px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else if(t==='vt-c'){if(window.__vtSrvPanel)window.__vtSrvPanel();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},2000);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},10000);})();`);
        })
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              AppStorage.setOrCreate('navBack', true); router.replaceUrl({ url: 'pages/ModeSelect' }); setTimeout(() => { AppStorage.setOrCreate('navBack', false); }, 600);
            } else if (url.includes('srv-close')) {
              // 面板关闭（× 按钮导航链路——零网页事件依赖）
              this.webController.runJavaScript('window.__vtSrvClose&&window.__vtSrvClose();');
            } else if (url.includes('srv-copy')) {
              // 复制地址（ArkTS pasteboard，比网页 clipboard 可靠）
              if (this.lastSrvAddr !== '') {
                const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.lastSrvAddr);
                pasteboard.getSystemPasteboard().setData(data).then(() => {
                  this.getUIContext().getPromptAction().showToast({ message: '已复制访问地址', duration: 2000 });
                });
              } else {
                this.getUIContext().getPromptAction().showToast({ message: '伺服器未开启', duration: 1800 });
              }
            } else if (url.includes('srv-cred-form')) {
              // 表单提交：ArkTS 主动读输入框值（零网页事件）
              this.webController.runJavaScript(
                "(document.getElementById('vt-srv-u')?document.getElementById('vt-srv-u').value:'')+'|'+(document.getElementById('vt-srv-p')?document.getElementById('vt-srv-p').value:'')",
                (err: BusinessError, result: string) => {
                  if (err) {
                    return;
                  }
                  const raw = String(result ?? '').replace(/["']/g, '').trim();
                  const sep = raw.indexOf('|');
                  const u = sep >= 0 ? raw.substring(0, sep).trim() : '';
                  const pw = sep >= 0 ? raw.substring(sep + 1).trim() : '';
                  if (u === '' || pw.length < 4) {
                    this.getUIContext().getPromptAction().showToast({ message: '请填账号和至少4位密码', duration: 2000 });
                    return;
                  }
                  // 安全提示前置：暂存凭证，确认后走 confirmSrvCred
                  this.pendingCredUser = u;
                  this.pendingCredPass = pw;
                  this.srvSafetyShow = true;
                });
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
                // 安全提示前置：暂存凭证，确认后走 confirmSrvCred（VIP 门禁在 confirm 内自证）
                this.pendingCredUser = u;
                this.pendingCredPass = p;
                this.srvSafetyShow = true;
              }
            } else if (url.includes('srv-toggle')) {
              // 开关语义统一（原"会话开关不动 srvModeEnabled"导致：本地关→伺服器页巡检按持久标志自动重开=状态鬼魅）：开=enable+保活+标志true，关=disable+停保活+标志false
              LanShareApi.status().then((st: LanShareStatus | null) => {
                if (st !== null && st.running) {
                  LanShareApi.disable().then(() => {
                    AppStorage.setOrCreate('srvModeEnabled', false);
                    this.srvKeepAlive(false);
                    this.pushSrvState();
                  });
                } else {
                  const tu = AppStorage.get<string>('lanShareUser') ?? '';
                  const tp = AppStorage.get<string>('lanSharePass') ?? '';
                  if (tu !== '' && tp !== '' && VipService.isVip()) { // VIP 门禁：订阅过期凭证残留不得复活伺服器
                    const togPort: number = AppStorage.get<number>('lanSharePort') ?? 0;
                    LanShareApi.enable(tu, tp, togPort).then((st2: LanShareStatus | null) => {
                      if (st2 !== null && st2.running) {
                        AppStorage.setOrCreate('lanSharePort', st2.port); // 端口持久：与伺服器模式页共用，地址不漂移
                        AppStorage.setOrCreate('srvModeEnabled', true); // 开关语义统一：与伺服器页共用持久标志
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
              this.webController.runJavaScript('window.__vtSrvClose&&window.__vtSrvClose();');
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


      // 凭证保存安全提示（遮罩层）
      SrvSafetyDialog({
        show: this.srvSafetyShow,
        onConfirm: () => {
          this.srvSafetyShow = false;
          this.confirmSrvCred();
        }
      })
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
