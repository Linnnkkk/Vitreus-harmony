import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { BackButton } from '../components/BackButton';
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

  aboutToAppear() {
    this.authRedirecting = false;
    this.authUser = AppStorage.get<string>('authUser') ?? '';
    this.authPwd = AppStorage.get<string>('authPwd') ?? '';
    const serverUrl = AppStorage.get<string>('serverUrl') ?? '';
    if (serverUrl === '') {
      // 没有地址，回登录页填地址
      router.replaceUrl({ url: 'pages/Login' });
      return;
    }
    this.url = serverUrl;
    // 权限申请已前移到 EntryAbility（app 启动即弹，本地/远程模式统一）
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
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: this.url, controller: this.webController })
        .javaScriptAccess(true)
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
          // 网页加载完成后申请权限（一次启动只弹一轮）：此时窗口/页面都稳定，
          // 权限弹窗序列不会被启动期的窗口切换打断
          const permCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          requestAppPermissionsOnce(permCtx);
          // 注入可拖动悬浮球（吸附+入场动画+2秒吸回）；点击 = 回 Login 换地址
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;function init(){if(!document.body||document.getElementById('vt-sw'))return;var b=document.createElement('div');b.id='vt-sw';b.textContent='‹';b.style.cssText='position:fixed;width:40px;height:40px;border-radius:20px;background:rgba(20,20,60,0.62);color:#fff;font-size:28px;text-align:center;line-height:38px;z-index:2147483647;box-shadow:0 2px 8px rgba(0,0,0,0.3);user-select:none;-webkit-user-select:none;touch-action:none;cursor:pointer;transition:left .3s,opacity .3s,top .3s;';document.body.appendChild(b);b.style.left=(window.innerWidth-48)+'px';b.style.top='60px';var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(b.style.left)||0;var cx=cur+20;if(cx<window.innerWidth/2){S.atRight=false;b.style.left='-20px';}else{S.atRight=true;b.style.left=(window.innerWidth-20)+'px';}b.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;b.style.left=S.atRight?(window.innerWidth-48)+'px':'8px';b.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2000);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=b.getBoundingClientRect();b._vx=r.left;b._vy=r.top;b.style.transition='none';b.style.left=r.left+'px';b.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(0,Math.min(window.innerWidth-40,b._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-40,b._vy+dy));b.style.left=nx+'px';b.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;b.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{window.location.href='vitreus://switch';}}else{snap();}}b.addEventListener('mousedown',down);b.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},700);}init();window.__vtGuard=window.__vtGuard||setInterval(function(){if(!document.getElementById('vt-sw'))init();},3000);})();`);
        })

        .width('100%')
        .height('100%')

      // 左上角常驻返回（回模式选择；网页内部返回靠悬浮球/左滑 Esc 逻辑）
      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
