import { router } from '@kit.ArkUI';
import { NetworkBackground } from '../components/AmbientBackground';
import { StartupPreferences } from '../common/StartupPreferences';
import { common } from '@kit.AbilityKit';
import { BackButton } from '../components/BackButton';
import { RemoteCapture } from '../common/RemoteCapture';
import { RemoteCredentialStore, RemoteCredential } from '../common/RemoteCredentialStore';
import { RemoteServerSettings } from '../common/RemoteServerSettings';
import { Theme } from '../common/Theme';
import { hapticLight } from '../common/Haptics';

@Entry
@Component
struct IgnisSettingsPage {
  @State private bgVisible: boolean = true;
  @State private error: string = '';
  @State private saved: string = '';
  @State private remoteTargetLabel: string = '未配置';
  // 远程配置就在本页填写：不跳远程浏览页，避免为了填地址而启动一个 ArkWeb。
  @State private remoteExpanded: boolean = false;
  @State private remoteServer: string = '';
  @State private remoteUser: string = '';
  @State private remotePwd: string = '';
  @State private remoteSaving: boolean = false;
  private remoteLoadEpoch: number = 0;
  private remoteEditEpoch: number = 0;
  private pageAlive: boolean = false;
  @State private credentialLoading: boolean = false;
  private credentialLoadEditEpoch: number = 0;
  private resumeCredentialLoad: boolean = false;
  private resumeCredentialEditEpoch: number = 0;
  aboutToAppear(): void {
    this.pageAlive = true;
    this.bgVisible = true;
    this.refreshRemoteLabel();
    this.openRemoteEntry();
  }
  onPageHide(): void {
    if (this.credentialLoading && this.credentialLoadEditEpoch === this.remoteEditEpoch) {
      this.resumeCredentialLoad = true;
      this.resumeCredentialEditEpoch = this.remoteEditEpoch;
    }
    this.pageAlive = false;
    this.bgVisible = false;
    this.remoteLoadEpoch++;
    this.credentialLoading = false;
  }

  aboutToDisappear(): void {
    this.onPageHide();
  }

  onPageShow(): void {
    this.pageAlive = true;
    this.bgVisible = true;
    if (this.resumeCredentialLoad && this.remoteExpanded && this.resumeCredentialEditEpoch === this.remoteEditEpoch) {
      this.resumeCredentialLoad = false;
      this.loadRemoteCredential();
    }
  }

  private openRemoteEntry(): void {
    // 只展开本页表单：不做页面跳转，也不触碰 ArkWeb。
    if (this.remoteSaving) { return; }
    this.remoteLoadEpoch++;
    this.credentialLoading = false;
    this.remoteExpanded = !this.remoteExpanded;
    if (this.remoteExpanded) {
      this.remoteServer = (AppStorage.get<string>('serverUrl') ?? '').trim();
      // 地址、账号和密码必须来自同一服务器，不能复用收起前的半份表单。
      this.remoteUser = '';
      this.remotePwd = '';
      this.loadRemoteCredential();
    }
  }

  private async loadRemoteCredential(): Promise<void> {
    const server = this.remoteServer.trim().replace(/\/+$/, '');
    const epoch = ++this.remoteLoadEpoch;
    const edited = this.remoteEditEpoch;
    this.credentialLoadEditEpoch = edited;
    this.credentialLoading = false;
    if (server === '') { return; }
    this.credentialLoading = true;
    try {
      const cred: RemoteCredential | undefined = await RemoteCredentialStore.load(server);
      if (!this.pageAlive || !this.remoteExpanded || epoch !== this.remoteLoadEpoch ||
        edited !== this.remoteEditEpoch || server !== this.remoteServer.trim().replace(/\/+$/, '') ||
        cred === undefined) { return; }
      this.remoteUser = cred.user;
      this.remotePwd = cred.pwd;
    } catch (e) {
      // 读不到就让用户手填
    } finally {
      if (this.pageAlive && epoch === this.remoteLoadEpoch) { this.credentialLoading = false; }
    }
  }

  private remoteEdited(): void {
    this.remoteEditEpoch++;
    this.error = '';
    this.saved = '';
  }

  private confirmClearRemote(): void {
    if (this.remoteSaving) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: '清除远程服务器？',
      message: '将清除已保存的服务器地址及相关账号密码。未完成的远程记录、速记草稿和笔记均会保留。',
      buttons: [{ text: '取消', color: Theme.TEXT_SECONDARY }, { text: '清除配置', color: Theme.DANGER }]
    }).then((result) => {
      if (result.index === 1 && this.pageAlive) { this.clearRemote(); }
    }).catch(() => {});
  }

  private async clearRemote(): Promise<void> {
    if (this.remoteSaving) { return; }
    this.remoteSaving = true;
    this.remoteLoadEpoch++;
    this.remoteEditEpoch++;
    this.credentialLoading = false;
    this.error = '';
    this.saved = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cleared = await RemoteServerSettings.clear(context);
      if (!this.pageAlive) { return; }
      if (!cleared) {
        this.error = '清除未完成，请重试；草稿和笔记已保留';
        return;
      }
      this.remoteServer = '';
      this.remoteUser = '';
      this.remotePwd = '';
      this.remoteExpanded = false;
      this.refreshRemoteLabel();
      this.saved = '远程配置已清除，未完成记录、草稿和笔记均已保留';
    } catch (e) {
      if (this.pageAlive) { this.error = '清除失败，请重试'; }
    } finally {
      this.remoteSaving = false;
    }
  }

  private async saveRemote(connect: boolean = false): Promise<void> {
    if (this.remoteSaving || this.credentialLoading) { return; }
    const server = this.remoteServer.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/(?:\[[0-9a-f:]+\]|[^/:?#@]+)(?::\d{1,5})?(?:\/[^?#]*)?$/i.test(server) ||
      /[\s\\]/.test(server)) {
      this.error = '请填写有效的 HTTP(S) 地址，不含账号、查询参数或片段';
      return;
    }
    this.remoteSaving = true;
    this.error = '';
    try {
      const user = this.remoteUser.trim();
      const pwd = this.remotePwd;
      const credentialSaved = await RemoteCredentialStore.save(server, user, pwd);
      if (!this.pageAlive) { return; }
      if (!credentialSaved) {
        this.error = '账号密码保存失败，未更新服务器配置';
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!RemoteServerSettings.save(context, server)) {
        this.error = '服务器配置写入失败，请重试';
        return;
      }
      AppStorage.setOrCreate('serverUrl', server);
      this.saved = server.replace(/^https?:\/\/[^/]+/i, '') !== ''
        ? '配置已保存；速记与剪藏请使用服务器根地址' : '服务器配置已保存';
      this.refreshRemoteLabel();
      if (connect) {
        if (!StartupPreferences.enterMode(context, 'remote')) { this.error = '启动模式保存失败，请重试'; return; }
        AppStorage.setOrCreate('bootMode', 'remote');
        await router.pushUrl({ url: 'pages/Index' }, router.RouterMode.Single);
      }
    } catch (e) {
      this.error = '保存或连接失败，请重试';
    } finally {
      this.remoteSaving = false;
    }
  }

  private refreshRemoteLabel(): void {
    const server = (AppStorage.get<string>('serverUrl') ?? '').trim();
    if (server === '') {
      this.remoteTargetLabel = '未配置 · 点此保存地址和账号密码';
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let pending = false;
    try { pending = RemoteCapture.load(context) !== undefined; } catch (e) { pending = true; }
    this.remoteTargetLabel = server + (pending ? '（有未完成记录）' : '（暂无待保存记录）');
  }

  @Styles
  plainInputStyle() {
    .width('100%').height(46)
    .backgroundColor(Theme.CONFIG_FIELD).border({ width: 1, color: Theme.CONFIG_BORDER })
    .borderRadius(Theme.R_CONTROL)
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}.width('100%').height('100%').linearGradient({ angle: 160,
        colors: [[Theme.PAGE_BG_START, 0], [Theme.PAGE_BG_MIDDLE, 0.55], [Theme.PAGE_BG_END, 1]] })
      NetworkBackground({ visible: this.bgVisible })
      Scroll() {
        Column({ space: 14 }) {
          Text('配置服务器').fontSize(30).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY).margin({ top: 110 })
          Column({ space: 10 }) {
            Text('连接已部署的 Ignis 服务器').fontSize(16).fontColor(Theme.TEXT_PRIMARY)
            Text('保存 Ignis 服务器地址和账号后，可在远程模式浏览笔记；速记和网页剪藏也可直接选择远程库保存。')
              .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).lineHeight(19)
            if (this.remoteExpanded) {
              Text('服务器地址').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
              TextInput({ placeholder: 'https://ignis.example.com', text: $$this.remoteServer })
                .plainInputStyle()
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_SECONDARY)
                .enabled(!this.remoteSaving)
                .onChange(() => {
                  this.remoteEdited();
                  this.remoteUser = '';
                  this.remotePwd = '';
                  this.loadRemoteCredential();
                })
              Text('账号（无认证可留空）').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
              TextInput({ placeholder: '账号', text: $$this.remoteUser })
                .plainInputStyle()
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_SECONDARY)
                .enabled(!this.remoteSaving)
                .onChange(() => { this.remoteEdited(); })
              Text('密码（无认证可留空，加密保存在本机）').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
              TextInput({ placeholder: '密码', text: $$this.remotePwd })
                .plainInputStyle()
                .type(InputType.Password)
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_SECONDARY)
                .enabled(!this.remoteSaving)
                .onChange(() => { this.remoteEdited(); })
              Button(this.remoteSaving ? '处理中…' : '保存并连接')
                .width('100%').height(48).backgroundColor(Theme.ACCENT_DEEP)
                .fontColor(Theme.TEXT_PRIMARY).borderRadius(Theme.R_CONTROL)
                .enabled(!this.remoteSaving && !this.credentialLoading)
                .onClick(() => { hapticLight(); this.saveRemote(true); })
              Button(this.remoteSaving ? '保存中…' : '只保存配置')
                .width('100%').height(44)
                .backgroundColor(Theme.ACCENT_DEEP)
                .fontColor(Theme.TEXT_PRIMARY).borderRadius(Theme.R_CONTROL)
                .enabled(!this.remoteSaving && !this.credentialLoading)
                .onClick(() => {
                  hapticLight();
                  this.saveRemote();
                })
              Text('密码加密保存在本机。速记与剪藏仅支持服务器根地址；子路径地址可用于浏览笔记。')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
            }
            Button(this.remoteSaving ? '处理中…' : '清除远程配置')
              .width('100%').height(44)
              .backgroundColor(Theme.CONFIG_FIELD).border({ width: 1, color: Theme.CONFIG_BORDER })
              .fontColor(Theme.DANGER).borderRadius(Theme.R_CONTROL)
              .enabled(!this.remoteSaving)
              .onClick(() => { this.confirmClearRemote(); })
            Text('远程服务器：' + this.remoteTargetLabel)
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            Text('提示：捕获目标可独立选择，不受主界面当前浏览本地还是远程的限制。')
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).lineHeight(17)
          }
          .width('86%')
          .padding(18)
          .backgroundColor(Color.Transparent)
          .borderRadius(Theme.R_CARD)
          .border({ width: 1, color: Theme.HAIRLINE })

          if (this.error !== '') { Text(this.error).fontColor(Theme.DANGER).width('86%') }
          if (this.saved !== '') { Text(this.saved).fontColor(Theme.SUCCESS).width('86%') }
        }.width('100%').padding({ bottom: 34 })
      }.width('100%').height('100%')
      BackButton({ target: 'pages/ModeSelect' })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 整页保持不透明：透明度转场会透出系统白底（既有真机修复规则）。
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
