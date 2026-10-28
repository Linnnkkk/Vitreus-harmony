import common from '@ohos.app.ability.common';
import { router } from '@kit.ArkUI';
import { MatrixRainBackground } from '../components/AmbientBackground';
import { ServiceSwitch } from '../components/ServiceSwitch';
import { BackButton } from '../components/BackButton';
import { Theme } from '../common/Theme';
import { VipService } from '../common/VipService';
import { WebDavSettings, WebDavConfig } from '../common/WebDavSettings';
import { WebDavCredentialStore, WebDavCredential } from '../common/WebDavCredentialStore';
import { WebDavProbe, WebDavProbeResult } from '../common/WebDavProbe';
import { WebDavRuntime } from '../common/WebDavRuntime';
import { RestartPrompt } from '../common/RestartPrompt';

@Entry
@Component
struct WebDavSettingsPage {
  @State private bgVisible: boolean = true;
  @State private webDavEnabled: boolean = false;
  @State private url: string = '';
  @State private user: string = '';
  @State private pwd: string = '';
  @State private vip: boolean = false;
  @State private credentialLoading: boolean = true;
  @State private saving: boolean = false;
  @State private testing: boolean = false;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  @State private testPassed: boolean = false;
  private pageAlive: boolean = false;
  private editEpoch: number = 0;
  private loadEpoch: number = 0;
  private operationEpoch: number = 0;
  private credentialId: string = '';
  private savePending: boolean = false;
  private loadedUser: string = '';
  private loadedPwd: string = '';

  aboutToAppear(): void {
    this.pageAlive = true;
    this.bgVisible = true;
    this.vip = VipService.isVip();
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config = WebDavSettings.load(context);
      if (config !== undefined) {
        this.webDavEnabled = config.enabled;
        this.url = config.url;
        this.credentialId = config.credentialId;
      }
      this.loadCredential();
    } catch (e) {
      this.credentialLoading = false;
      this.message = '读取配置失败，请重新填写并保存';
    }
  }

  onPageHide(): void {
    this.pageAlive = false;
    this.bgVisible = false;
    this.loadEpoch++;
    this.operationEpoch++;
    this.testPassed = false;
  }

  onPageShow(): void {
    this.pageAlive = true;
    this.bgVisible = true;
    this.vip = VipService.isVip();
    if (!this.savePending) { this.saving = false; this.testing = false; }
    if (this.credentialLoading) { this.loadCredential(); }
  }

  aboutToDisappear(): void { this.onPageHide(); }

  private async loadCredential(): Promise<void> {
    const epoch = ++this.loadEpoch;
    const edited = this.editEpoch;
    this.credentialLoading = true;
    this.loadFailed = false;
    try {
      const credential: WebDavCredential | undefined = this.credentialId === '' ? undefined :
        await WebDavCredentialStore.load(this.credentialId);
      if (!this.pageAlive || epoch !== this.loadEpoch) { return; }
      if (edited !== this.editEpoch) {
        this.message = '加载期间内容发生变化，请检查账号密码后保存';
        return;
      }
      if (this.credentialId !== '' && credential === undefined) {
        this.message = '已保存的凭据不存在，请重新填写账号密码并保存';
        return;
      }
      if (credential !== undefined) {
        this.user = credential.user; this.pwd = credential.pwd;
        this.loadedUser = credential.user; this.loadedPwd = credential.pwd;
      }
    } catch (e) {
      if (!this.pageAlive || epoch !== this.loadEpoch) { return; }
      this.loadFailed = true;
      this.message = '读取本机凭据失败，请点击重新读取后再保存';
    } finally {
      if (this.pageAlive && epoch === this.loadEpoch) { this.credentialLoading = false; }
    }
  }

  private edited(): void {
    // ArkUI can emit onChange while restoring bound values; controls are disabled during loading.
    if (this.credentialLoading) { return; }
    this.editEpoch++;
    this.testPassed = false;
    this.message = '';
  }

  private async changeEnabled(value: boolean): Promise<void> {
    if (!this.pageAlive || this.saving || this.testing) { return; }
    if (value && !VipService.isVip()) {
      this.vip = false;
      router.pushUrl({ url: 'pages/VipPanelPage' });
      return;
    }
    if (value && (this.credentialLoading || this.loadFailed)) { return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.saving = true;
    try {
      const config = WebDavSettings.load(context);
      if (value) {
        if (config === undefined) { this.message = '请先填写并保存连接配置，再开启远程库'; return; }
        const credential = await WebDavCredentialStore.load(config.credentialId);
        if (!this.pageAlive) { return; }
        if (!this.requireVip()) { return; }
        if (credential === undefined) { this.message = '请重新保存账号密码后再开启'; return; }
        const latest = WebDavSettings.load(context);
        if (latest === undefined || WebDavSettings.connectionKey(latest) !== WebDavSettings.connectionKey(config)) {
          this.message = '连接已变更，请重新开启'; return;
        }
        const enabled: WebDavConfig = { enabled: true, url: config.url, vaultName: config.vaultName, credentialId: config.credentialId };
        if (!WebDavSettings.save(context, enabled)) { this.message = '开启失败，请重试'; return; }
        this.webDavEnabled = true;
        AppStorage.setOrCreate('webDavPreferLocal', false);
        this.message = '远程库已开启，重启后生效';
        this.showRestartDialog();
      } else {
        // 先卸载运行中的连接，再落盘确认关闭；不联网访问WebDAV，也不要求会员。
        await WebDavRuntime.disable();
        if (config !== undefined) {
          const disabled: WebDavConfig = { enabled: false, url: config.url, vaultName: config.vaultName, credentialId: config.credentialId };
          if (!WebDavSettings.save(context, disabled)) { this.message = '关闭状态保存失败，请重试'; return; }
        }
        if (!this.pageAlive) { return; }
        this.webDavEnabled = false;
        this.message = '远程库已关闭，立即生效';
      }
    } catch (e) {
      if (this.pageAlive) { this.message = value ? '开启失败，请检查已保存配置' : '关闭未完成，请重试'; }
    } finally { this.saving = false; }
  }

  private requireVip(): boolean {
    this.vip = VipService.isVip();
    if (!this.vip) { this.message = 'WebDAV 远程库是会员功能，请先开通会员'; }
    return this.vip;
  }

  private vaultLabel(): string {
    try { return WebDavSettings.vaultNameFromUrl(this.url); } catch (e) { return '填写目录地址后自动识别'; }
  }

  private validate(): boolean {
    try {
      WebDavSettings.vaultNameFromUrl(this.url);
      if (this.user.trim() === '' || this.user.includes(':') || /[\x00-\x1f\x7f]/.test(this.user)) {
        this.message = '请填写有效账号，账号不能包含冒号或控制字符';
        return false;
      }
      if (this.pwd === '') { this.message = '请填写密码'; return false; }
      return true;
    } catch (e) {
      // Only our fixed validation messages are displayed, never transport errors or server bodies.
      this.message = (e as Error).message;
      return false;
    }
  }

  private async testConnection(): Promise<void> {
    if (!this.requireVip() || this.saving || this.testing || this.credentialLoading || this.loadFailed) { return; }
    if (!this.validate()) { return; }
    const epoch = ++this.operationEpoch;
    const edited = this.editEpoch;
    this.testing = true;
    this.testPassed = false;
    this.message = '正在认证并检查目录…';
    try {
      const result: WebDavProbeResult = await WebDavProbe.test(WebDavSettings.normalizeUrl(this.url), this.user.trim(), this.pwd);
      if (!this.pageAlive || epoch !== this.operationEpoch || edited !== this.editEpoch) { return; }
      if (!this.requireVip()) { return; }
      this.testPassed = result.ok;
      this.message = result.message;
    } catch (e) {
      if (this.pageAlive && epoch === this.operationEpoch) { this.message = '连接测试失败，请重试'; }
    } finally {
      if (this.pageAlive && epoch === this.operationEpoch) { this.testing = false; }
    }
  }

  private async save(): Promise<void> {
    if (!this.requireVip() || this.saving || this.testing || this.credentialLoading || this.loadFailed) { return; }
    if (!this.validate()) { return; }
    const epoch = ++this.operationEpoch;
    const edited = this.editEpoch;
    const url = WebDavSettings.normalizeUrl(this.url);
    const name = WebDavSettings.vaultNameFromUrl(url);
    const sameCredential = this.credentialId !== '' && this.user.trim() === this.loadedUser && this.pwd === this.loadedPwd;
    const id = sameCredential ? this.credentialId : Date.now().toString(36) + Math.random().toString(36).slice(2);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const previous = WebDavSettings.load(context);
    const config: WebDavConfig = { enabled: previous !== undefined && previous.enabled, url: url, vaultName: name, credentialId: id };
    this.saving = true;
    this.savePending = true;
    this.testPassed = false;
    this.message = '保存前正在验证当前连接…';
    try {
      const result: WebDavProbeResult = await WebDavProbe.test(url, this.user.trim(), this.pwd);
      if (!this.pageAlive || epoch !== this.operationEpoch || edited !== this.editEpoch) { return; }
      if (!this.requireVip()) { return; }
      this.testPassed = result.ok;
      this.message = result.message;
      if (!result.ok) { return; }
      const stored = sameCredential ? true : await WebDavCredentialStore.save(id, this.user.trim(), this.pwd);
      if (!this.pageAlive || epoch !== this.operationEpoch || edited !== this.editEpoch) { return; }
      if (!this.requireVip()) { return; }
      if (!stored) { this.message = '凭据保存失败，配置未更新'; return; }
      if (!WebDavSettings.save(context, config)) { this.message = '配置写入失败，请重试'; return; }
      this.credentialId = id;
      this.loadedUser = this.user.trim();
      this.loadedPwd = this.pwd;
      this.savedResult(config);
    } catch (e) {
      if (this.pageAlive && epoch === this.operationEpoch) { this.message = '保存失败，请重试'; }
    } finally {
      this.savePending = false;
      if (this.pageAlive) { this.saving = false; }
    }
  }

  private savedResult(config: WebDavConfig): void {
    this.webDavEnabled = config.enabled;
    this.message = config.enabled && WebDavSettings.needsRestart(config)
      ? '连接配置已保存；关闭后重新开启远程库以应用新配置'
      : '连接配置已保存';
  }

  private showRestartDialog(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    RestartPrompt.show(context, '重启启用远程库', '远程库已开启，重启后加载已保存的连接。', () => {}, () => {
      if (this.pageAlive) { this.message = '请从系统最近任务中划掉应用，再重新打开'; }
    });
  }

  @Styles
  inputStyle() {
    .width('100%').height(46).backgroundColor(Theme.CONFIG_FIELD).border({ width: 1, color: Theme.CONFIG_BORDER })
    .borderRadius(Theme.R_CONTROL).padding({ left: 14, right: 14 })
    .enabled(this.vip && !this.saving && !this.testing && !this.credentialLoading && !this.loadFailed)
  }

  @Styles
  cardStyle() {
    .width('100%').padding(18).backgroundColor(Color.Transparent).borderRadius(Theme.R_CARD)
    .border({ width: 1, color: Theme.HAIRLINE })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}.width('100%').height('100%').linearGradient({
        angle: 160,
        colors: [[Theme.PAGE_BG_START, 0], [Theme.PAGE_BG_MIDDLE, 0.55], [Theme.PAGE_BG_END, 1]]
      })
      MatrixRainBackground({ visible: this.bgVisible })
      Column({ space: 16 }) {
        Row() {
          Text('WebDAV 远程库').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
        }.width('100%').padding({ left: 58 }).height(44)
        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('启用远程库').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
                  Text('开启后重启生效，关闭立即生效').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                ServiceSwitch({
                  isOn: this.webDavEnabled,
                  interactive: !this.saving && !this.testing,
                  label: '启用远程库',
                  onChange: (value: boolean) => { this.changeEnabled(value); }
                })
              }.width('100%')
              Text('通过 WebDAV 直接访问自己的笔记目录，账号密码保存在本机系统保险箱。')
                .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).lineHeight(20).width('100%')
            }.cardStyle().alignItems(HorizontalAlign.Start)
            Column({ space: 12 }) {
              Text('连接信息').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
              Text('WebDAV 目录地址').fontColor(Theme.TEXT_SECONDARY).fontSize(Theme.FS_CAPTION)
              TextInput({ placeholder: 'https://example.com/dav/我的笔记', text: $$this.url })
                .inputStyle().fontColor(Theme.TEXT_PRIMARY).placeholderColor(Theme.TEXT_TERTIARY).onChange(() => { this.edited(); })
              Text('库名：' + this.vaultLabel()).fontColor(Theme.TEXT_SECONDARY).fontSize(Theme.FS_CAPTION)
              Text('自动使用地址最后一层目录名称。建议使用 HTTPS。').fontColor(Theme.TEXT_TERTIARY).fontSize(Theme.FS_FOOT)
              Text('账号').fontColor(Theme.TEXT_SECONDARY).fontSize(Theme.FS_CAPTION)
              TextInput({ placeholder: 'WebDAV 账号', text: $$this.user })
                .inputStyle().fontColor(Theme.TEXT_PRIMARY).placeholderColor(Theme.TEXT_TERTIARY).onChange(() => { this.edited(); })
              Text('密码 · 仅保存在本机系统保险箱').fontColor(Theme.TEXT_SECONDARY).fontSize(Theme.FS_CAPTION)
              TextInput({ placeholder: 'WebDAV 密码', text: $$this.pwd })
                .inputStyle().fontColor(Theme.TEXT_PRIMARY).placeholderColor(Theme.TEXT_TERTIARY)
                .type(InputType.Password).onChange(() => { this.edited(); })
            }.cardStyle().alignItems(HorizontalAlign.Start)
            Column({ space: 12 }) {
              Text('测试与保存').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
              Text('测试并保存地址和账号密码；启用或停用由上方开关控制。')
                .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).lineHeight(20)
              if (this.message !== '') {
                Text(this.message).fontSize(Theme.FS_CAPTION).fontColor(this.testPassed ? Theme.SUCCESS : Theme.WARN).lineHeight(20)
              }
              if (this.loadFailed) {
                Button('重新读取凭据').onClick(() => { this.loadCredential(); })
                  .backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_PRIMARY)
              }
              Row({ space: 12 }) {
                Button(this.testing ? '测试中…' : '测试连接').layoutWeight(1).height(46)
                  .backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_PRIMARY)
                  .enabled(!this.saving && !this.testing && !this.credentialLoading && !this.loadFailed)
                  .onClick(() => { this.testConnection(); })
                Button(this.credentialLoading ? '读取中…' : (this.saving ? '验证并保存…' : '保存设置')).layoutWeight(1).height(46)
                  .backgroundColor(Theme.ACCENT_DEEP).fontColor(Theme.TEXT_PRIMARY)
                  .enabled(!this.saving && !this.testing && !this.credentialLoading && !this.loadFailed)
                  .onClick(() => { this.save(); })
              }.width('100%')
            }.cardStyle().alignItems(HorizontalAlign.Start)
            Column({ space: 10 }) {
              Text('何时生效').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
              Text('仅测试或保存未启用的连接，无需重启。启用后进入本地模式使用；若本地服务已经运行，更改连接或关闭远程库时会提示重启。')
                .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).lineHeight(21)

            }.cardStyle().alignItems(HorizontalAlign.Start).margin({ bottom: 24 })
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').padding({ left: 18, right: 18, top: 56 })
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
