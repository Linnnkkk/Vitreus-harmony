import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { BackButton } from '../components/BackButton';
import { VipService } from '../common/VipService';
import { CapturePathSettings } from '../common/CapturePathSettings';
import { CapturePathTemplate, CapturePathTemplates, CaptureTemplateValues } from '../common/CapturePathTemplate';
import { QuickCapture } from '../common/QuickCapture';
import { Theme } from '../common/Theme';
import { hapticLight } from '../common/Haptics';

@Entry
@Component
struct CaptureSettings {
  @State private quickPath: string = '';
  @State private quickHeading: string = '';
  @State private clipPath: string = '';
  @State private error: string = '';
  @State private saved: string = '';
  @State private vip: boolean = false;
  @State private previewAt: number = Date.now();
  @State private activeField: string = 'quick';
  private previewVaultName: string = 'vault';
  private quickCtl: TextInputController = new TextInputController();
  private clipCtl: TextInputController = new TextInputController();
  private headingCtl: TextInputController = new TextInputController();
  private readonly variables: string[] = ['{{年}}', '{{月}}', '{{日}}', '{{今天}}', '{{时间}}', '{{标题}}', '{{站点}}', '{{库名}}'];

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.previewAt = Date.now();
    this.refreshPreviewVault();
    this.vip = VipService.isVip();
  }

  private refreshPreviewVault(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const vaultName = QuickCapture.vaultName(QuickCapture.resolveVault(context));
    this.previewVaultName = vaultName !== '' ? vaultName : 'vault';
  }

  private load(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
    this.saved = '已保存';
  }

  private reset(): void {
    this.quickPath = '';
    this.quickHeading = '';
    this.clipPath = '';
    this.save();
  }

  private previewPath(template: string, title: string, site: string): string {
    if (template.trim() === '') {
      return '旧版固定路径';
    }
    const checked = CapturePathTemplate.expand(template, CapturePathTemplate.makeValues(
      this.previewAt, title, site, this.previewVaultName));
    return checked.valid ? checked.path : '模板无效：' + checked.error;
  }

  // 点变量标签：插入到当前聚焦路径框的光标处
  private insertVariable(v: string): void {
    if (!this.vip) {
      return;
    }
    hapticLight();
    if (this.activeField === 'clip') {
      const at = Math.min(this.clipCtl.getCaretOffset().index, this.clipPath.length);
      this.clipPath = this.clipPath.substring(0, at) + v + this.clipPath.substring(at);
    } else {
      const at = Math.min(this.quickCtl.getCaretOffset().index, this.quickPath.length);
      this.quickPath = this.quickPath.substring(0, at) + v + this.quickPath.substring(at);
    }
    this.error = '';
  }

  // 预设：一键填好常用组合
  private applyPreset(quick: string, heading: string, clip: string): void {
    if (!this.vip) {
      return;
    }
    hapticLight();
    this.quickPath = quick;
    this.quickHeading = heading;
    this.clipPath = clip;
    this.error = '';
    this.saved = '';
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
  presetChip(label: string, quick: string, heading: string, clip: string) {
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
        this.applyPreset(quick, heading, clip);
      })
  }

  // 路径面包屑预览：目录 › 目录 › 文件
  @Builder
  crumbs(template: string, title: string, site: string) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text('预览').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).margin({ right: 8 })
      if (template.trim() === '') {
        Text('旧版固定路径').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_SECONDARY)
      } else if (this.previewPath(template, title, site).startsWith('模板无效')) {
        Text(this.previewPath(template, title, site)).fontSize(Theme.FS_FOOT).fontColor(Theme.DANGER)
      } else {
        ForEach(this.pathSegments(this.previewPath(template, title, site)), (seg: string, idx: number) => {
          if (idx > 0) {
            Text('›').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).margin({ left: 4, right: 4 })
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

  @Builder
  fieldInput(placeholder: string, value: string, ctl: TextInputController, field: string, onText: (v: string) => void) {
    TextInput({ placeholder: placeholder, text: value, controller: ctl })
      .width('100%')
      .height(46)
      .enabled(this.vip)
      .fontColor(Theme.TEXT_PRIMARY)
      .placeholderColor('#5A649E')
      .backgroundColor('rgba(255,255,255,0.05)')
      .borderRadius(12)
      .border({ width: 1, color: this.activeField === field ? Theme.ACCENT : 'rgba(255,255,255,0.22)' })
      .padding({ left: 14, right: 14 })
      .onEditChange((editing: boolean) => {
        if (editing) {
          this.activeField = field;
        }
      })
      .onChange((v: string) => {
        onText(v);
        this.error = '';
      })
  }

  @Builder
  sectionCard(title: string, hint: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(Theme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
      Text(hint).fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
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
          Text('快捷捕获')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 110, bottom: 0 })
          Text('决定速记和网页剪藏落在笔记库的哪里')
            .fontSize(Theme.FS_CAPTION)
            .fontColor('#9AA3D8')
            .margin({ bottom: 6 })

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
            Text('常用方案').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
            Flex({ wrap: FlexWrap.Wrap }) {
              this.presetChip('按日期归档', '速记/{{今天}}.md', '', '剪藏/{{年}}/{{标题}}.md')
              this.presetChip('剪藏按站点', '', '', '剪藏/{{站点}}/{{标题}}.md')
              this.presetChip('写进日记', '日记/{{今天}}.md', '## 速记', '')
            }
          }
          .width('86%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.sectionCard('速记', '追加到哪个文件、哪个标题下')
            this.fieldInput('速记/{{今天}}.md', this.quickPath, this.quickCtl, 'quick', (v: string) => { this.quickPath = v; })
            this.fieldInput('## 收件箱（可选标题）', this.quickHeading, this.headingCtl, 'heading', (v: string) => { this.quickHeading = v; })
            this.crumbs(this.quickPath, '示例标题', '速记')
            if (this.quickHeading.trim() !== '') {
              Text('追加到标题 ' + this.quickHeading.trim() + ' 下；标题不存在时补到文件末尾')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
            }
          }
          .width('86%')
          .padding(18)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(18)
          .border({ width: 1, color: Theme.HAIRLINE })

          Column({ space: 10 }) {
            this.sectionCard('网页剪藏', '每篇剪藏单独一个笔记')
            this.fieldInput('剪藏/{{年}}/{{标题}}.md', this.clipPath, this.clipCtl, 'clip', (v: string) => { this.clipPath = v; })
            this.crumbs(this.clipPath, '示例网页标题', 'example.com')
          }
          .width('86%')
          .padding(18)
          .backgroundColor('rgba(255,255,255,0.05)')
          .borderRadius(18)
          .border({ width: 1, color: Theme.HAIRLINE })

          Column({ space: 8 }) {
            Text('点一下插入变量到光标处').fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.variables, (v: string) => {
                Text(v)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(this.vip ? '#C7CDF0' : Theme.TEXT_TERTIARY)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(Theme.CHIP)
                  .borderRadius(12)
                  .margin({ right: 6, bottom: 6 })
                  .stateStyles({
                    pressed: { .scale({ x: 0.95, y: 0.95 }) }
                  })
                  .onClick(() => {
                    this.insertVariable(v);
                  })
              }, (v: string) => v)
            }
            Text('留空会恢复旧版 Inbox.md / Clippings/ 位置；路径必须是库内的 .md 相对路径。')
              .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).lineHeight(17)
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
