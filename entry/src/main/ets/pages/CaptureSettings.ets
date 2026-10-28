import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { BackButton } from '../components/BackButton';
import { VipService } from '../common/VipService';
import { CapturePathSettings } from '../common/CapturePathSettings';
import { CapturePathTemplate, CapturePathTemplates, CaptureTemplateValues } from '../common/CapturePathTemplate';
import { QuickCapture } from '../common/QuickCapture';
import { RemoteCapture } from '../common/RemoteCapture';
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
  @State private openStartup: boolean = false;
  @State private openVault: boolean = false;
  @State private openCapture: boolean = false;
  private pageAlive: boolean = false;
  private previewVaultName: string = 'vault';
  private readonly variables: string[] = ['{{年}}', '{{月}}', '{{日}}', '{{今天}}', '{{时间}}', '{{标题}}', '{{站点}}', '{{库名}}'];

  aboutToAppear(): void {
    this.pageAlive = true;
    this.load();
  }

  onPageHide(): void { this.pageAlive = false; }
  aboutToDisappear(): void { this.onPageHide(); }
  onPageShow(): void {
    this.pageAlive = true;
    this.previewAt = Date.now();
    this.refreshPreviewVault();
    this.vip = VipService.isVip();
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
            .backgroundColor(Theme.CHIP)
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
    .backgroundColor(Theme.CONFIG_FIELD).border({ width: 1, color: Theme.CONFIG_BORDER })
    .borderRadius(Theme.R_CONTROL)
    .padding({ left: 14, right: 14 })
  }

  // 远程配置不是会员功能，不受 vip 限制。
  @Styles
  plainInputStyle() {
    .width('100%')
    .height(46)
    .backgroundColor(Theme.CONFIG_FIELD).border({ width: 1, color: Theme.CONFIG_BORDER })
    .borderRadius(Theme.R_CONTROL)
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

  // 分组卡片：与 WebDAV 设置页一致的半透明面 + 细描边
  @Styles
  groupCard() {
    .width('100%')
    .backgroundColor('rgba(255,255,255,0.04)')
    .borderRadius(20)
    .border({ width: 1, color: 'rgba(255,255,255,0.10)' })
  }

  @Builder
  groupDivider() {
    Divider().color('rgba(255,255,255,0.08)').strokeWidth(0.5)
  }

  // 分组标题行：标题 + 说明，右侧展开箭头
  @Builder
  groupRow(title: string, hint: string, expanded: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(Theme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
        Text(hint).fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor(['#8C97CE'])
        .rotate({ angle: expanded ? 180 : 0 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 15, bottom: 15 })
    .onClick(() => {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, onTap);
    })
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
        colors: [[Theme.PAGE_BG_START, 0], [Theme.PAGE_BG_MIDDLE, 0.55], [Theme.PAGE_BG_END, 1]]
      })

      Column({ space: 14 }) {
        Row() {
          Text('其他配置').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
        }.width('100%').padding({ left: 58 }).height(44)

        Scroll() {
          Column({ space: 12 }) {
            // ── 置顶常驻：更换组件包 ──
            Column() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('更换组件包').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                  Text('重新导入用于打开 Vault 的组件包').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor(['#8C97CE'])
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 15, bottom: 15 })
              .onClick(() => {
                hapticLight();
                AppStorage.setOrCreate('forceImportPage', true);
                router.pushUrl({ url: 'pages/NodeTest' });
              })
            }.groupCard()

            // ── 启动偏好 ──
            Column() {
              this.groupRow('启动偏好', '设置下次打开 App 时的入口', this.openStartup,
                () => { hapticLight(); this.openStartup = !this.openStartup; })
              if (this.openStartup) {
                Column({ space: 0 }) {
                  this.groupDivider()
                  Row({ space: 12 }) {
                    Column({ space: 3 }) {
                      Text('记住上次使用的位置').fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_PRIMARY)
                      Text('下次打开直接回到上次的页面').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: this.rememberMode })
                      .selectedColor(Theme.ACCENT)
                      .onChange((value: boolean) => { this.changeRememberMode(value); })
                  }
                  .width('100%')
                  .padding({ left: 18, right: 18, top: 14, bottom: 16 })
                }.width('100%').alignItems(HorizontalAlign.Start)
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 })))
              }
            }.groupCard()

            // ── 笔记库 ──
            Column() {
              this.groupRow('笔记库', '管理笔记库连接', this.openVault,
                () => { hapticLight(); this.openVault = !this.openVault; })
              if (this.openVault) {
                Column({ space: 0 }) {
                  this.groupDivider()
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text('WebDAV 远程库').fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_PRIMARY)
                      Text('把笔记放在网盘上，手机直接连接').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text('会员')
                      .fontSize(10)
                      .fontColor(Theme.WARN)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('rgba(242,198,109,0.12)')
                      .borderRadius(6)
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor(['#8C97CE'])
                  }
                  .width('100%')
                  .padding({ left: 18, right: 18, top: 14, bottom: 16 })
                  .onClick(() => {
                    hapticLight();
                    router.pushUrl({ url: 'pages/WebDavSettingsPage' });
                  })
                }.width('100%').alignItems(HorizontalAlign.Start)
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 })))
              }
            }.groupCard()

            // ── 速记与剪藏 ──
            Column() {
              this.groupRow('速记与剪藏', '保存位置、归档方式与路径变量', this.openCapture,
                () => { hapticLight(); this.openCapture = !this.openCapture; })
              if (this.openCapture) {
                Column({ space: 0 }) {
                  this.groupDivider()
                  Column({ space: 14 }) {
                    if (!this.vip) {
                      Column({ space: 8 }) {
                        Text('自定义存储规则是会员功能，下方可以先预览效果。')
                          .fontSize(Theme.FS_FOOT).fontColor(Theme.WARN).lineHeight(17).width('100%')
                        Button('查看会员权益')
                          .width('100%').height(40).fontSize(13)
                          .fontColor(Theme.TEXT_PRIMARY)
                          .backgroundColor(Theme.CHIP)
                          .borderRadius(Theme.R_CONTROL)
                          .onClick(() => { router.pushUrl({ url: 'pages/VipPanelPage' }); })
                      }.width('100%').alignItems(HorizontalAlign.Start)
                    }

                    Column({ space: 8 }) {
                      Text('常用方案').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                      Flex({ wrap: FlexWrap.Wrap }) {
                        this.presetChip('按日期归档', 'date')
                        this.presetChip('剪藏按站点', 'site')
                        this.presetChip('写进日记', 'diary')
                      }
                    }.width('100%').alignItems(HorizontalAlign.Start)

                    Column({ space: 8 }) {
                      this.sectionCard('速记保存规则', '追加到哪个文件、哪个标题下')
                      Text('速记文件路径').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
                      TextInput({ placeholder: '速记/{{今天}}.md', text: $$this.quickPath })
                        .ruleInputStyle()
                        .fontColor(Theme.TEXT_PRIMARY)
                        .placeholderColor(Theme.TEXT_SECONDARY)
                        .border({ width: 1, color: this.activeField === 'quick' ? Theme.ACCENT : Theme.CONFIG_BORDER })
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
                        .placeholderColor(Theme.TEXT_SECONDARY)
                        .border({ width: 1, color: this.activeField === 'heading' ? Theme.ACCENT : Theme.CONFIG_BORDER })
                        .onEditChange((editing: boolean) => {
                          if (editing) { this.activeField = 'heading'; }
                        })
                        .onChange(() => { this.edited(); })
                      this.crumbs(this.quickPath, '示例标题', '速记', false)
                      if (this.quickHeading.trim() !== '') {
                        Text('追加到标题 ' + this.quickHeading.trim() + ' 下；标题不存在时补到文件末尾')
                          .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
                      }
                    }.width('100%').alignItems(HorizontalAlign.Start)

                    Column({ space: 8 }) {
                      this.sectionCard('网页剪藏保存规则', '每篇剪藏单独一个笔记')
                      Text('剪藏文件路径').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
                      TextInput({ placeholder: '剪藏/{{年}}/{{标题}}.md', text: $$this.clipPath })
                        .ruleInputStyle()
                        .fontColor(Theme.TEXT_PRIMARY)
                        .placeholderColor(Theme.TEXT_SECONDARY)
                        .border({ width: 1, color: this.activeField === 'clip' ? Theme.ACCENT : Theme.CONFIG_BORDER })
                        .onEditChange((editing: boolean) => {
                          if (editing) {
                            this.activeField = 'clip';
                          }
                        })
                        .onChange(() => { this.edited(); })
                      this.crumbs(this.clipPath, '示例网页标题', 'example.com', true)
                    }.width('100%').alignItems(HorizontalAlign.Start)

                    Column({ space: 8 }) {
                      Text('支持的变量').fontSize(Theme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                      Text('点击变量复制，再粘贴到路径输入框；速记标题不支持变量。')
                        .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(this.variables, (v: string) => {
                          Text(v)
                            .fontSize(Theme.FS_FOOT)
                            .fontColor(Theme.TEXT_SECONDARY)
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
                        .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
                    }.width('100%').alignItems(HorizontalAlign.Start)

                    if (this.error !== '') {
                      Text(this.error)
                        .fontSize(Theme.FS_FOOT).fontColor(Theme.DANGER).width('100%').lineHeight(17)
                    }
                    if (this.saved !== '') {
                      Text(this.saved)
                        .fontSize(Theme.FS_FOOT).fontColor(Theme.SUCCESS).width('100%')
                    }

                    Row({ space: 10 }) {
                      Button('恢复默认')
                        .layoutWeight(1).height(44).fontSize(14)
                        .enabled(this.vip)
                        .fontColor(Theme.TEXT_SECONDARY)
                        .backgroundColor(Theme.CHIP)
                        .borderRadius(Theme.R_CONTROL)
                        .onClick(() => { this.reset(); })
                      Button('保存规则')
                        .layoutWeight(1).height(44).fontSize(14)
                        .enabled(this.vip)
                        .fontColor(Theme.TEXT_PRIMARY)
                        .backgroundColor(Theme.ACCENT_DEEP)
                        .borderRadius(Theme.R_CONTROL)
                        .onClick(() => { this.save(); })
                    }.width('100%')
                  }
                  .width('100%')
                  .padding({ left: 18, right: 18, top: 16, bottom: 18 })
                  .alignItems(HorizontalAlign.Start)
                }.width('100%').alignItems(HorizontalAlign.Start)
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 })))
              }
            }.groupCard()
          }
          .width('100%')
          .padding({ bottom: 28 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: 56 })

      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
