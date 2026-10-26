import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { BackButton } from '../components/BackButton';
import { VipService } from '../common/VipService';
import { CapturePathSettings } from '../common/CapturePathSettings';
import { CapturePathTemplate, CapturePathTemplates, CaptureTemplateValues } from '../common/CapturePathTemplate';
import { QuickCapture } from '../common/QuickCapture';
import { RemoteCapture } from '../common/RemoteCapture';
import { RemoteCredentialStore, RemoteCredential } from '../common/RemoteCredentialStore';
import { RemoteServerSettings } from '../common/RemoteServerSettings';
import { Theme } from '../common/Theme';
import { hapticLight } from '../common/Haptics';
import { StartupPreferences } from '../common/StartupPreferences';

@Entry
@Component
struct CaptureSettings {
  @State private rememberMode: boolean = true;
  @State private quickPath: string = '';
  @State private quickHeading: string = '';
  @State private clipPath: string = '';
  @State private error: string = '';
  @State private saved: string = '';
  @State private vip: boolean = false;
  @State private previewAt: number = Date.now();
  @State private activeField: string = 'quick';
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
  private previewVaultName: string = 'vault';
  private readonly variables: string[] = ['{{年}}', '{{月}}', '{{日}}', '{{今天}}', '{{时间}}', '{{标题}}', '{{站点}}', '{{库名}}'];

  aboutToAppear(): void {
    this.pageAlive = true;
    this.load();
  }

  onPageHide(): void {
    if (this.credentialLoading && this.credentialLoadEditEpoch === this.remoteEditEpoch) {
      this.resumeCredentialLoad = true;
      this.resumeCredentialEditEpoch = this.remoteEditEpoch;
    }
    this.pageAlive = false;
    this.remoteLoadEpoch++;
    this.credentialLoading = false;
  }

  aboutToDisappear(): void {
    this.onPageHide();
  }

  onPageShow(): void {
    this.pageAlive = true;
    if (this.resumeCredentialLoad) {
      this.resumeCredentialLoad = false;
      if (this.remoteExpanded && this.resumeCredentialEditEpoch === this.remoteEditEpoch) {
        this.loadRemoteCredential();
      }
    }
    this.previewAt = Date.now();
    this.refreshPreviewVault();
    this.vip = VipService.isVip();
    this.refreshRemoteLabel();
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
      buttons: [{ text: '取消', color: '#9AA3D8' }, { text: '清除配置', color: '#E66D7A' }]
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

  private async saveRemote(): Promise<void> {
    if (this.remoteSaving || this.credentialLoading) { return; }
    const server = this.remoteServer.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/(?:\[[0-9a-f:]+\]|[^/:?#@]+)(?::\d{1,5})?$/i.test(server) ||
      /[\s\\]/.test(server)) {
      this.error = '请填写服务器根地址，如 https://ignis.example.com（不含子路径、账号或参数）';
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
      this.remotePwd = '';
      this.remoteExpanded = false;
      this.saved = '远程服务器已保存，速记与剪藏可直接选择远程库';
      this.refreshRemoteLabel();
    } catch (e) {
      this.error = '保存失败，请重试';
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

  private refreshPreviewVault(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (RemoteCapture.isRemote()) {
      this.previewVaultName = '远程库';
      return;
    }
    const vaultName = QuickCapture.vaultName(QuickCapture.resolveVault(context));
    this.previewVaultName = vaultName !== '' ? vaultName : 'vault';
  }

  private changeRememberMode(value: boolean): void {
    const previous = this.rememberMode;
    this.rememberMode = value;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!StartupPreferences.setRemember(context, value)) {
      this.rememberMode = previous;
      this.getUIContext().getPromptAction().showToast({ message: '启动偏好保存失败，已恢复原设置，请重试' });
    }
  }

  private load(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.rememberMode = StartupPreferences.load(context).remember;
    const settings = CapturePathSettings.load(context);
    this.refreshPreviewVault();
    this.quickPath = settings.quickNotePath;
    this.quickHeading = settings.quickNoteHeading;
    this.clipPath = settings.clipPath;
    this.vip = VipService.isVip();
    this.refreshRemoteLabel();
  }

  private save(): void {
    this.error = '';
    this.saved = '';
    if (!VipService.isVip()) {
      this.vip = false;
      this.error = '自定义存储规则是会员功能';
      return;
    }
    const quick = CapturePathTemplate.validateTemplate(this.quickPath);
    if (!quick.empty && !quick.valid) {
      this.error = '速记路径：' + quick.error;
      return;
    }
    const heading = CapturePathTemplate.validateHeading(this.quickHeading);
    if (!heading.empty && !heading.valid) {
      this.error = '速记标题：' + heading.error;
      return;
    }
    const clip = CapturePathTemplate.validateTemplate(this.clipPath);
    if (!clip.empty && !clip.valid) {
      this.error = '剪藏路径：' + clip.error;
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const vault = QuickCapture.resolveVault(context);
    const vaultName = QuickCapture.vaultName(vault);
    const shownVault = vaultName !== '' ? vaultName : 'vault';
    const values: CaptureTemplateValues = CapturePathTemplate.makeValues(
      Date.now(), '示例标题', 'example.com', shownVault);
    if (!quick.empty && !CapturePathTemplate.expand(this.quickPath, values).valid) {
      this.error = '速记路径展开后无效';
      return;
    }
    if (!clip.empty && !CapturePathTemplate.expand(this.clipPath, values).valid) {
      this.error = '剪藏路径展开后无效';
      return;
    }
    const templates: CapturePathTemplates = {
      version: 1,
      quickNotePath: this.quickPath.trim(),
      quickNoteHeading: this.quickHeading.trim(),
      clipPath: this.clipPath.trim()
    };
    if (!CapturePathSettings.save(context, templates)) {
      this.error = '保存失败，请重试';
      return;
    }
    const stored = CapturePathSettings.load(context);
    if (stored.quickNotePath !== templates.quickNotePath ||
      stored.quickNoteHeading !== templates.quickNoteHeading || stored.clipPath !== templates.clipPath) {
      this.error = '保存后校验失败，请重试；当前编辑内容已保留';
      return;
    }
    this.quickPath = stored.quickNotePath;
    this.quickHeading = stored.quickNoteHeading;
    this.clipPath = stored.clipPath;
    this.saved = '全部规则已保存并校验（速记路径、速记标题、剪藏路径）';
  }

  private reset(): void {
    this.quickPath = '';
    this.quickHeading = '';
    this.clipPath = '';
    this.save();
  }

  private previewPath(template: string, title: string, site: string, isClip: boolean): string {
    if (template.trim() === '') {
      return isClip ? 'Clippings/时间 标题.md' : 'Inbox.md';
    }
    const checked = CapturePathTemplate.expand(template, CapturePathTemplate.makeValues(
      this.previewAt, title, site, this.previewVaultName));
    return checked.valid ? checked.path : '模板无效：' + checked.error;
  }

  private edited(): void {
    this.error = '';
    this.saved = '';
  }

  private async copyVariable(v: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, v);
      await pasteboard.getSystemPasteboard().setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制 ' + v });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    }
  }

  // 每个预设只改它负责的字段，保留其他已编辑规则。
  private applyPreset(preset: string): void {
    if (!this.vip) {
      return;
    }
    hapticLight();
    switch (preset) {
      case 'date':
        this.quickPath = '速记/{{今天}}.md';
        this.clipPath = '剪藏/{{年}}/{{标题}}.md';
        break;
      case 'site':
        this.clipPath = '剪藏/{{站点}}/{{标题}}.md';
        break;
      case 'diary':
        this.quickPath = '日记/{{今天}}.md';
        this.quickHeading = '## 速记';
        break;
      default:
        return;
    }
    this.edited();
  }

  private pathSegments(path: string): string[] {
    const out: string[] = [];
    for (const part of path.split('/')) {
      if (part !== '') {
        out.push(part);
      }
    }
    return out;
  }

  @Builder
  presetChip(label: string, preset: string) {
    Text(label)
      .fontSize(Theme.FS_CAPTION)
      .fontColor(this.vip ? Theme.TEXT_PRIMARY : Theme.TEXT_TERTIARY)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(Theme.CHIP)
      .borderRadius(Theme.R_PILL)
      .margin({ right: 8, bottom: 8 })
      .stateStyles({
        pressed: { .scale({ x: 0.96, y: 0.96 }) }
      })
      .onClick(() => {
        this.applyPreset(preset);
      })
  }

  // 路径面包屑预览：目录 › 目录 › 文件
  @Builder
  crumbs(template: string, title: string, site: string, isClip: boolean) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text('保存到').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).margin({ right: 8 })
      if (template.trim() === '') {
        Text(isClip ? '默认位置：Clippings/时间 标题.md' : '默认位置：Inbox.md')
          .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
      } else if (this.previewPath(template, title, site, isClip).startsWith('模板无效')) {
        Text(this.previewPath(template, title, site, isClip)).fontSize(Theme.FS_FOOT).fontColor(Theme.DANGER)
      } else {
        ForEach(this.pathSegments(this.previewPath(template, title, site, isClip)), (seg: string, idx: number) => {
          if (idx > 0) {
            Text('›').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).margin({ left: 4, right: 4 })
          }
          Text(seg)
            .fontSize(Theme.FS_FOOT)
            .fontColor(Theme.ACCENT)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('rgba(122,136,232,0.14)')
            .borderRadius(8)
        }, (seg: string, idx: number) => idx + seg)
      }
    }
    .width('100%')
  }

  @Styles
  ruleInputStyle() {
    .width('100%')
    .height(46)
    .enabled(this.vip)
    .backgroundColor('rgba(255,255,255,0.05)')
    .borderRadius(12)
    .padding({ left: 14, right: 14 })
  }

  // 远程配置不是会员功能，不受 vip 限制。
  @Styles
  plainInputStyle() {
    .width('100%')
    .height(46)
    .backgroundColor('rgba(255,255,255,0.05)')
    .borderRadius(12)
    .padding({ left: 14, right: 14 })
  }

  @Builder
  sectionCard(title: string, hint: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(Theme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
      Text(hint).fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
      })

      Scroll() {
        Column({ space: 14 }) {
          Text('配置')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 110, bottom: 0 })
          Text(RemoteCapture.isRemote() ? '本地与远程保存沿用这些规则，捕获时直接选择目标库' : '决定速记和网页剪藏落在笔记库的哪里')
            .fontSize(Theme.FS_CAPTION)
            .fontColor('#9AA3D8')
            .margin({ bottom: 6 })

          Column({ space: 8 }) {
            Row({ space: 12 }) {
              Text('记住上次使用的模式')
                .fontSize(Theme.FS_BODY)
                .fontColor(Theme.TEXT_PRIMARY)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.rememberMode })
                .selectedColor(Theme.ACCENT)
                .onChange((value: boolean) => { this.changeRememberMode(value); })
            }
            .width('100%')
            Text('开启后，启动时直接进入上次使用的模式；关闭后，每次启动先选择模式。')
              .fontSize(Theme.FS_FOOT)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(16)

          if (!this.vip) {
            Column({ space: 10 }) {
              Text('自定义存储规则是会员功能。下方可以先预览效果，基础速记和剪藏不受影响。')
                .fontSize(Theme.FS_CAPTION)
                .fontColor(Theme.WARN)
                .lineHeight(19)
              Button('查看会员权益')
                .width('100%')
                .height(42)
                .fontSize(14)
                .fontColor(Color.White)
                .linearGradient({ angle: 90, colors: [[Theme.ACCENT, 0], [Theme.ACCENT_DEEP, 1]] })
                .borderRadius(14)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/VipPanelPage' });
                })
            }
            .width('86%')
            .padding(16)
            .backgroundColor('rgba(242,198,109,0.08)')
            .borderRadius(16)
            .border({ width: 1, color: 'rgba(242,198,109,0.25)' })
          }

          Column({ space: 8 }) {
            Text('常用方案').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            Flex({ wrap: FlexWrap.Wrap }) {
              this.presetChip('按日期归档', 'date')
              this.presetChip('剪藏按站点', 'site')
              this.presetChip('写进日记', 'diary')
            }
          }
          .width('86%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.sectionCard('远程服务器', '统一配置地址和账号密码，捕获时直接读取')
            Text('在远程模式入口保存服务器配置后，速记和网页剪藏可在当前界面直接选择本地库或远程库并保存，无需再跳确认页。')
              .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).lineHeight(19)
            Button(this.remoteExpanded ? '收起配置' : '配置远程服务器')
              .width('100%').height(44)
              .backgroundColor('rgba(122,136,232,0.18)')
              .fontColor(Theme.TEXT_PRIMARY).borderRadius(14)
              .onClick(() => {
                hapticLight();
                this.openRemoteEntry();
              })
            if (this.remoteExpanded) {
              Text('服务器根地址').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
              TextInput({ placeholder: 'https://ignis.example.com', text: $$this.remoteServer })
                .plainInputStyle()
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor('#B8C0E4')
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
                .placeholderColor('#B8C0E4')
                .enabled(!this.remoteSaving)
                .onChange(() => { this.remoteEdited(); })
              Text('密码（无认证可留空，加密保存在本机）').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
              TextInput({ placeholder: '密码', text: $$this.remotePwd })
                .plainInputStyle()
                .type(InputType.Password)
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor('#B8C0E4')
                .enabled(!this.remoteSaving)
                .onChange(() => { this.remoteEdited(); })
              Button(this.remoteSaving ? '保存中…' : '保存配置')
                .width('100%').height(44)
                .backgroundColor(Theme.ACCENT_DEEP)
                .fontColor(Color.White).borderRadius(14)
                .enabled(!this.remoteSaving && !this.credentialLoading)
                .onClick(() => {
                  hapticLight();
                  this.saveRemote();
                })
              Text('这里只保存地址和账号，不打开网页；进入远程模式浏览仍走主界面。')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
            }
            Button(this.remoteSaving ? '处理中…' : '清除远程配置')
              .width('100%').height(44)
              .backgroundColor('rgba(230,109,122,0.12)')
              .fontColor(Theme.DANGER).borderRadius(14)
              .enabled(!this.remoteSaving)
              .onClick(() => { this.confirmClearRemote(); })
            Text('远程服务器：' + this.remoteTargetLabel)
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            Text('提示：捕获目标可独立选择，不受主界面当前浏览本地还是远程的限制。')
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).lineHeight(17)
          }
          .width('86%')
          .padding(18)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(18)
          .border({ width: 1, color: Theme.HAIRLINE })

          Column({ space: 10 }) {
            this.sectionCard('速记', '追加到哪个文件、哪个标题下')
            Text('速记文件路径').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ placeholder: '速记/{{今天}}.md', text: $$this.quickPath })
              .ruleInputStyle()
              .fontColor(Theme.TEXT_PRIMARY)
              .placeholderColor('#B8C0E4')
              .border({ width: 1, color: this.activeField === 'quick' ? Theme.ACCENT : 'rgba(255,255,255,0.22)' })
              .onEditChange((editing: boolean) => {
                if (editing) {
                  this.activeField = 'quick';
                }
              })
              .onChange(() => { this.edited(); })
            Text('速记追加标题（可选，不支持变量）').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ placeholder: '## 收件箱', text: $$this.quickHeading })
              .ruleInputStyle()
              .fontColor(Theme.TEXT_PRIMARY)
              .placeholderColor('#B8C0E4')
              .border({ width: 1, color: this.activeField === 'heading' ? Theme.ACCENT : 'rgba(255,255,255,0.22)' })
              .onEditChange((editing: boolean) => {
                if (editing) { this.activeField = 'heading'; }
              })
              .onChange(() => { this.edited(); })
            this.crumbs(this.quickPath, '示例标题', '速记', false)
            if (this.quickHeading.trim() !== '') {
              Text('追加到标题 ' + this.quickHeading.trim() + ' 下；标题不存在时补到文件末尾')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).lineHeight(17)
            }
          }
          .width('86%')
          .padding(18)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(18)
          .border({ width: 1, color: Theme.HAIRLINE })

          Column({ space: 10 }) {
            this.sectionCard('网页剪藏', '每篇剪藏单独一个笔记')
            Text('剪藏文件路径').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ placeholder: '剪藏/{{年}}/{{标题}}.md', text: $$this.clipPath })
              .ruleInputStyle()
              .fontColor(Theme.TEXT_PRIMARY)
              .placeholderColor('#B8C0E4')
              .border({ width: 1, color: this.activeField === 'clip' ? Theme.ACCENT : 'rgba(255,255,255,0.22)' })
              .onEditChange((editing: boolean) => {
                if (editing) {
                  this.activeField = 'clip';
                }
              })
              .onChange(() => { this.edited(); })
            this.crumbs(this.clipPath, '示例网页标题', 'example.com', true)
          }
          .width('86%')
          .padding(18)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(18)
          .border({ width: 1, color: Theme.HAIRLINE })

          Column({ space: 8 }) {
            Text('支持的变量').fontSize(Theme.FS_BODY).fontColor(Theme.TEXT_PRIMARY)
            Text('点击变量复制，再粘贴到路径输入框；速记标题不支持变量。')
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).lineHeight(17)
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.variables, (v: string) => {
                Text(v)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor('#C7CDF0')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(Theme.CHIP)
                  .borderRadius(12)
                  .margin({ right: 6, bottom: 6 })
                  .stateStyles({
                    pressed: { .scale({ x: 0.95, y: 0.95 }) }
                  })
                  .onClick(() => {
                    this.copyVariable(v);
                  })
              }, (v: string) => v)
            }
            Text('留空就用默认位置；自定义路径必须是库内的 .md 相对路径。')
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY).lineHeight(17)
          }
          .width('86%')
          .alignItems(HorizontalAlign.Start)

          if (this.error !== '') {
            Text(this.error)
              .fontSize(12)
              .fontColor(Theme.DANGER)
              .width('86%')
              .lineHeight(18)
          }
          if (this.saved !== '') {
            Text(this.saved)
              .fontSize(12)
              .fontColor(Theme.SUCCESS)
              .width('86%')
          }

          Row({ space: 10 }) {
            Button('恢复默认')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .enabled(this.vip)
              .fontColor('#C7CDF0')
              .backgroundColor(Theme.CHIP)
              .borderRadius(15)
              .onClick(() => { this.reset(); })
            Button('保存规则')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .enabled(this.vip)
              .fontColor(Color.White)
              .linearGradient({ angle: 90, colors: [[Theme.ACCENT, 0], [Theme.ACCENT_DEEP, 1]] })
              .borderRadius(15)
              .onClick(() => { this.save(); })
          }
          .width('86%')
          .margin({ top: 4, bottom: 34 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
