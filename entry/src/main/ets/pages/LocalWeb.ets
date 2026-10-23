import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ensurePermissions, LOCATION_PERMISSIONS } from '../common/AppPermissions';
import { getStatusbarHeightVp } from '../common/SafeArea';
import { getObsidianInsetScript } from '../common/ObsidianInset';
import { LanShareApi, LanShareStatus } from '../common/LanShareApi';
import { VipService } from '../common/VipService';
import { WebPopupSheet } from '../common/WebPopupSheet';
import { isObsidianUri, obsidianUriScript } from '../common/ObsidianUri';
import { SrvSafetyDialog } from '../common/SrvSafetyDialog';
import { UpdateNoticeDialog, UPDATE_NOTICE_ID } from '../components/UpdateNotice';
import { NoticeState } from '../common/NoticeState';
import { BackgroundLease } from '../common/BackgroundLease';
import { AiLanApi, AiLanStatus } from '../common/AiLanApi';

// Deliberately excludes pairing codes, fingerprints and device identifiers from the Web state.
interface LocalAiPanelState {
  known: boolean;
  running: boolean;
  busy: boolean;
  vip: boolean;
  accessReady: boolean;
  vaultCount: number;
  allowWrite: boolean;
  pairedClients: number;
  message: string;
}

// 页面→App 的剪贴板读取入口（javaScriptProxy 注入为 window.vtClip）：只转交给页面壳，不在此处处理权限
class ClipBridge {
  handler: (id: number) => void = (id: number): void => {};
  read(id: number): void {
    this.handler(id);
  }
}

// 本地模式全屏壳：ignis server 就在本机 6791，无需登录/Basic Auth
// 沉浸式：无返回键/无日志面板，切模式靠网页内悬浮球 ‹（对齐 VPS 模式）
@Entry
@Component
struct LocalWeb {
  private webController: webview.WebviewController = new webview.WebviewController();
  private url: string = 'http://127.0.0.1:6791';
  private clipBridge: ClipBridge = new ClipBridge();
  @State private lastBackTime: number = 0;
  @State private exitTime: number = 0;
  // 伺服器凭证保存流程：安全提示弹窗 + 暂存（srv-cred-form / srv-cred 两入口共用，确认后 confirmSrvCred 落库）
  @State private srvSafetyShow: boolean = false;
  private pendingCredUser: string = '';
  private pendingCredPass: string = '';
  // 网页弹窗（window.open / OAuth）：Custom Frames 等插件会在 iframe 里弹登录窗，
  // ArkWeb 宿主必须接住（不接=渲染进程阻塞、点击无响应）。issue#3
  @State private popupShow: boolean = false;
  @State private popupHost: string = '';
  @State private popupEpoch: number = 0;
  // Obsidian 1.13.7 兼容性公告：本地 Web 入口也要覆盖，仍按同一公告 ID 只展示一次。
  @State private showUpdateNotice: boolean = false;
  // Obsidian 前端自己启动要几秒（加载 app.js、建索引），期间 Web 是空白——盖一层深色载入层，
  // 轮询到 .workspace 出现再淡出，避免用户看到几秒白屏
  @State private loadingCover: boolean = true;
  private coverPolling: boolean = false;
  private readonly updateNoticeId: string = UPDATE_NOTICE_ID;
  private updateNoticeTimer: number = -1;
  private noticeFilesDir: string = '';
  private popupCtrl: webview.WebviewController = new webview.WebviewController();

  // 安全提示确认后：VIP 门禁自证 + 存凭证 + enable + 回推（原两分支的保存逻辑合并于此，单一事实源）
  private confirmSrvCred(): void {
    if (!VipService.isVip()) {
      // 非 VIP：与伺服器页同款闭环——凭证先存（买完回来面板开关即用/进伺服器页自动续开），引导购买
      AppStorage.setOrCreate('lanShareUser', this.pendingCredUser);
      AppStorage.setOrCreate('lanSharePass', this.pendingCredPass);
      AppStorage.setOrCreate('vipPendingEnable', true);
      this.getUIContext().getPromptAction().showToast({ message: '凭证已保存，开通会员后即可开启伺服器', duration: 2600 });
      this.webController.runJavaScript('window.__vtSrvClose&&window.__vtSrvClose();');
      router.pushUrl({ url: 'pages/VipPanelPage' });
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
        AppStorage.setOrCreate('srvRunning', true); // 开关语义统一：与伺服器页共用持久标志
        BackgroundLease.reconcile(this.getUIContext().getHostContext() as common.UIAbilityContext);
      }
      this.pushSrvState();
    });
  }
  // 状态栏高度(vp)：横屏平板时钟会压住 Obsidian 顶部UI(issue#1)，Web 从状态栏下开始布局
  @State private sbH: number = 0;

  aboutToAppear() {
    this.clipBridge.handler = (id: number): void => { this.readClipboardForWeb(id); };
    // 放行 iframe 第三方 cookie：Custom Frames 等插件嵌的站点（百度/Google）登录依赖
    // 3P cookie，内核默认不发不收导致"请开启cookie"无法登录（issue#3）
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    this.refreshSafeArea();
    // 伺服器面板依赖的持久键（与 LanServerPage 幂等共持）
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    PersistentStorage.persistProp('lanSharePort', 0);
    PersistentStorage.persistProp('lanShareTls', false);
  }

  private refreshSafeArea(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    getStatusbarHeightVp(ctx).then((h: number) => {
      this.sbH = h;
      this.safeRun(getObsidianInsetScript(h));
    });
  }

  private startCoverPoll(): void {
    if (this.coverPolling || !this.loadingCover) {
      return;
    }
    this.coverPolling = true;
    const t0 = Date.now();
    const tick = () => {
      if (!this.loadingCover || !this.pageAlive) {
        return;
      }
      if (Date.now() - t0 > 20000) {
        this.hideCover();
        return;
      }
      try {
        this.webController.runJavaScript("(function(){return !!document.querySelector('.workspace')&&!document.querySelector('.app-container.mod-loading');})()")
          .then((r: string) => {
            if (r === 'true') {
              this.hideCover();
            } else {
              setTimeout(tick, 250);
            }
          })
          .catch(() => { setTimeout(tick, 400); });
      } catch (e) {
        // Web 已解绑（页面已离开）：停止轮询
      }
    };
    tick();
  }

  private hideCover(): void {
    if (!this.pageAlive) {
      return;
    }
    const t0 = AppStorage.get<number>('bootT0') ?? 0;
    console.info('[boot] obsidian ready, cover hide +' + (t0 > 0 ? Date.now() - t0 : -1) + 'ms');
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
      this.loadingCover = false;
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

  // 网页读剪贴板：按需申请 READ_PASTEBOARD，ArkTS 读出文本后回填给页面里挂起的 Promise
  private async readClipboardForWeb(id: number): Promise<void> {
    let text: string = '';
    hilog.info(0x0000, 'VtClip', 'read request id=%{public}d', id);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await ensurePermissions(ctx, ['ohos.permission.READ_PASTEBOARD'])) {
        const data = await pasteboard.getSystemPasteboard().getData();
        text = data.getPrimaryText() ?? '';
        // Do not feed a copied one-time pairing secret back to vault plugins/AI.
        if (text.indexOf('"pairingCode"') >= 0 && text.indexOf('"fingerprint"') >= 0 &&
          text.indexOf('"deviceId"') >= 0) {
          text = '';
        }
        hilog.info(0x0000, 'VtClip', 'read ok id=%{public}d len=%{public}d', id, text.length);
      } else {
        hilog.warn(0x0000, 'VtClip', 'permission not granted id=%{public}d', id);
      }
    } catch (err) {
      hilog.error(0x0000, 'VtClip', 'read failed: %{public}s', JSON.stringify(err));
    }
    this.webController.runJavaScript('window.__vtClipDone&&window.__vtClipDone(' + id.toString() + ',' + JSON.stringify(text) + ')');
  }

  private injectObsidianInset(): void {
    // 立即注入 + 延迟补注：Obsidian 启动期可能重建 head，样式被冲掉时再补一次
    const run = () => { this.safeRun(getObsidianInsetScript(this.sbH)); };
    run();
    setTimeout(run, 1500);
    setTimeout(run, 4000);
  }

  // ── 伺服器面板：状态回推（网页侧 __vtSrvSync 渲染）──
  private lastSrvAddr: string = '';
  private pushSrvState(): void {
    const epoch = this.aiEpoch;
    AiLanApi.status().then((status: AiLanStatus | null) => {
      if (!this.pageAlive || !this.localVisible || this.aiBusy || epoch !== this.aiEpoch) {
        return;
      }
      this.aiStatus = status;
      if (status !== null) {
        AppStorage.setOrCreate('aiRunning', status.running);
      }
      this.pushAiState();
    });
    LanShareApi.status().then((st: LanShareStatus | null) => {
      if (st === null || !this.pageAlive) { return; }
      let js: string;
      if (st !== null && st.running) {
        this.lastSrvAddr = LanShareApi.fullAddr(st);
        js = JSON.stringify({ running: true, addr: this.lastSrvAddr, user: st.user, tls: LanShareApi.tlsPreferred(), vip: VipService.isVip() });
      } else {
        const u = AppStorage.get<string>('lanShareUser') ?? '';
        js = JSON.stringify({ running: false, addr: '', user: u, tls: LanShareApi.tlsPreferred(), vip: VipService.isVip() });
      }
      this.safeRun('window.__vtSrvState=' + js + ';window.__vtSrvSync&&window.__vtSrvSync();');
      AppStorage.setOrCreate('srvRunning', st !== null && st.running);
    });
  }

  // AI operations are serialized; every await is fenced by both lifecycle and request epoch.
  private aiPanelVisible: boolean = false;
  private localVisible: boolean = true;
  private aiBusy: boolean = false;
  private aiEpoch: number = 0;
  private aiStatus: AiLanStatus | null = null;
  private aiMessage: string = '';

  private aiCurrent(epoch: number): boolean {
    return this.pageAlive && this.localVisible && this.aiPanelVisible && epoch === this.aiEpoch;
  }

  private pushAiState(): void {
    if (!this.pageAlive || !this.localVisible) {
      return;
    }
    const status = this.aiStatus;
    const accessReady = AiLanApi.hasAccessPolicy(status);
    const state: LocalAiPanelState = {
      known: status !== null,
      running: status !== null && status.running === true,
      busy: this.aiBusy,
      vip: VipService.isVip(),
      accessReady: accessReady,
      vaultCount: accessReady && status !== null && status.access !== undefined ? status.access.vaultIds.length : 0,
      allowWrite: accessReady && status !== null && status.access !== undefined && status.access.allowWrite,
      pairedClients: status !== null && typeof status.pairedClients === 'number' ? status.pairedClients : 0,
      message: this.aiMessage
    };
    this.safeRun('window.__vtAiState=' + JSON.stringify(state) + ';window.__vtAiSync&&window.__vtAiSync();');
  }

  private dismissAiPanel(): void {
    this.aiPanelVisible = false;
    this.aiEpoch++;
    this.aiStatus = null;
  }

  private async aiPanelAction(action: string): Promise<void> {
    if (!this.pageAlive || !this.localVisible) {
      return;
    }
    if (action === 'refresh') {
      this.aiPanelVisible = true;
    }
    if (!this.aiPanelVisible || this.aiBusy) {
      return;
    }
    this.aiBusy = true;
    const epoch = ++this.aiEpoch;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.aiMessage = '正在确认本机服务状态…';
    this.aiStatus = null;
    this.pushAiState();
    try {
      // Never decide a toggle or pairing from cached/unknown state.
      let result = await AiLanApi.status();
      if (!this.aiCurrent(epoch)) {
        return;
      }
      if (result === null || typeof result.running !== 'boolean') {
        this.aiMessage = '无法确认 AI 服务状态，请刷新后重试。';
        return;
      }
      this.aiStatus = result;
      if ((action === 'toggle' && !result.running) || action === 'pair') {
        if (!VipService.isVip()) {
          this.aiMessage = 'AI 连接是会员功能，请先开通会员。';
          return;
        }
        if (!AiLanApi.hasAccessPolicy(result)) {
          this.aiMessage = '无法确认授权策略，请更新本机服务后重试。';
          return;
        }
        if (LanShareApi.getLanIp() === '') {
          this.aiMessage = '请先连接 Wi-Fi，或开启热点让电脑接入同一局域网。';
          return;
        }
      }
      if (action === 'toggle') {
        result = result.running ? await AiLanApi.disable() : await AiLanApi.enable();
        // Service side effects outlive this popup. Re-read truth and reconcile the
        // shared lease even if the UI closed while the request was in flight.
        const actual = await AiLanApi.status();
        if (actual !== null) {
          AppStorage.setOrCreate('aiRunning', actual.running);
          await BackgroundLease.reconcile(context);
          result = actual;
        }
        if (!this.aiCurrent(epoch)) {
          return;
        }
      } else if (action === 'pair') {
        if (!result.running) {
          this.aiMessage = '请先开启 AI 连接，再生成配对信息。';
          return;
        }
        result = await AiLanApi.pair();
        if (!this.aiCurrent(epoch)) {
          return;
        }
      }
      // Ambiguous action results must not leave a stale enabled state usable in the tab.
      this.aiStatus = result !== null && typeof result.running === 'boolean' ? result : null;
      if (this.aiStatus === null || result === null) {
        this.aiMessage = '操作结果未确认，请刷新；不要假定服务已开启或关闭。';
        return;
      }
      AppStorage.setOrCreate('aiRunning', result.running);
      const leaseOk = await BackgroundLease.reconcile(context);
      if (!this.aiCurrent(epoch)) {
        return;
      }
      this.aiMessage = result.running && !leaseOk ? '服务运行中，但未获后台运行授权，切到后台可能暂停。' : '';
      if (action === 'pair') {
        if (!VipService.isVip() || !result.running || !AiLanApi.hasAccessPolicy(result) ||
          !result.pairingCode || !result.pairingExpiresAt || result.pairingExpiresAt <= Date.now()) {
          this.aiMessage = '配对信息未确认或已过期，未复制，请重试。';
          return;
        }
        // Secret stays native: never put AiLanStatus / pairingInfo in runJavaScript or the DOM.
        await pasteboard.getSystemPasteboard().setData(
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AiLanApi.pairingInfo(result)));
        if (!this.aiCurrent(epoch)) {
          return;
        }
        this.aiMessage = '配对信息已复制：仅一次有效，2 分钟过期。只粘贴到电脑配对终端，勿发给 AI 或公开分享。';
      }
    } catch (error) {
      if (this.aiCurrent(epoch)) {
        this.aiStatus = null;
        this.aiMessage = '操作未确认或复制失败，请刷新状态后重试。';
      }
    } finally {
      this.aiBusy = false;
      if (this.aiCurrent(epoch)) {
        this.pushAiState();
      } else if (this.pageAlive && this.localVisible && this.aiPanelVisible) {
        // A tab was reopened while a previous request was finishing: discard it, then reload.
        this.aiPanelAction('refresh');
      }
    }
  }

  onPageShow() {
    this.localVisible = true;
    this.noticeFilesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir;
    if (!NoticeState.isSeen(this.noticeFilesDir, this.updateNoticeId)) {
      if (this.updateNoticeTimer !== -1) {
        clearTimeout(this.updateNoticeTimer);
      }
      // Web 页面已经落定后再弹，避免遮住首帧或和网页初始化争抢。
      this.updateNoticeTimer = setTimeout(() => {
        this.updateNoticeTimer = -1;
        if (!NoticeState.isSeen(this.noticeFilesDir, this.updateNoticeId)) {
          this.showUpdateNotice = true;
        }
      }, 900);
    }
    // 从购买页/会员页返回：重推面板状态（VIP 变更后悬浮球按钮与面板文案同步刷新，
    // 否则购买成功后悬浮球仍显示旧状态，须退出本地模式重进才恢复）
    setTimeout(() => { this.pushSrvState(); }, 200);
  }

  onPageHide() {
    this.localVisible = false;
    this.dismissAiPanel();
    this.safeRun('window.__vtSrvClose&&window.__vtSrvClose();');
    if (this.updateNoticeTimer !== -1) {
      clearTimeout(this.updateNoticeTimer);
      this.updateNoticeTimer = -1;
    }
  }

  aboutToDisappear() {
    this.dismissAiPanel();
    this.localVisible = false;
    this.pageAlive = false;
    if (this.updateNoticeTimer !== -1) {
      clearTimeout(this.updateNoticeTimer);
      this.updateNoticeTimer = -1;
    }
  }

  private closeUpdateNotice(): void {
    if (this.noticeFilesDir !== '') {
      NoticeState.markSeen(this.noticeFilesDir, this.updateNoticeId);
    }
    this.showUpdateNotice = false;
  }

  // 重定向回调：把 obsidian://… 投递给主页面的 Obsidian（window.OBS_ACT），并收起弹窗
  private deliverObsidianUri(url: string): void {
    console.info('[popup] deliver obsidian uri: ' + url.substring(0, 80));
    this.webController.runJavaScript(obsidianUriScript(url));
    this.popupShow = false;
  }

  onBackPress(): boolean {
    console.info('[LocalWeb] onBackPress fired');
    const now = Date.now();
    // 防抖：一次左滑多次触发，500ms 内只处理一次
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
      "(function(){var p=document.getElementById('vt-srv-panel');if(p&&p.getAttribute('data-open')==='true'){window.__vtSrvClose&&window.__vtSrvClose();return '1';}var h=document.querySelector('.modal-container,.modal-bg,.modal,.suggestion-container,.suggestion,.menu,.prompt,.dropdown-menu,.notice');if(h){var o={key:'Escape',code:'Escape',keyCode:27,which:27,bubbles:true,cancelable:true};document.dispatchEvent(new KeyboardEvent('keydown',o));document.dispatchEvent(new KeyboardEvent('keyup',o));return '1';}return '0';})()",
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
        .backgroundColor('#141736')
        .javaScriptAccess(true)
        .javaScriptProxy({ object: this.clipBridge, name: 'vtClip', methodList: ['read'], controller: this.webController })
        .darkMode(WebDarkMode.Auto)
        .domStorageAccess(true)
        .imageAccess(true)
        .mediaPlayGestureAccess(true)
        .fileAccess(true)
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
        .geolocationAccess(true)
        .onGeolocationShow((event: OnGeolocationShowEvent) => {
          // 网页请求定位 → 此刻才向用户索要系统位置权限，授权后再放行
          if (event && event.geolocation) {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            ensurePermissions(ctx, LOCATION_PERMISSIONS).then((ok: boolean) => {
              event.geolocation.invoke(event.origin, ok, false);
            });
          }
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
          this.dismissAiPanel(); // A new Web document must not inherit an in-flight pairing request.
          console.info('[boot] web onPageEnd +' + (Date.now() - (AppStorage.get<number>('bootT0') ?? Date.now())) + 'ms');
          this.startCoverPoll();
          this.injectObsidianInset();
          // 剪贴板读取桥：ignis 垫片的 clipboard.readText 优先走它（vitreus://clip-read → ArkTS 读取 → __vtClipDone 回填）
          this.webController.runJavaScript("(function(){if(window.__vtClipRead)return;var n=0,m={};var f=document.createElement('iframe');f.name='vtclipfrm';f.style.cssText='display:none!important';(document.body||document.documentElement).appendChild(f);window.__vtClipRead=function(){return new Promise(function(res){var id=++n;m[id]=res;if(window.vtClip&&typeof window.vtClip.read==='function'){window.vtClip.read(id);}else{var a=document.createElement('a');a.href='vitreus://clip-read?id='+id;a.target='vtclipfrm';(document.body||document.documentElement).appendChild(a);a.click();a.remove();}setTimeout(function(){if(m[id]){delete m[id];res('');}},20000);});};window.__vtClipDone=function(id,t){var r=m[id];if(r){delete m[id];r(t);}};})()");
          // 用户反馈：网页内按钮触发的手机振动体验差——覆盖 navigator.vibrate 让页面
          // 认为设备不支持振动（App 原生 Haptics.ets 不走此通道，不受影响）
          this.webController.runJavaScript("(function(){if(window.__vtNoVibe)return;window.__vtNoVibe=1;var off=function(){return false;};try{if(typeof Navigator!=='undefined'&&Navigator.prototype)Object.defineProperty(Navigator.prototype,'vibrate',{value:off,writable:true,configurable:true});}catch(e){}try{navigator.vibrate=off;}catch(e){}})()");
          // 注入伺服器面板（悬浮球第三按钮 ◉/○ 点击弹出：会话开关+地址复制+账密设置）
          this.webController.runJavaScript(`(function(){if(window.__vtSrvP)return;window.__vtSrvP=1;var S=window.__vtSrvState||{running:false,addr:'',user:'',tls:false,vip:false};var mask=null,panel=null,tab='srv',A=window.__vtAiState||{known:false,busy:false};var st=document.createElement('style');st.textContent='#vt-srv-panel:not([data-open="true"]),#vt-srv-panel:not([data-open="true"]) *{animation:none!important;transition:none!important}#vt-srv-panel{max-height:82vh;overflow-y:auto} .vtinput::placeholder{color:#767FBE!important}.vtinput{background:rgba(255,255,255,0.10)!important;border:1px solid rgba(255,255,255,0.25)!important;color:#F0F2FA!important}@keyframes vtbreath{0%,100%{opacity:1;box-shadow:0 0 8px 2px rgba(155,232,180,.55)}50%{opacity:.55;box-shadow:0 0 3px 1px rgba(155,232,180,.25)}}@keyframes vtin{from{opacity:0;transform:translate(-50%,-40%) scale(.78)}to{opacity:1;transform:translate(-50%,-50%) scale(1)}}.vtbtn{transition:transform .12s ease,filter .12s ease}.vtbtn:active{transform:scale(.965);filter:brightness(1.15)}';document.head.appendChild(st);function ensurePanel(){if(mask)return;mask=document.createElement('div');mask.id='vt-srv-mask';mask.style.cssText='position:fixed;left:0;top:0;right:0;bottom:0;background:rgba(8,10,26,0.62);z-index:2147483640;display:none;';panel=document.createElement('div');panel.id='vt-srv-panel';panel.style.cssText='position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:86vw;max-width:330px;background:rgba(34,38,82,0.42);-webkit-backdrop-filter:blur(26px) saturate(1.4);backdrop-filter:blur(26px) saturate(1.4);border:1px solid rgba(255,255,255,0.28);border-radius:20px;padding:22px 20px;z-index:2147483641;font-family:system-ui,-apple-system,sans-serif;box-shadow:0 18px 52px rgba(0,0,0,0.5),inset 0 1px 0 rgba(255,255,255,0.18);box-sizing:border-box;display:none;animation:vtin .3s cubic-bezier(.34,1.56,.64,1);';document.body.appendChild(mask);document.body.appendChild(panel);mask._vtcb=close;var frm=document.createElement('iframe');frm.name='vtfrm';frm.setAttribute('style','display:none!important;position:fixed;left:-9999px;top:-9999px;width:0;height:0;border:0;');document.body.appendChild(frm);}function send(act){var a=document.createElement('a');a.href='vitreus://'+act;a.target='vtfrm';document.body.appendChild(a);a.click();a.remove();}function close(){if(mask)mask.style.display='none';if(panel){panel.style.display='none';panel.removeAttribute('data-open');}send('ai-hide');}window.__vtSrvClose=close;function syncLamp(){var b=document.getElementById('vt-c');var on=!!(S.running||(A.known&&A.running));if(b){b.textContent=on?'◉':'○';b.style.color=on?'#9BE8B4':'#E8EAF4';}}window.__vtAiSync=function(){A=window.__vtAiState||{known:false,busy:false};syncLamp();if(mask&&mask.style.display==='block'&&tab==='ai')render();};window.__vtSrvPanel=function(){ensurePanel();render();mask.style.display='block';panel.style.display='';panel.setAttribute('data-open','true');if(tab==='ai')send('ai-refresh');};window.__vtSrvSync=function(){S=window.__vtSrvState||S;syncLamp();if(mask&&mask.style.display==='block')render();};function h(txt,color,size,wt){var e=document.createElement('div');e.textContent=txt;e.style.cssText='color:'+(color||'#AAB4E8')+';font-size:'+(size||13)+'px;font-weight:'+(wt||'400')+';line-height:1.55;margin:2px 0;';return e;}function delegate(ev){var el=ev.target;while(el&&el!==document.body){if(el._vtcb){if(el._vtT&&Date.now()-el._vtT<400)return;el._vtT=Date.now();ev.stopPropagation();ev.preventDefault();el._vtcb();return;}el=el.parentNode;}}document.addEventListener('pointerdown',delegate,true);document.addEventListener('pointerdown',function(ev){var el=ev.target;while(el&&el!==document.body){if(el.className==='vtbtn'){el.style.transform='scale(.93)';el.style.filter='brightness(1.2)';setTimeout(function(){el.style.transform='';el.style.filter='';},320);break;}el=el.parentNode;}},true);document.addEventListener('touchstart',delegate,true);function btn(txt,bg,act,small){var e=document.createElement('a');e.href='vitreus://'+act;e.target='vtfrm';e.textContent=txt;e.className='vtbtn';e.style.cssText='display:flex;align-items:center;justify-content:center;width:100%;height:'+(small?38:46)+'px;border-radius:'+(small?11:13)+'px;font-size:'+(small?13:15)+'px;font-weight:600;color:#fff;background:'+bg+';margin-top:10px;cursor:pointer;font-family:inherit;text-decoration:none;box-shadow:0 6px 18px rgba(95,107,216,.28);';return e;}function tlsRow(){var r=document.createElement('a');r.href='vitreus://srv-tls';r.target='vtfrm';r.className='vtbtn';r.style.cssText='display:flex;align-items:center;justify-content:space-between;margin-top:12px;padding:10px 12px;border-radius:12px;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.14);text-decoration:none;cursor:pointer;';var l=document.createElement('span');l.textContent='加密连接（HTTPS）';l.style.cssText='color:#E8EAF4;font-size:13px;font-weight:600;';var sw=document.createElement('span');sw.style.cssText='position:relative;width:38px;height:22px;border-radius:11px;background:'+(S.tls?'#5F6BD8':'rgba(255,255,255,0.22)')+';flex:none;';var kn=document.createElement('span');kn.style.cssText='position:absolute;top:2px;left:'+(S.tls?'18px':'2px')+';width:18px;height:18px;border-radius:50%;background:#fff;';sw.appendChild(kn);r.appendChild(l);r.appendChild(sw);return r;}function aiButton(txt,act,enabled,small){var b=btn(txt,'linear-gradient(90deg,#7A88E8,#5F6BD8)',act,small);if(!enabled){b.removeAttribute('href');b.style.opacity='.42';b.style.pointerEvents='none';b.setAttribute('aria-disabled','true');}panel.appendChild(b);}function renderAi(){panel.appendChild(h(A.known?(A.running?'● AI 连接运行中':'○ AI 连接已关闭'):'状态待确认',A.known&&A.running?'#9BE8B4':'#AAB4E8',14,'600'));panel.appendChild(h('让同一局域网电脑上的 Claude Code、Codex 等通过 MCP 搜索、读取你授权的手机笔记。无需公网，换 IP 不用重装 MCP。','#AAB4E8',12));panel.appendChild(h('已配对电脑：'+(A.known?A.pairedClients:'—'),'#AAB4E8',12));panel.appendChild(h(A.accessReady?'授权 '+A.vaultCount+' 个笔记库 · '+(A.allowWrite?'允许编辑':'只读访问'):'授权策略尚未确认，不能开启或配对。',A.allowWrite?'#FFD28A':'#AAB4E8',12));panel.appendChild(h('仅授权的笔记库可访问；编辑权限需在管理页明确开启。可在管理页调整范围、撤销已配对电脑。','#767FBE',11));if(A.message)panel.appendChild(h(A.message,'#FFD28A',12));if(!A.vip)aiButton('了解会员','ai-buy',!A.busy,true);aiButton(A.busy?'处理中…':(A.running?'关闭 AI 连接':'开启 AI 连接'),'ai-toggle',!A.busy&&A.known&&(A.running||(A.vip&&A.accessReady)));aiButton('生成并复制配对信息','ai-pair',!A.busy&&A.known&&A.running&&A.accessReady&&A.vip);aiButton('刷新状态','ai-refresh',!A.busy,true);aiButton('授权管理与安装指引 ↗','ai-manage',!A.busy,true);panel.appendChild(h('配对秘密只写入系统剪贴板，不显示在网页；仅粘贴到电脑配对终端，请勿发送给 AI 或公开分享。','#767FBE',11));}function render(){var _u=document.getElementById('vt-srv-u'),_p=document.getElementById('vt-srv-p'),_uv=_u?_u.value:'',_pv=_p?_p.value:'';panel.innerHTML='';var head=document.createElement('div');head.style.cssText='display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;padding-bottom:10px;border-bottom:1px solid rgba(122,136,232,0.16);';var tabs=document.createElement('div');tabs.style.cssText='display:flex;gap:6px;flex:1;';['srv','ai'].forEach(function(id){var t=h(id==='srv'?'伺服器模式':'AI 连接',tab===id?'#FFFFFF':'#AAB4E8',14,'700');t.style.cssText+='padding:7px 9px;border-radius:9px;cursor:pointer;background:'+(tab===id?'rgba(122,136,232,.30)':'transparent')+';';t._vtcb=function(){tab=id;render();send(id==='ai'?'ai-refresh':'ai-hide');};tabs.appendChild(t);});head.appendChild(tabs);var x=document.createElement('a');x.href='vitreus://srv-close';x.target='vtfrm';x.className='vtbtn';x.textContent='×';x.style.cssText='font-size:24px;color:#767FBE;cursor:pointer;padding:0 6px;line-height:1;text-decoration:none;';head.appendChild(x);panel.appendChild(head);if(tab==='ai'){renderAi();return;}if(S.running){var dot=document.createElement('span');dot.style.cssText='display:inline-block;width:9px;height:9px;border-radius:50%;background:#9BE8B4;margin-right:7px;animation:vtbreath 1.8s ease-in-out infinite;vertical-align:1px;';var rl=h('',' #1F8A4C',13,'600');rl.insertBefore(dot,rl.firstChild);rl.style.cssText+='margin-top:12px;';panel.appendChild(rl);var addr=h(S.addr||'(获取地址中...)','#9BE8B4',18,'700');addr.style.cssText+='word-break:break-all;margin:12px 0 4px;letter-spacing:.5px;';panel.appendChild(addr);panel.appendChild(h(S.tls?'局域网设备浏览器输入上面地址访问；首次会提示证书不受信任，选择继续访问即可':'局域网设备浏览器输入上面地址即可访问','#767FBE',11));panel.appendChild(tlsRow());panel.appendChild(btn('复制地址','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-copy'));panel.appendChild(btn('关闭伺服器','linear-gradient(90deg,#3A4078,#32375F)','srv-toggle',true));}else if(S.vip){panel.appendChild(h('○ 已停止','#8F9BD8',13,'600'));if(S.user){panel.appendChild(h('账号：'+S.user+'（Digest 加密，密码不上线）','#767FBE',11));panel.appendChild(tlsRow());panel.appendChild(btn('开启伺服器','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-toggle'));}else{panel.appendChild(h('首次开启需设置访问账号密码','#8F9BD8',12));var iu=document.createElement('input');iu.id='vt-srv-u';iu.placeholder='账号';iu.className='vtinput';iu.style.cssText='width:100%;box-sizing:border-box;border-radius:12px;padding:11px 12px;font-size:14px;margin-top:10px;outline:none;';var ip=document.createElement('input');ip.className='vtinput';ip.id='vt-srv-p';ip.type='password';ip.placeholder='密码（至少4位）';ip.style.cssText=iu.style.cssText;iu.value=_uv;ip.value=_pv;panel.appendChild(iu);panel.appendChild(ip);panel.appendChild(tlsRow());panel.appendChild(btn('保存并开启','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-cred-form'));}}else{panel.appendChild(h('伺服器模式是 Vitreus 会员功能','#FFFFFF',14,'600'));panel.appendChild(h('熄屏在线，局域网设备浏览器直连。','#8F9BD8',12));panel.appendChild(btn('了解会员','linear-gradient(90deg,#7A88E8,#5F6BD8)','srv-buy'));}var ft=h('开关持久保存（重启 App 自动恢复）· Digest 加密· 内网传输','#5A649E',10);ft.style.cssText+='margin-top:14px;padding-top:10px;border-top:1px solid rgba(122,136,232,0.12);';panel.appendChild(ft);}})();`);
          // 初始状态回推（面板/按钮图标就位后）
          setTimeout(() => { this.pushSrvState(); }, 600);
          // 注入悬浮球：‹ 左箭头（与返回键统一），点击回模式选择（vitreus://switch → ModeSelect）
          this.webController.runJavaScript(`(function(){if(window.__vtInited)return;window.__vtInited=1;var S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};var W=148;var fst=document.createElement('style');fst.textContent='@keyframes vtfabB{0%,100%{box-shadow:0 0 12px 3px rgba(155,232,180,.55),0 2px 8px rgba(0,0,0,.3)}50%{box-shadow:0 0 4px 1px rgba(155,232,180,.15),0 2px 8px rgba(0,0,0,.3)}}';document.head.appendChild(fst);function init(){if(!document.body||document.getElementById('vt-bar'))return;var bar=document.createElement('div');bar.id='vt-bar';bar.style.cssText='position:fixed;display:flex;gap:8px;white-space:nowrap;flex-wrap:nowrap;max-width:none;z-index:2147483647;user-select:none;-webkit-user-select:none;touch-action:none;transition:left .3s,opacity .3s,top .3s;';var a=document.createElement('div');a.id='vt-a';a.textContent='\u2039 Vitreus';a.style.cssText='white-space:nowrap;height:40px;line-height:40px;padding:0 18px;border-radius:20px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:15px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';var b=document.createElement('div');b.id='vt-b';b.innerHTML='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#E8EAF4" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><polyline points="21 3 21 9 15 9"/></svg>';b.style.cssText='width:40px;height:40px;display:flex;align-items:center;justify-content:center;border-radius:14px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:#E8EAF4;font-size:21px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(a);bar.appendChild(b);var sv=document.createElement('div');sv.id='vt-c';var svOn=!!((window.__vtSrvState&&window.__vtSrvState.running)||(window.__vtAiState&&window.__vtAiState.known&&window.__vtAiState.running));sv.textContent=svOn?'\u25C9':'\u25CB';sv.style.cssText='width:40px;height:40px;line-height:40px;border-radius:14px;background:rgba(108,113,133,0.6);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,0.16);color:'+(svOn?'#9BE8B4':'#E8EAF4')+';font-size:18px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);cursor:pointer;';bar.appendChild(sv);document.body.appendChild(bar);W=bar.offsetWidth||148;bar.style.width=W+'px';bar.style.left=(window.innerWidth-W-8)+'px';bar.style.top=(window.innerHeight/2-22)+'px';S={drag:false,moved:false,sx:0,sy:0,t0:0,hidden:false,atRight:true,autoSnap:0};function pt(e){if(e.touches&&e.touches[0])return{x:e.touches[0].clientX,y:e.touches[0].clientY};if(e.changedTouches&&e.changedTouches[0])return{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY};return{x:e.clientX,y:e.clientY};}function snap(){clearTimeout(S.autoSnap);S.hidden=true;var cur=parseFloat(bar.style.left)||0;var cx=cur+W/2;if(cx<window.innerWidth/2){S.atRight=false;bar.style.left=(-W+14)+'px';}else{S.atRight=true;bar.style.left=(window.innerWidth-14)+'px';}bar.style.opacity='0.5';}function expand(){clearTimeout(S.autoSnap);S.hidden=false;bar.style.left=S.atRight?(window.innerWidth-W-8)+'px':'8px';bar.style.opacity='1';S.autoSnap=setTimeout(function(){if(!S.drag)snap();},2600);}function down(e){clearTimeout(S.autoSnap);S.drag=true;S.moved=false;var p=pt(e);S.sx=p.x;S.sy=p.y;S.t0=Date.now();var r=bar.getBoundingClientRect();bar._vx=r.left;bar._vy=r.top;bar.style.transition='none';bar.style.left=r.left+'px';bar.style.top=r.top+'px';e.preventDefault();}function move(e){if(!S.drag)return;var p=pt(e);var dx=p.x-S.sx,dy=p.y-S.sy;if(Math.abs(dx)>4||Math.abs(dy)>4)S.moved=true;var nx=Math.max(-W+14,Math.min(window.innerWidth-14,bar._vx+dx));var ny=Math.max(0,Math.min(window.innerHeight-44,bar._vy+dy));bar.style.left=nx+'px';bar.style.top=ny+'px';e.preventDefault();}function up(e){if(!S.drag)return;S.drag=false;bar.style.transition='left .3s,opacity .3s,top .3s';if(!S.moved&&Date.now()-S.t0<400){if(S.hidden){expand();}else{var t=e.target&&e.target.id;if(t==='vt-b'){location.reload();}else if(t==='vt-c'){if(window.__vtSrvPanel)window.__vtSrvPanel();}else{window.location.href='vitreus://switch';}}}else{snap();}}bar.addEventListener('mousedown',down);bar.addEventListener('touchstart',down,{passive:false});window.addEventListener('mousemove',move);window.addEventListener('touchmove',move,{passive:false});window.addEventListener('mouseup',up);window.addEventListener('touchend',up);setTimeout(function(){snap();},2000);}init();function onResize(){var el=document.getElementById('vt-bar');if(!el)return;var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(el.style.left)||0,t=parseFloat(el.style.top)||60;var op=parseFloat(el.style.opacity)||1;if(op<0.6){if(S.atRight){el.style.left=(w-14)+'px';}else{el.style.left=(-W+14)+'px';}}else{el.style.left=Math.max(-W+14,Math.min(w-W-4,l))+'px';}el.style.top=Math.max(0,Math.min(h-44,t))+'px';}window.addEventListener('resize',onResize);window.__vtGuard=window.__vtGuard||setInterval(function(){var g=document.getElementById('vt-bar');if(!g){init();return;}var w=window.innerWidth,h=window.innerHeight;var l=parseFloat(g.style.left)||0,t=parseFloat(g.style.top)||60;if(l>w-10||l<-W+4||t>h-10||t<-5){onResize();}},10000);})();`);
        })
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('vitreus://')) {
            if (url === 'vitreus://ai-hide' || url === 'vitreus://ai-hide/') {
              this.dismissAiPanel();
            } else if (url === 'vitreus://ai-refresh' || url === 'vitreus://ai-refresh/') {
              this.aiPanelAction('refresh');
            } else if (url === 'vitreus://ai-toggle' || url === 'vitreus://ai-toggle/') {
              this.aiPanelAction('toggle');
            } else if (url === 'vitreus://ai-pair' || url === 'vitreus://ai-pair/') {
              this.aiPanelAction('pair');
            } else if (url === 'vitreus://ai-manage' || url === 'vitreus://ai-manage/' ||
              url === 'vitreus://ai-buy' || url === 'vitreus://ai-buy/') {
              if (this.pageAlive && this.localVisible && !this.aiBusy) {
                this.dismissAiPanel();
                this.safeRun('window.__vtSrvClose&&window.__vtSrvClose();');
                router.pushUrl({ url: url.includes('ai-buy') ? 'pages/VipPanelPage' : 'pages/AiConnectPage' });
              }
            } else if (url.includes('clip-read')) {
              // 笔记脚本读剪贴板（navigator.clipboard.readText）：此刻才申请 READ_PASTEBOARD 再读
              this.readClipboardForWeb(parseInt(url.split('id=')[1] ?? '0'));
            } else if (url.includes('switch')) {
              AppStorage.setOrCreate('navBack', true);
              // Reuse an existing home rather than replacing Web with a second home.
              if (router.getStateByUrl('pages/ModeSelect').length > 0) {
                router.back({ url: 'pages/ModeSelect' });
              } else {
                router.replaceUrl({ url: 'pages/ModeSelect' });
              }
              setTimeout(() => { AppStorage.setOrCreate('navBack', false); }, 600);
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
              // Floating controls affect this process only; saved page switches are untouched.
              LanShareApi.status().then((st: LanShareStatus | null) => {
                if (st !== null && st.running) {
                  LanShareApi.disable().then((stopped: LanShareStatus | null) => {
                    if (stopped === null) { this.pushSrvState(); return; }
                    AppStorage.setOrCreate('srvRunning', stopped.running);
                    BackgroundLease.reconcile(this.getUIContext().getHostContext() as common.UIAbilityContext);
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
                        AppStorage.setOrCreate('srvRunning', true);
                        BackgroundLease.reconcile(this.getUIContext().getHostContext() as common.UIAbilityContext);
                      }
                      this.pushSrvState();
                    });
                  } else {
                    this.pushSrvState(); // 无凭证：回推后面板显示设置表单
                  }
                }
              });
            } else if (url.includes('srv-tls')) {
              // 加密连接开关：持久偏好翻转；运行中则以新档位重启 serverB（地址协议随之变化）
              const on: boolean = !LanShareApi.tlsPreferred();
              AppStorage.setOrCreate('lanShareTls', on);
              const tu2 = AppStorage.get<string>('lanShareUser') ?? '';
              const tp2 = AppStorage.get<string>('lanSharePass') ?? '';
              LanShareApi.status().then((st: LanShareStatus | null) => {
                if (st !== null && st.running && tu2 !== '' && tp2 !== '') {
                  this.getUIContext().getPromptAction().showToast({
                    message: on ? '已切换为加密连接，请用新的 https 地址访问' : '已切换为普通连接，请用新的 http 地址访问',
                    duration: 2600
                  });
                  const tp: number = AppStorage.get<number>('lanSharePort') ?? 0;
                  LanShareApi.enable(tu2, tp2, tp).then((st2: LanShareStatus | null) => {
                    if (st2 !== null && st2.running) {
                      AppStorage.setOrCreate('lanSharePort', st2.port);
                    }
                    this.pushSrvState();
                  });
                } else {
                  this.pushSrvState();
                }
              });
            } else if (url.includes('srv-buy')) {
              this.webController.runJavaScript('window.__vtSrvClose&&window.__vtSrvClose();');
              router.pushUrl({ url: 'pages/VipPanelPage' });
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
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')


      if (this.loadingCover) {
        Column({ space: 16 }) {
          LoadingProgress().width(40).height(40).color('#7A88E8')
          Text('正在载入 Obsidian…').fontSize(13).fontColor('#8F9BD8')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#141736')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .zIndex(15)
        .transition(TransitionEffect.OPACITY)
      }
      if (this.showUpdateNotice) {
        UpdateNoticeDialog({ onClose: () => { this.closeUpdateNotice(); } })
      }

      // 凭证保存安全提示（遮罩层）
      SrvSafetyDialog({
        show: this.srvSafetyShow,
        onConfirm: () => {
          this.srvSafetyShow = false;
          this.confirmSrvCred();
        }
      })

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
