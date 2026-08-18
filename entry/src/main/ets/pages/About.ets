import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BackButton } from '../components/BackButton';

// 关于页：应用信息 / 开源协议 / 免责声明 / 反馈渠道（应用市场普遍要求
// app 内提供反馈入口与版权信息）
@Entry
@Component
struct About {
  private githubUrl: string = 'https://github.com/Linnnkkk/Vitreus-harmony';
  @State private showDisclaimer: boolean = false;

  // 系统浏览器打开（不用 Web 组件，避免页面栈复杂化）
  private openLink(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // startAbilityByType('browser')：系统浏览器打开，无需额外权限。
      // 本 SDK 签名：第三参必传 common.AbilityStartCallback（启动失败回调）
      const wantParam: Record<string, Object> = { 'uri': url };
      const cb: common.AbilityStartCallback = {
        onError: (code: number, name: string, message: string) => {
          console.error('[About] browser launch failed: ' + code + ' ' + name + ' ' + message);
        }
      };
      ctx.startAbilityByType('browser', wantParam, cb);
    } catch (e) {
      console.error('[About] open link failed: ' + JSON.stringify(e));
    }
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
        Column() {
          Text('关于')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 110, bottom: 8 })
          Text('Vitreus')
            .fontSize(14)
            .fontColor('#9AA3D8')
            .margin({ bottom: 40 })

          // ── 应用信息卡片 ──
          Column() {
            this.infoRow('应用', 'Vitreus — 非官方 Obsidian 移动端兼容工具')
            Divider().color('#2A2E5E').margin({ left: 4, right: 4 })
            this.infoRow('开源协议', 'AGPL v3')
            Divider().color('#2A2E5E').margin({ left: 4, right: 4 })
            this.infoRow('源代码', this.githubUrl)
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 10, bottom: 10 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: '#3A4078' })
          .alignItems(HorizontalAlign.Start)

          // ── 操作卡片 ──
          Column() {
            this.actionRow('免责声明', () => {
              this.showDisclaimer = !this.showDisclaimer;
            })
            Divider().color('#2A2E5E').margin({ left: 4, right: 4 })
            this.actionRow('源代码与反馈（GitHub）', () => {
              this.openLink(this.githubUrl);
            })
          }
          .width('86%')
          .margin({ top: 16 })
          .padding({ left: 22, right: 22, top: 10, bottom: 10 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: '#3A4078' })
          .alignItems(HorizontalAlign.Start)

          // ── 免责声明展开区 ──
          if (this.showDisclaimer) {
            Column({ space: 10 }) {
              Text('本应用为独立第三方开源工具，与 Obsidian / Dynalist Inc. 及 ignis 项目无任何隶属、合作或背书关系。')
                .fontSize(12)
                .fontColor('#8F9BD8')
                .textAlign(TextAlign.Start)
              Text('"Obsidian" 为其权利人的商标，此处仅用于描述兼容性。本应用不包含、不分发任何 Obsidian 受版权保护的内容；本地模式所需组件（.asar）由用户自行获取导入。')
                .fontSize(12)
                .fontColor('#8F9BD8')
                .textAlign(TextAlign.Start)
              Text('用户需自行承担使用第三方组件的风险；笔记数据始终由你自己的服务或设备保管。')
                .fontSize(12)
                .fontColor('#8F9BD8')
                .textAlign(TextAlign.Start)
            }
            .width('86%')
            .margin({ top: 12 })
            .padding({ left: 22, right: 22, top: 18, bottom: 18 })
            .backgroundColor('#161A3E')
            .borderRadius(14)
            .border({ width: 1, color: '#2A2E5E' })
            .alignItems(HorizontalAlign.Start)
          }

          Text('AGPL v3 · 开源免费 · 无广告')
            .fontSize(11)
            .fontColor('#5A649E')
            .margin({ top: 32, bottom: 30 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  infoRow(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#6A74A8')
      Text(value)
        .fontSize(14)
        .fontColor('#E2E6F8')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  actionRow(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#E2E6F8')
      Blank()
      Text('›')
        .fontSize(18)
        .fontColor('#6A74A8')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 4, right: 4 })
    .onClick(() => {
      onTap();
    })
  }
}
