import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';

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
      // 没有地址，回模式选择页
      router.replaceUrl({ url: 'pages/ModeSelect' });
      return;
    }
    this.url = serverUrl;
    this.requestPermissions();
  }

  async requestPermissions() {
    const permissions: Permissions[] = [
      'ohos.permission.CAMERA',
      'ohos.permission.READ_IMAGEVIDEO',
      'ohos.permission.WRITE_IMAGEVIDEO',
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext(this) as common.UIAbilityContext;
      await atManager.requestPermissionsFromUser(context, permissions);
    } catch (err) {
      console.error('权限申请失败:', JSON.stringify(err));
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
    Stack() {
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
            const photoSelectOptions = new picker.PhotoSelectOptions();
            photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
            photoSelectOptions.maxSelectNumber = 1;
            const photoPicker = new picker.PhotoViewPicker();

            photoPicker.select(photoSelectOptions).then((result: picker.PhotoSelectResult) => {
              if (result && result.photoUris && result.photoUris.length > 0) {
                fileSelectorResult.handleFileList(result.photoUris);
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
          // 拦截网页按钮触发的 vitreus:// 自定义协议 → 切换模式（return true 取消导航，不影响 Obsidian）
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url.includes('switch')) {
              router.replaceUrl({ url: 'pages/ModeSelect' });
            }
            return true;
          }
          return false;
        })
        .onPageEnd((event) => {
          // 页面加载完，把切换按钮注入到网页 DOM（成为网页一部分，不被原生层盖；定时检查防被清）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;function init(){if(!document.body||document.getElementById('vt-sw'))return;var b=document.createElement('div');b.id='vt-sw';b.textContent='⇄';b.style.cssText='position:fixed;width:34px;height:34px;border-radius:17px;background:rgba(20,20,60,0.55);color:#fff;font-size:18px;text-align:center;line-height:34px;z-index:2147483647;box-shadow:0 2px 8px rgba(0,0,0,0.3);user-select:none;-webkit-user-select:none;touch-action:none;cursor:pointer;transition:left .3s,opacity .3s,top .3s;';document.body.appendChild(b);b.style.left=(window.innerWidth-46)+'px';b.style.top='60px';var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(b.style.left)||0;var cx=cur+17;if(cx<window.innerWidth/2){S.atRight=false;b.style.left='-24px';}else{S.atRight=true;b.style.left=(window.innerWidth-10)+'px';}b.style.opacity='0.4';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;b.style.left=S.atRight?(window.innerWidth-44)+'px':'10px';b.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2000);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=b.getBoundingClientRect();b._vx=r.left;b._vy=r.top;b.style.transition='none';b.style.left=r.left+'px';b.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(0,Math.min(window.innerWidth-34,b._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-34,b._vy+dy));b.style.left=nx+'px';b.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;b.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{window.location.href='vitreus://switch';}}else{snap();}}b.addEventListener('mousedown',down);b.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},700);}init();window.__vtGuard=window.__vtGuard||setInterval(function(){if(!document.getElementById('vt-sw'))init();},3000);})();`);
        })

        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
