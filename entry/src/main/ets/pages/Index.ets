import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { ensurePermissions, LOCATION_PERMISSIONS } from '../common/AppPermissions';
import { getStatusbarHeightVp } from '../common/SafeArea';
import { WebPopupSheet } from '../common/WebPopupSheet';
import { isObsidianUri, obsidianUriScript } from '../common/ObsidianUri';
import { getObsidianInsetScript } from '../common/ObsidianInset';
import { RemoteCredentialStore, RemoteCredential } from '../common/RemoteCredentialStore';
import { RemoteServerSettings } from '../common/RemoteServerSettings';

class RemoteClipBridge {
  handler: (id: number) => void = (_id: number): void => {};
  read(id: number): void { this.handler(id); }
}

@Entry
@Component
struct WebShell {
  private webController: webview.WebviewController = new webview.WebviewController();
  private remoteClipBridge: RemoteClipBridge = new RemoteClipBridge();
  // ★ 改成你的网址 ★
  private url: string = '';
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;
  @State private authPrompt: boolean = false;
  @State private authInputUser: string = '';
  @State private authInputPwd: string = '';
  @State private pageLoading: boolean = true;
  // 页面上的自检结果（截图即可核实，不依赖日志工具）
  private authAttempted: boolean = false;
  private leaving: boolean = false;
  private authConfirm: (user: string, pwd: string) => void = (_user: string, _pwd: string): void => {};
  private authCancel: () => void = (): void => {};

  private credential: RemoteCredential | undefined = undefined;
  private credentialLoad: Promise<void> = Promise.resolve();
  private credentialEpoch: number = 0;
  // 缓存分区：服务器 + 非明文账号标签。账号未知时为空 → 注入脚本直接不启用缓存，
  // 宁可慢，也不让同一服务器上的两个账号共用一份插件缓存。
  private authEpoch: number = 0;
  private authDocumentUrl: string = '';
  private pendingAuthHost: string = '';
  @State private authSaving: boolean = false;

  private authOrigin(value: string): string {
    const match = value.match(/^(https?):\/\/(\[[^\]]+\]|[^/:?#@]+)(?::(\d+))?(?:[/?#]|$)/i);
    if (!match) { return ''; }
    const scheme = match[1].toLowerCase();
    const port = match[3] || (scheme === 'https' ? '443' : '80');
    return scheme + '://' + match[2].toLowerCase() + ':' + port;
  }

  private trustedAuthHost(host: string): boolean {
    const trusted = this.authOrigin(this.url);
    let current = this.authDocumentUrl;
    try {
      const controllerUrl = this.webController.getUrl();
      if (controllerUrl !== '' && controllerUrl !== 'about:blank') { current = controllerUrl; }
    } catch (e) { /* 初始挑战时控制器可能尚无 URL，使用主文档请求地址 */ }
    if (trusted === '' || this.authOrigin(current) !== trusted || this.authOrigin(this.authDocumentUrl) !== trusted) { return false; }
    const authority = trusted.substring(trusted.indexOf('://') + 3);
    const hostname = authority.replace(/:\d+$/, '');
    // ArkWeb 有时只给 hostname；此时用主文档当前 origin 补齐 scheme/port。
    // 若挑战给了端口，则必须与服务器有效端口严格一致。
    const challenge = host.toLowerCase();
    return challenge === hostname || challenge === authority;
  }

  private async resolveAuth(epoch: number, host: string): Promise<void> {
    await this.credentialLoad;
    if (!this.pageAlive || this.leaving || epoch !== this.authEpoch) { return; }
    if (!this.trustedAuthHost(host)) { this.authCancel(); return; }
    const user = this.credential?.user ?? '';
    const pwd = this.credential?.pwd ?? '';
    if (!this.authAttempted && (user !== '' || pwd !== '')) {
      this.authAttempted = true;
      this.authConfirm(user, pwd);
      this.authCancel = (): void => {};
      this.authConfirm = (_user: string, _pwd: string): void => {};
      this.watchdogTimer = setTimeout(() => { if (this.pageAlive) { this.showRescue = true; } }, 15000);
      return;
    }
    this.authInputUser = user;
    this.authInputPwd = '';
    this.authPrompt = true;
  }

  private async submitAuth(): Promise<void> {
    if (this.authInputUser.trim() === '' || this.authInputPwd === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入账号和密码' });
      return;
    }
    if (this.authSaving) { return; }
    const epoch = this.authEpoch;
    const server = this.url;
    const user = this.authInputUser.trim();
    const pwd = this.authInputPwd;
    this.authSaving = true;
    let saved: boolean = false;
    try { saved = await RemoteCredentialStore.save(server, user, pwd); } catch (e) { saved = false; }
    this.authSaving = false;
    if (!this.pageAlive || this.leaving || epoch !== this.authEpoch) { return; }
    if (!saved) {
      this.getUIContext().getPromptAction().showToast({ message: '凭据保存失败，尚未连接，请重试' });
      return;
    }
    if (!this.trustedAuthHost(this.pendingAuthHost)) { this.authCancel(); this.authPrompt = false; return; }
    this.credential = { server: server, user: user, pwd: pwd };
    this.authAttempted = true;
    this.authConfirm(user, pwd);
    this.authCancel = (): void => {};
    this.authConfirm = (_user: string, _pwd: string): void => {};
    this.authInputPwd = '';
    this.authPrompt = false;
    this.showRescue = false;
    this.watchdogTimer = setTimeout(() => { if (this.pageAlive) { this.showRescue = true; } }, 15000);
  }

  private returnToLogin(): void {
    if (this.leaving || !this.pageAlive) { return; }
    this.leaving = true;
    this.authCancel();
    this.authCancel = (): void => {};
    this.authConfirm = (_user: string, _pwd: string): void => {};
    this.authPrompt = false;
    // Login push Index：必须 pop 到原地址页，不能 replace 出第二个 Login。
    if (router.getStateByUrl('pages/Login').length > 0) {
      router.back({ url: 'pages/Login' });
    } else {
      router.replaceUrl({ url: 'pages/Login' });
    }
  }
  // 状态栏高度(vp)：横屏平板时钟会压住 Obsidian 顶部UI(issue#1)，Web 从状态栏下开始布局
  @State private sbH: number = 0;
  private refreshSafeArea(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    getStatusbarHeightVp(ctx).then((h: number) => {
      this.sbH = h;
      this.safeRun(getObsidianInsetScript(h));
    });
  }

  // 页面已销毁标志：延迟任务/异步回调落到已销毁的 Web 上，runJavaScript 会抛
  // "WebviewController must be associated with a Web component"，在定时器里是未捕获异常，直接闪退
  private pageAlive: boolean = true;
  private safeRun(js: string): void {
    if (!this.pageAlive) {
      return;
    }
    try {
      this.webController.runJavaScript(js);
    } catch (e) {
      // Web 组件已解绑，忽略
    }
  }

  private async readRemoteClipboard(id: number): Promise<void> {
    const origin = (value: string): string => {
      const match = value.match(/^https?:\/\/[^/]+/i);
      return match ? match[0].toLowerCase() : '';
    };
    const trusted = origin(this.url);
    if (!this.pageAlive || trusted === '' || origin(this.webController.getUrl()) !== trusted) {
      return;
    }
    let text: string = '';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await ensurePermissions(ctx, ['ohos.permission.READ_PASTEBOARD'])) {
        text = (await pasteboard.getSystemPasteboard().getData()).getPrimaryText() ?? '';
      }
    } catch (err) {
      console.error('[VtClipRemote] read failed: ' + JSON.stringify(err));
    }
    if (this.pageAlive && origin(this.webController.getUrl()) === trusted) {
      this.safeRun('window.__vtRemoteClipDone&&window.__vtRemoteClipDone(' + id.toString() + ',' + JSON.stringify(text) + ')');
    }
  }

  private injectObsidianInset(): void {
    // 立即注入 + 延迟补注：Obsidian 启动期可能重建 head，样式被冲掉时再补一次
    const run = () => { this.safeRun(getObsidianInsetScript(this.sbH)); };
    run();
    setTimeout(run, 1500);
    setTimeout(run, 4000);
  }

  // 连接看门狗：非 ignis 地址（如误填 openlist）会白屏且 onPageEnd 不来、
  // 悬浮球注入不进——超时后浮出"重新配置"入口，把用户捞出来
  @State private showRescue: boolean = false;
  // 主文档加载失败标记：错误页也会触发 onPageEnd，用它防止误清救援
  @State private mainFrameFailed: boolean = false;
  private watchdogTimer: number = -1;
  private loadStartedAt: number = 0;
  // 网页弹窗（window.open / OAuth）：Custom Frames 等插件会在 iframe 里弹登录窗，
  // ArkWeb 宿主必须接住（不接=渲染进程阻塞、点击无响应）。issue#3
  @State private popupShow: boolean = false;
  @State private popupHost: string = '';
  @State private popupEpoch: number = 0;
  private popupCtrl: webview.WebviewController = new webview.WebviewController();

  aboutToAppear() {
    this.remoteClipBridge.handler = (id: number): void => { this.readRemoteClipboard(id); };
    // 放行 iframe 第三方 cookie：Custom Frames 等插件嵌的站点（百度/Google）登录依赖
    // 3P cookie，内核默认不发不收导致"请开启cookie"无法登录（issue#3）
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    this.refreshSafeArea();
    this.pageAlive = true;
    this.leaving = false;
    this.authAttempted = false;
    this.authPrompt = false;
    this.pageLoading = true;
    this.showRescue = false;
    this.mainFrameFailed = false;
    const serverUrl = AppStorage.get<string>('serverUrl') ?? '';
    if (serverUrl === '') {
      // 没有地址，回登录页填地址
      this.returnToLogin();
      return;
    }
    this.url = serverUrl;
    this.authDocumentUrl = serverUrl;
    this.credential = undefined;
    const credentialEpoch = ++this.credentialEpoch;
    this.credentialLoad = RemoteCredentialStore.load(serverUrl).then((credential: RemoteCredential | undefined): void => {
      if (this.pageAlive && credentialEpoch === this.credentialEpoch && this.url === serverUrl) {
        this.credential = credential;
      }
    }).catch((): void => {});
    this.loadStartedAt = Date.now();

    console.info('[remote-load] Web mounted');
    // 看门狗：15s 内没等到 onPageEnd（页面加载失败/非网页服务）→ 浮出救援入口
    this.watchdogTimer = setTimeout(() => {
      this.showRescue = true;
    }, 15000);
    // 权限申请已前移到 EntryAbility（app 启动即弹，本地/远程模式统一）
  }

  aboutToDisappear() {
    this.pageAlive = false;
    this.credentialEpoch += 1;
    this.authEpoch += 1;
    this.credential = undefined;
    this.authCancel();
    this.authConfirm = (_user: string, _pwd: string): void => {};
    this.authCancel = (): void => {};
    this.authInputPwd = '';
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

  // 重定向回调：把 obsidian://… 投递给主页面的 Obsidian（window.OBS_ACT），并收起弹窗
  private deliverObsidianUri(url: string): void {
    console.info('[popup] deliver obsidian uri: ' + url.substring(0, 80));
    this.webController.runJavaScript(obsidianUriScript(url));
    this.popupShow = false;
  }

  onBackPress(): boolean {
    console.info('[Index] onBackPress fired');
    const now = Date.now();
    // 防抖：一次左滑手势过程会触发多次 onBackPress，500ms 内只处理一次（否则会连退好几级）
    if (now - this.lastBackTime < 500) {
      return true;
    }
    this.lastBackTime = now;
    // 网页弹窗在场：返回键先让弹窗内部后退，没有历史可退就收起弹窗（不能误触发下面的退出流程）
    if (this.popupShow) {
      try {
        if (this.popupCtrl.accessBackward()) {
          this.popupCtrl.backward();
        } else {
          this.popupShow = false;
        }
      } catch (e) {
        this.popupShow = false;
      }
      return true;
    }
    if (this.authPrompt || this.pageLoading) {
      this.returnToLogin();
      return true;
    }
    // ★ 白屏死锁兜底：runJavaScript 依赖网页响应，坏地址下回调可能永不来
    //   （且 toast 双击退出也走不进去）——救援浮层在场时，返回键直接回登录页
    if (this.showRescue) {
      this.returnToLogin();
      return true;
    }
    // ★ 死页兜底：JS 探测回调 400ms 不来（坏地址白屏，runJavaScript 永不返回）
    //   → 直接走退出流程。之前依赖回调 = 白屏时按返回毫无反应，只能卸载重装
    let probeAnswered: boolean = false;
    setTimeout(() => {
      if (!probeAnswered && this.pageAlive && !this.leaving) {
        this.exitFlow();
      }
    }, 400);
    // 有弹窗/面板（modal/命令面板/菜单等）→ Esc 关闭（返回上一级）；主页无弹窗 → 进入退出流程
    this.webController.runJavaScript(
      "(function(){var h=document.querySelector('.modal-container,.modal-bg,.modal,.suggestion-container,.suggestion,.menu,.prompt,.dropdown-menu,.notice');if(h){var o={key:'Escape',code:'Escape',keyCode:27,which:27,bubbles:true,cancelable:true};document.dispatchEvent(new KeyboardEvent('keydown',o));document.dispatchEvent(new KeyboardEvent('keyup',o));return '1';}return '0';})()",
      (err: BusinessError, result: string) => {
        probeAnswered = true;
        if (err) {
          console.error('[Index] probe error: ' + JSON.stringify(err));
        }
        // result 回传格式不稳定（'0' / '"0"' / 0）——规范化后再判断（issue侧划反馈）
        const ans = String(result ?? '').replace(/["']/g, '').trim();
        console.info('[Index] probe ans=' + ans);
        if (ans === '0') {
          this.exitFlow();
        }
      }
    );
    return true;
  }

  // 双击退出流程（JS 探测无弹窗 / 探测超时兜底 共用）
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
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        // issue#1 终态：Web 顶进状态栏+毛玻璃条替代死板底块（同 LocalWeb）
        Web({ src: this.url, controller: this.webController })
        .javaScriptProxy({ object: this.remoteClipBridge, name: 'vtRemoteClip', methodList: ['read'], controller: this.webController })
        .javaScriptAccess(true)
        .darkMode(WebDarkMode.Auto)
        .domStorageAccess(true)
        // 遵循服务端 Cache-Control/ETag；不能为提速使用 CacheOnly 或忽略鉴权的强制缓存。
        .cacheMode(CacheMode.Default)
        .imageAccess(true)
        .mediaPlayGestureAccess(true)
        .geolocationAccess(true)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        .zoomAccess(false) // issue#4-②：屏蔽双指/触摸板 viewport 缩放（与 PDF 插件内缩放冲突；桌面 UI 被 viewport 缩放还会点击错位）
        .onWindowNew((event: OnWindowNewEvent) => {
          console.info('[popup] onWindowNew main: ' + event.targetUrl);
          if (isObsidianUri(event.targetUrl)) {
            // 插件直接 window.open('obsidian://…')：不开弹窗，直接投递
            event.handler.setWebController(null);
            this.deliverObsidianUri(event.targetUrl);
            return;
          }
          // 官方契约：必须回传新 WebviewController，否则渲染进程阻塞；
          // 不建新窗口时须传 null。这里统一走应用内弹窗层（OAuth 需要 cookie 共享）
          const pc: webview.WebviewController = new webview.WebviewController();
          event.handler.setWebController(pc);
          this.popupCtrl = pc;
          this.popupHost = '';
          this.popupEpoch += 1;
          this.popupShow = true;
        })
        .onConsole((e: OnConsoleEvent): boolean => {
          // 诊断桥：页面（含 iframe）console 输出转 hilog，排查 Custom Frames 白屏（issue#3）
          console.info('[web:' + e.message.getMessageLevel() + '] ' + e.message.getMessage());
          return false;
        })
        .onErrorReceive((e: OnErrorReceiveEvent) => {
          // 主文档加载失败（地址不可达/DNS 解析失败/连接拒绝）→ 立即浮出救援。
          // 不等 15s 看门狗：错误信号已经到了，白屏等待没有意义
          const req: WebResourceRequest = e.request;
          if (req !== null && req !== undefined) {
            try {
              if (req.isMainFrame()) {
                this.mainFrameFailed = true;
                console.info('[web:main-err] ' + req.getRequestUrl() + ' → ' + e.error.getErrorInfo());
                if (this.watchdogTimer !== -1) {
                  clearTimeout(this.watchdogTimer);
                  this.watchdogTimer = -1;
                }
                this.showRescue = true;
              }
            } catch (err) {
              console.error('[web:err-check] ' + JSON.stringify(err));
            }
          }
        })
        .onGeolocationShow((event: OnGeolocationShowEvent) => {
          // 网页请求定位 → 此刻才向用户索要系统位置权限，授权后再放行
          if (event && event.geolocation) {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            ensurePermissions(ctx, LOCATION_PERMISSIONS).then((ok: boolean) => {
              event.geolocation.invoke(event.origin, ok, false);
            });
          }
        })

        .onHttpAuthRequest((event: OnHttpAuthRequestEvent) => {
          // 在原 Web 上完成挑战，不再 Index → AuthPage → Index 销毁重建、重复启动整页。
          // 插件跨域站点的挑战不可拿到配置服务器的密码。
          if (!this.trustedAuthHost(event.host)) { return false; }
          this.authCancel();
          const epoch = ++this.authEpoch;
          this.pendingAuthHost = event.host;
          this.authConfirm = (user: string, pwd: string): void => { event.handler.confirm(user, pwd); };
          this.authCancel = (): void => { event.handler.cancel(); };
          // 保留挑战 handler，等待冷启动保险箱读取；首个挑战不因 load 尚未完成强制重输。
          this.resolveAuth(epoch, event.host);
          // 等待用户输入期间不是连接超时，不让看门狗盖住认证面板。
          if (this.watchdogTimer !== -1) {
            clearTimeout(this.watchdogTimer);
            this.watchdogTimer = -1;
          }
          return true;
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
            // 网页要用相机时才向用户索要系统相机权限；其余资源沿用原行为直接放行
            const res: string[] = event.request.getAccessibleResource();
            if (res.indexOf('TYPE_VIDEO_CAPTURE') >= 0) {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              ensurePermissions(ctx, ['ohos.permission.CAMERA']).then((ok: boolean) => {
                if (ok) {
                  event.request.grant(res);
                } else {
                  event.request.deny();
                }
              });
            } else {
              event.request.grant(res);
            }
          }
        })
        .onLoadIntercept((event) => {
          // 拦截悬浮球触发的 vitreus://switch → 回 Login 换服务器地址
          const url = event.data.getRequestUrl();
          if (event.data.isMainFrame() && /^https?:\/\//i.test(url)) {
            this.authDocumentUrl = url;
            if (this.authOrigin(url) !== this.authOrigin(this.url)) {
              this.authEpoch += 1;
              this.authCancel();
              this.authCancel = (): void => {};
              this.authConfirm = (_user: string, _pwd: string): void => {};
              this.authPrompt = false;
            }
          }
          if (url.startsWith('vitreus://')) {
            if (url.startsWith('vitreus://remote-clip-read?id=')) {
              this.readRemoteClipboard(parseInt(url.split('id=')[1] ?? '0'));
            } else if (url.includes('switch')) {
              this.returnToLogin();
            }
            return true;
          }
          if (isObsidianUri(url)) {
            // 主页面里直接跳 obsidian://（插件 location.href 回调）→ 投递给 Obsidian
            this.deliverObsidianUri(url);
            return true;
          }
          return false;
        })
        .onPageEnd((event) => {
          // 错误页也会触发 onPageEnd：主帧已失败时保住救援浮层，不撤销
          if (this.mainFrameFailed) {
            return;
          }
          // onPageEnd 到达 = 页面真实加载完成 → 撤销看门狗（正常路径不出救援 UI）
          if (this.watchdogTimer !== -1) {
            clearTimeout(this.watchdogTimer);
            this.watchdogTimer = -1;
          }
          this.showRescue = false;
          this.pageLoading = false;
          console.info('[remote-load] document complete +' + (Date.now() - this.loadStartedAt) + 'ms');
          // 一句可核实的诊断：客户端缓存层到底有没有装上、分区是否已定。
          // 没装上（scope 空）就等于没有加速，速度问题要按"未启用"排查。
          // 诊断必须可核实：取值走 runJavaScript 回调（console 与 hilog 都可能抓不到），
          // 结果直接画在屏幕上，截图即证据。
          this.injectObsidianInset();
          const trustedMatch = this.url.match(/^https?:\/\/[^/]+/i);
          if (trustedMatch) {
            this.safeRun("(function(trusted){if(location.origin.toLowerCase()!==trusted||window.__vtRemoteClipRead)return;var seq=0,pending={};window.__vtRemoteClipRead=function(){return new Promise(function(resolve){var id=++seq;pending[id]=resolve;try{window.vtRemoteClip.read(id);}catch(e){delete pending[id];resolve('');}setTimeout(function(){if(pending[id]){delete pending[id];resolve('');}},20000);});};window.__vtClipRead=window.__vtRemoteClipRead;window.__vtRemoteClipDone=function(id,text){var resolve=pending[id];if(resolve){delete pending[id];resolve(text);}};function patch(){try{var c=navigator.clipboard;if(c)c.readText=window.__vtRemoteClipRead;}catch(e){}try{var e=window.require&&window.require('electron');if(e&&e.clipboard)e.clipboard.readText=window.__vtRemoteClipRead;var r=window.require&&window.require('@electron/remote');if(r&&r.clipboard)r.clipboard.readText=window.__vtRemoteClipRead;}catch(e){}}patch();setTimeout(patch,1500);setTimeout(patch,4000);})(" + JSON.stringify(trustedMatch[0].toLowerCase()) + ")");
          }
          // 用户反馈：网页内按钮触发的手机振动体验差——覆盖 navigator.vibrate 让页面
          // 认为设备不支持振动（App 原生 Haptics.ets 不走此通道，不受影响）
          this.webController.runJavaScript("(function(){if(window.__vtNoVibe)return;window.__vtNoVibe=1;var off=function(){return false;};try{if(typeof Navigator!=='undefined'&&Navigator.prototype)Object.defineProperty(Navigator.prototype,'vibrate',{value:off,writable:true,configurable:true});}catch(e){}try{navigator.vibrate=off;}catch(e){}})()");
          // 注入可拖动悬浮球（吸附+入场动画+2秒吸回）；点击 = 回 Login 换地址
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;var fst=document.createElement('style');fst.textContent='@keyframes vtfabB{0%,100%{box-shadow:0 0 12px 3px rgba(155,232,180,.55),0 2px 8px rgba(0,0,0,.3)}50%{box-shadow:0 0 4px 1px rgba(155,232,180,.15),0 2px 8px rgba(0,0,0,.3)}}';document.head.appendChild(fst);function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;white-space:nowrap;flex-wrap:nowrap;max-width:none;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='white-space:nowrap;height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.innerHTML='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#E8EAF4" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><polyline points="21 3 21 9 15 9"/></svg>';b.style.cssText='width:40px;height:40px;display:flex;align-items:center;justify-content:center;border-radius:14px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.width=W+'px';bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top=(window.innerHeight/2-22)+'px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},2000);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},10000);})();`);
        })

        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 原生加载入口不依赖 onPageEnd：慢资源/认证等待时也随时能回地址页。
      if (this.pageLoading && !this.authPrompt && !this.showRescue) {
        Row({ space: 10 }) {
          Button('‹ 返回地址')
            .onClick(() => { this.returnToLogin(); })
          Text('正在连接服务器…')
            .fontSize(12)
            .fontColor('#9AA3D8')
        }
        .padding(12)
        .backgroundColor('#E623265C')
        .borderRadius(16)
        .position({ x: 16, y: this.sbH + 12 })
      }

      if (this.authPrompt) {
        Column({ space: 14 }) {
          Text(this.authAttempted ? '认证未通过，请重新输入' : '服务器认证')
            .fontSize(18)
            .fontColor(Color.White)
          TextInput({ placeholder: '账号', text: this.authInputUser })
            .fontColor('#F3F4FF')
            .placeholderColor('#B9C0E3')
            .backgroundColor('#363A70')
            .border({ width: 1, color: '#747FAE' })
            .height(48)
            .type(InputType.USER_NAME)
            .enableAutoFill(true)
            .onChange((value: string) => { this.authInputUser = value; })
          TextInput({ placeholder: '密码', text: this.authInputPwd })
            .fontColor('#F3F4FF')
            .placeholderColor('#B9C0E3')
            .backgroundColor('#363A70')
            .border({ width: 1, color: '#747FAE' })
            .height(48)
            .type(InputType.Password)
            .enableAutoFill(true)
            .onChange((value: string) => { this.authInputPwd = value; })
          Button(this.authSaving ? '保存中…' : '保存并登录')
            .width('100%')
            .enabled(!this.authSaving)
            .onClick(() => { this.submitAuth(); })
          Button('返回地址页').width('100%').onClick(() => { this.returnToLogin(); })
        }
        .width('86%')
        .padding(24)
        .backgroundColor('#F223265C')
        .borderRadius(18)
      }

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
            .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
            .fontColor(Color.White)
            .borderRadius(16)
            .margin({ top: 10 })
            .onClick(() => {
              this.returnToLogin();
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
        .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
        .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
        .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
        .alignItems(HorizontalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
          .animation({ duration: 160, curve: Curve.EaseOut }))
      }

      // ── 网页弹窗层：window.open / OAuth 登录窗落点（issue#3 Custom Frames）──
      // 底部半屏面板（WebPopupSheet）：从下方滑入、不盖住 Obsidian，✕ / 下拉关闭。
      // epoch 作 ForEach key：弹窗里再弹窗时强制重建 Web 组件绑定新 controller
      WebPopupSheet({
        show: this.popupShow,
        host: this.popupHost,
        onClose: () => { this.popupShow = false; }
      }) {
        ForEach([this.popupEpoch], (ep: number) => {
          Web({ src: 'about:blank', controller: this.popupCtrl })
            .javaScriptAccess(true)
            .darkMode(WebDarkMode.Auto)
            .domStorageAccess(true)
            .imageAccess(true)
            .mediaPlayGestureAccess(true)
            .multiWindowAccess(true)
            .allowWindowOpenMethod(true)
            .zoomAccess(false) // 同上：弹窗内同样禁缩放
            .onWindowNew((event: OnWindowNewEvent) => {
              console.info('[popup] onWindowNew chained: ' + event.targetUrl);
              if (isObsidianUri(event.targetUrl)) {
                // 登录流程以 obsidian:// 回调收尾：不开新窗，直接投递给 Obsidian 并收起弹窗
                event.handler.setWebController(null);
                this.deliverObsidianUri(event.targetUrl);
                return;
              }
              // 链式弹窗：同一层替换（popupEpoch 变化触发 ForEach 重建）
              const npc: webview.WebviewController = new webview.WebviewController();
              event.handler.setWebController(npc);
              this.popupCtrl = npc;
              this.popupHost = '';
              this.popupEpoch += 1;
            })
            .onLoadIntercept((event) => {
              // 重定向回调：弹窗里的页面跳到 obsidian://（OAuth 回调 / 插件协议处理）→ 投递给 Obsidian
              const url = event.data.getRequestUrl();
              if (isObsidianUri(url)) {
                this.deliverObsidianUri(url);
                return true;
              }
              return false;
            })
            .onPageEnd(() => {
              try {
                const u: string = this.popupCtrl.getUrl();
                let host: string = u;
                if (host.indexOf('//') >= 0) {
                  const rest: string = host.substring(host.indexOf('//') + 2);
                  host = rest.split('/')[0];
                }
                this.popupHost = host;
              } catch (err) {
                console.info('[popup] getUrl fail: ' + JSON.stringify(err));
              }
            })
            .onWindowExit(() => {
              // 页面 window.close()——OAuth 完成的标准收尾
              this.popupShow = false;
            })
            .onAppear(() => {
              console.info('[popup] overlay web mounted');
            })
            .layoutWeight(1)
        }, (ep: number) => 'pop' + ep.toString())
      }

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange(() => {
      this.refreshSafeArea();
    })
  }
  // 页面转场：进入=淡入+上浮，退出=淡出（全 app 统一节奏）
  // 方向感转场：前进从右滑入（旧页左移淡出）；返回从左回位（旧页向右滑走）
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 200, curve: Curve.EaseOut })
      .translate({ x: 320 })
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
  }
}
