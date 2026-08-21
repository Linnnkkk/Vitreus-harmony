import { router } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackButton } from '../components/BackButton';
import { hapticTap } from '../common/Haptics';

// 关于页：应用信息 / 开源协议 / 免责声明 / 反馈渠道（应用市场普遍要求
// app 内提供反馈入口与版权信息）
@Entry
@Component
struct About {
  @State private pressedRow: boolean = false;
  private githubUrl: string = 'https://github.com/Linnnkkk/Vitreus-harmony';
  @State private showDisclaimer: boolean = false;
  // credits 字幕滚动（参考 PPSSPP 鸿蒙版 about 页）
  @State private creditsY: number = 0;
  private creditsTimer: number = -1;
  // KenBurns 呼吸背景（与 ModeSelect 同款）
  @State private bgBreath: boolean = false;

  aboutToAppear() {
    setTimeout(() => { this.bgBreath = true; }, 800);
    this.creditsTimer = setTimeout(() => { this.startCredits(); }, 1200);
  }

  aboutToDisappear() {
    clearTimeout(this.creditsTimer);
  }

  // 一轮：滚到底 → 停 2.5s → 瞬间回顶 → 停 0.8s → 再滚
  private startCredits(): void {
    this.getUIContext().animateTo({
      duration: 18000, curve: Curve.Linear,
      onFinish: () => {
        this.creditsTimer = setTimeout(() => { this.resetCredits(); }, 2500);
      }
    }, () => {
      this.creditsY = -240;
    });
  }

  private resetCredits(): void {
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.creditsY = 0;
    });
    this.creditsTimer = setTimeout(() => { this.startCredits(); }, 800);
  }

  // 拉起默认浏览器打开链接：隐式 Want（action=viewData + browsable），
  // 官方文档《鸿蒙原生应用如何拉起系统浏览器》的标准做法。
  // （startAbilityByType('browser') 在部分设备无响应，弃用）
  private openLink(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      ctx.startAbility(want)
        .then(() => {
          console.info('[About] browser launched');
        })
        .catch((err: BusinessError) => {
          console.error(`[About] startAbility failed: ${err.code} ${err.message}`);
        });
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
      .scale(this.bgBreath ? { x: 1.08, y: 1.08 } : { x: 1, y: 1 })
      .translate(this.bgBreath ? { x: -12, y: 8 } : { x: 0, y: 0 })
      .animation({ duration: 26000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })

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
            this.infoRow('应用', 'Vitreus — 非官方 Obsidian 鸿蒙端兼容工具')
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

          // ── 开源致谢（自动滚动 credits）──
          Column() {
            Column() {
              this.creditRow('Obsidian', '知识管理工具 · 本地模式素材由用户自备')
              this.creditRow('ignis · Nystik-gh', '自建同步服务核心 · AGPL v3')
              this.creditRow('hqzing', 'libnode 鸿蒙沙箱适配补丁')
              this.creditRow('ZhaoYuLiOfficial', 'Node.js 鸿蒙移植参考实现')
              this.creditRow('esbuild · Pillow', '构建与素材生成工具链')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .translate({ y: this.creditsY })
          }
          .width('86%')
          .height(132)
          .margin({ top: 16 })
          .padding({ left: 22, right: 22 })
          .backgroundColor('#161A3E')
          .borderRadius(14)
          .border({ width: 1, color: '#2A2E5E' })
          .clip(true)
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
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 12 }))
              .animation({ duration: 220, curve: Curve.EaseOut }))
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

  // 页面转场：进入=淡入+上浮，退出=淡出（全 app 统一节奏）
  pageTransition() {
    PageTransitionEnter({ duration: 260, curve: Curve.EaseOut })
      .translate({ y: 24 })
      .opacity(0)
    PageTransitionExit({ duration: 180, curve: Curve.EaseIn })
      .opacity(0)
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
  creditRow(name: string, role: string) {
    Column({ space: 3 }) {
      Text(name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E2E6F8')
      Text(role)
        .fontSize(11)
        .fontColor('#8F9BD8')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 10, bottom: 10 })
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
    .scale(this.pressedRow ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
    .animation({ duration: 130, curve: 'springMotion(0.3, 0.8)' })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedRow = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedRow = false;
      }
    })
    .onClick(() => {
      hapticTap();
      onTap();
    })
  }
}
