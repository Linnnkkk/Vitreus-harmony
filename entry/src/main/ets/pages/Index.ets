import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { requestAppPermissionsOnce } from '../common/AppPermissions';

@Entry
@Component
struct WebShell {
  private webController: webview.WebviewController = new webview.WebviewController();
  // ★ 改成你的网址 ★
  private url: string = '';
  // Basic Auth 凭证：由登录页（Login）经 AppStorage 传入
  private authUser: string = '';
  private authPwd: string = '';
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;
  @State private authRedirecting: boolean = false;
  // 连接看门狗：非 ignis 地址（如误填 openlist）会白屏且 onPageEnd 不来、
  // 悬浮球注入不进——超时后浮出"重新配置"入口，把用户捞出来
  @State private showRescue: boolean = false;
  private watchdogTimer: number = -1;

  aboutToAppear() {
    this.authRedirecting = false;
    this.showRescue = false;
    this.authUser = AppStorage.get<string>('authUser') ?? '';
    this.authPwd = AppStorage.get<string>('authPwd') ?? '';
    const serverUrl = AppStorage.get<string>('serverUrl') ?? '';
    if (serverUrl === '') {
      // 没有地址，回登录页填地址
      router.replaceUrl({ url: 'pages/Login' });
      return;
    }
    this.url = serverUrl;
    // 看门狗：15s 内没等到 onPageEnd（页面加载失败/非网页服务）→ 浮出救援入口
    this.watchdogTimer = setTimeout(() => {
      this.showRescue = true;
    }, 15000);
    // 权限申请已前移到 EntryAbility（app 启动即弹，本地/远程模式统一）
  }

  aboutToDisappear() {
    if (this.watchdogTimer !== -1) {
      clearTimeout(this.watchdogTimer);
    }
  }

  // ★ 上传修复：media URI（file://media/Photo_xxx）→ 沙箱缓存真实文件
  //   网页 fetch 上传时 media URI 常拿不到内容/文件名（线上服务端校验失败），
  //   拷出来给网页一个可直读的 file:// 真实路径
  private copyToCacheWithRealName(uri: string): string {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const cacheDir = context.cacheDir;
      // 从 URI 提取显示名（Photo_20260817_123456.jpg → 用时间戳保唯一）
      const namePart = uri.split('/').pop() ?? 'upload.jpg';
      const ext = namePart.includes('.') ? namePart.substring(namePart.lastIndexOf('.')) : '.jpg';
      const dst = cacheDir + '/upload_' + Date.now() + ext;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const out = fs.openSync(dst, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const buf = new ArrayBuffer(1024 * 512);
      while (true) {
        const rd = fs.readSync(src.fd, buf);
        if (rd <= 0) { break; }
        fs.writeSync(out.fd, buf, { length: rd });
      }
      fs.closeSync(src);
      fs.closeSync(out);
      console.info('[upload] copied to ' + dst);
      return 'file://' + dst;
    } catch (e) {
      console.error('[upload] copy failed: ' + JSON.stringify(e));
      return '';
    }
  }

  onBackPress(): boolean {
    const now = Date.now();
    // 防抖：一次左滑手势过程会触发多次 onBackPress，500ms 内只处理一次（否则会连退好几级）
    if (now - this.lastBackTime < 500) {
      return true;
    }
    this.lastBackTime = now;
    // ★ 白屏死锁兜底：runJavaScript 依赖网页响应，坏地址下回调可能永不来
    //   （且 toast 双击退出也走不进去）——救援浮层在场时，返回键直接回登录页
    if (this.showRescue) {
      router.replaceUrl({ url: 'pages/Login' });
      return true;
    }
    // 有弹窗/面板（modal/命令面板/菜单等）→ Esc 关闭（返回上一级）；主页无弹窗 → 进入退出流程
    this.webController.runJavaScript(
      "(function(){var h=document.querySelector('.modal-container,.modal-bg,.modal,.suggestion-container,.suggestion,.menu,.prompt,.dropdown-menu,.notice');if(h){var o={key:'Escape',code:'Escape',keyCode:27,which:27,bubbles:true,cancelable:true};document.dispatchEvent(new KeyboardEvent('keydown',o));document.dispatchEvent(new KeyboardEvent('keyup',o));return '1';}return '0';})()",
      (err: BusinessError, result: string) => {
        if (result === '0') {
          // 主页：双击退出（切换模式交给网页内注入的 ⇄ 按钮，两条逻辑分开）
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
    Stack({ alignContent: Alignment.Center }) {
      Web({ src: this.url, controller: this.webController })
        .javaScriptAccess(true)
        .darkMode(WebDarkMode.Auto)
        .domStorageAccess(true)
        .imageAccess(true)
        .mediaPlayGestureAccess(true)
        .geolocationAccess(true)
        .onGeolocationShow((event: OnGeolocationShowEvent) => {
          // 网页请求定位 → 授权（app 自用直接允许；系统层会单独弹位置权限确认框）
          if (event && event.geolocation) {
            event.geolocation.invoke(event.origin, true, true);
          }
        })

        .onHttpAuthRequest((event: OnHttpAuthRequestEvent) => {
          // onHttpAuthRequest：WebView 在服务器要求 HTTP 认证时主动触发（唯一正确信号，不靠死板的 401）
          const user = AppStorage.get<string>('authUser') ?? '';
          const pwd = AppStorage.get<string>('authPwd') ?? '';
          if (user !== '' && pwd !== '') {
            // 有凭证：直接认证
            event.handler.confirm(user, pwd);
            return true;
          }
          // 无凭证：去认证页让用户输（保险箱会 AutoFill 账号）；authRedirecting 防重复跳
          if (!this.authRedirecting) {
            this.authRedirecting = true;
            router.replaceUrl({ url: 'pages/AuthPage' });
          }
          return false;
        })
        .onHttpErrorReceive((event) => {
          // 认证流程由 onHttpAuthRequest 统一驱动，这里不再拦截 401（避免死板判断/重复跳转）
        })

        .onShowFileSelector((event: OnShowFileSelectorEvent) => {
          const fileSelectorResult: FileSelectorResult = event.result;

          try {
            // 相册选图（Obsidian 上传主场景；本 SDK 的 event 无 accept 字段可分流，
            // 非图片附件后续有需求再走 DocumentViewPicker 方案）
            const photoSelectOptions = new picker.PhotoSelectOptions();
            photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
            photoSelectOptions.maxSelectNumber = 1;
            const photoPicker = new picker.PhotoViewPicker();
            photoPicker.select(photoSelectOptions).then((result: picker.PhotoSelectResult) => {
              if (result && result.photoUris && result.photoUris.length > 0) {
                // ★ 关键修复：photoUri 是 file://media/Photo_*.jpg 形态，网页 fetch 上传
                //   常拿不到真实内容/文件名（线上服务端校验失败）。拷到沙箱缓存
                //   改成真实文件名，网页拿到的是可直接读的文件
                const copied = this.copyToCacheWithRealName(result.photoUris[0]);
                fileSelectorResult.handleFileList(copied !== '' ? [copied] : result.photoUris);
              } else {
                fileSelectorResult.handleFileList([]);
              }
            }).catch((err: BusinessError) => {
              console.error('图片选择失败:', JSON.stringify(err));
              fileSelectorResult.handleFileList([]);
            });
          } catch (err) {
            console.error('Picker异常:', JSON.stringify(err));
            fileSelectorResult.handleFileList([]);
          }

          return true;
        })

        .onPermissionRequest((event: OnPermissionRequestEvent) => {
          if (event) {
            event.request.grant(event.request.getAccessibleResource());
          }
        })
        .onLoadIntercept((event) => {
          // 拦截悬浮球触发的 vitreus://switch → 回 Login 换服务器地址
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              router.replaceUrl({ url: 'pages/Login' });
            }
            return true;
          }
          return false;
        })
        .onPageEnd((event) => {
          // onPageEnd 到达 = 页面真实加载完成 → 撤销看门狗（正常路径不出救援 UI）
          if (this.watchdogTimer !== -1) {
            clearTimeout(this.watchdogTimer);
            this.watchdogTimer = -1;
          }
          this.showRescue = false;
          // 网页加载完成后申请权限（一次启动只弹一轮）：此时窗口/页面都稳定，
          // 权限弹窗序列不会被启动期的窗口切换打断
          const permCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          requestAppPermissionsOnce(permCtx);
          // 注入可拖动悬浮球（吸附+入场动画+2秒吸回）；点击 = 回 Login 换地址
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(20,20,60,0.92);color:#fff;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.textContent='\u27F3';b.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(250,247,241,0.95);color:#1E2150;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top='60px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},700);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},3000);})();`);
        })

        .width('100%')
        .height('100%')

      // ── 救援浮层：连接看门狗超时（地址不可达/非 ignis 服务/白屏）时浮出，
      //    给用户一条活路回登录页重填地址——否则只能卸载重装 ──
      if (this.showRescue) {
        Column({ space: 10 }) {
          Text('无法连接服务器')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text('地址可能填写有误，或服务未启动')
            .fontSize(12)
            .fontColor('#9AA3D8')
          Text(this.url)
            .fontSize(12)
            .fontColor('#7A85C4')
            .maxLines(1)
            .width('80%')
            .textAlign(TextAlign.Center)
          Button('重新配置地址')
            .width('70%')
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#4F5AC8')
            .fontColor(Color.White)
            .borderRadius(12)
            .margin({ top: 10 })
            .onClick(() => {
              router.replaceUrl({ url: 'pages/Login' });
            })
          Text('继续等待')
            .fontSize(13)
            .fontColor('#7A85C4')
            .padding({ top: 6, bottom: 6 })
            .onClick(() => {
              // 网络慢的场景：关掉浮层再等一轮（悬浮球若已注入仍可用）
              this.showRescue = false;
              this.watchdogTimer = setTimeout(() => {
                this.showRescue = true;
              }, 15000);
            })
        }
        .width('78%')
        .padding({ left: 24, right: 24, top: 28, bottom: 26 })
        .backgroundColor('#1A1E4A')
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })
        .alignItems(HorizontalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
          .animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  // 页面转场：进入=淡入+上浮，退出=淡出（全 app 统一节奏）
  pageTransition() {
    PageTransitionEnter({ duration: 260, curve: Curve.EaseOut })
      .translate({ y: 24 })
      .opacity(0)
    PageTransitionExit({ duration: 180, curve: Curve.EaseIn })
      .opacity(0)
  }
}
