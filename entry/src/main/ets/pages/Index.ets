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
          // 主页：双击退出 app
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
          // 处理 nginx Basic Auth（HTTP 401）：用登录页输入的凭证认证
          event.handler.confirm(this.authUser, this.authPwd);
          return true;
        })
        .onHttpErrorReceive((event) => {
          // 凭证错误（服务器二次返回 401）：跳回登录页重输，避免卡死
          if (this.authRedirecting) {
            return;
          }
          if (event && event.response && event.response.getResponseCode() === 401) {
            this.authRedirecting = true;
            AppStorage.setOrCreate('authFailed', true);
            router.replaceUrl({ url: 'pages/Login' });
          }
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

        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
