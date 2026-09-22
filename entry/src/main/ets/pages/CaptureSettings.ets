import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { BackButton } from '../components/BackButton';
import { VipService } from '../common/VipService';
import { CapturePathSettings } from '../common/CapturePathSettings';
import { CapturePathTemplate, CapturePathTemplates, CaptureTemplateValues } from '../common/CapturePathTemplate';
import { QuickCapture } from '../common/QuickCapture';

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

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.previewAt = Date.now();
    this.vip = VipService.isVip();
  }

  private load(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const settings = CapturePathSettings.load(context);
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
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const vault = QuickCapture.resolveVault(context);
    const vaultName = QuickCapture.vaultName(vault);
    const shownVault = vaultName !== '' ? vaultName : 'vault';
    const checked = CapturePathTemplate.expand(template, CapturePathTemplate.makeValues(
      this.previewAt, title, site, shownVault));
    return checked.valid ? checked.path : '模板无效：' + checked.error;
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
            .margin({ top: 110, bottom: 4 })
          Text('会员可分别自定义速记和剪藏的 Markdown 路径')
            .fontSize(13)
            .fontColor('#9AA3D8')
            .margin({ bottom: 20 })

          Column({ space: 8 }) {
            Text('速记路径模板')
              .fontSize(12)
              .fontColor('#7A85C4')
            TextInput({ placeholder: '速记/{{今天}}.md', text: this.quickPath })
              .width('100%')
              .height(48)
              .enabled(this.vip)
              .fontColor(Color.White)
              .placeholderColor('#5A649E')
              .backgroundColor('rgba(255,255,255,0.05)')
              .borderRadius(12)
              .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => { this.quickPath = v; this.error = ''; })
            Text('速记追加标题（可选）')
              .fontSize(12)
              .fontColor('#7A85C4')
            TextInput({ placeholder: '## 收件箱', text: this.quickHeading })
              .width('100%')
              .height(48)
              .enabled(this.vip)
              .fontColor(Color.White)
              .placeholderColor('#5A649E')
              .backgroundColor('rgba(255,255,255,0.05)')
              .borderRadius(12)
              .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => { this.quickHeading = v; this.error = ''; })
            Text('填 # 标题；留空则继续追加到文件末尾。标题不存在时会自动补到文件末尾。')
              .fontSize(11)
              .fontColor('#6A74A8')
              .lineHeight(18)
            Text('剪藏路径模板')
              .fontSize(12)
              .fontColor('#7A85C4')
            TextInput({ placeholder: '剪藏/{{年}}/{{标题}}.md', text: this.clipPath })
              .width('100%')
              .height(48)
              .enabled(this.vip)
              .fontColor(Color.White)
              .placeholderColor('#5A649E')
              .backgroundColor('rgba(255,255,255,0.05)')
              .borderRadius(12)
              .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => { this.clipPath = v; this.error = ''; })
            Text('变量：{{年}} {{月}} {{日}} {{今天}} {{时间}} {{标题}} {{站点}} {{库名}}')
              .fontSize(11)
              .fontColor('#8F9BD8')
              .lineHeight(18)
            Text('留空会恢复旧版 Inbox.md / Clippings/ 保存位置；路径必须是 vault 内的 .md 相对路径。')
              .fontSize(11)
              .fontColor('#6A74A8')
              .lineHeight(18)
            Text('速记示例：' + this.previewPath(this.quickPath, '示例标题', '速记') +
              (this.quickHeading.trim() !== '' ? ' → ' + this.quickHeading.trim() : ' → 文件末尾'))
              .fontSize(11)
              .fontColor('#A9B4F0')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('剪藏示例：' + this.previewPath(this.clipPath, '示例网页标题', 'example.com'))
              .fontSize(11)
              .fontColor('#A9B4F0')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 22, bottom: 22 })
          .backgroundColor('rgba(255,255,255,0.04)')
          .borderRadius(18)
          .border({ width: 1, color: 'rgba(255,255,255,0.22)' })

          if (!this.vip) {
            Text('当前不是有效会员，自定义规则仅可查看，基础速记和剪藏仍可正常使用。')
              .fontSize(12)
              .fontColor('#F2C66D')
              .width('86%')
              .lineHeight(18)
            Button('查看会员权益')
              .width('86%')
              .height(46)
              .fontSize(14)
              .fontColor(Color.White)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .borderRadius(15)
              .onClick(() => {
                router.pushUrl({ url: 'pages/VipPanelPage' });
              })
          }

          if (this.error !== '') {
            Text(this.error)
              .fontSize(12)
              .fontColor('#FF8D8D')
              .width('86%')
              .lineHeight(18)
          }
          if (this.saved !== '') {
            Text(this.saved)
              .fontSize(12)
              .fontColor('#9BE8B4')
              .width('86%')
          }

          Row({ space: 10 }) {
            Button('恢复默认')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .enabled(this.vip)
              .fontColor('#C7CDF0')
              .backgroundColor('rgba(255,255,255,0.10)')
              .borderRadius(15)
              .onClick(() => { this.reset(); })
            Button('保存规则')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .enabled(this.vip)
              .fontColor(Color.White)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
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

      BackButton({ target: 'pages/About' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
