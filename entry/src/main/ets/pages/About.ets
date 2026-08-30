import { router } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackButton } from '../components/BackButton';
import { hapticLight } from '../common/Haptics';
import { WaveBackground } from '../components/WaveBackground';
import { TypeWriter } from '../components/TypeWriter';

// 关于页：应用信息 / 开源协议 / 免责声明 / 反馈渠道（应用市场普遍要求
// app 内提供反馈入口与版权信息）
@Entry
@Component
struct About {
  // 背景动效联通：页面隐藏停表
  @State private bgVisible: boolean = true;
  @State private pressedRow: boolean = false;
  private githubUrl: string = 'https://github.com/Linnnkkk/Vitreus-harmony';
  @State private showDisclaimer: boolean = false;
  // credits 字幕滚动（参考 PPSSPP 鸿蒙版 about 页）
  @State private creditsY: number = 0;
  private creditsTimer: number = -1;

  aboutToAppear() {
    this.creditsTimer = setTimeout(() => { this.startCredits(); }, 1200);
  }

  aboutToDisappear() {
    clearTimeout(this.creditsTimer);
  }

  // 一轮：滚到底 → 停 2.5s → 瞬间回顶 → 停 0.8s → 再滚
  private startCredits(): void {
    this.getUIContext().animateTo({
      duration: 14000, curve: Curve.Linear,
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

  // 左滑/系统返回：与左上角 BackButton 同目标。
  // 全 app 用 replaceUrl 导航，路由栈只有 1 层，系统默认返回无处可 pop——必须显式指路
  onBackPress(): boolean {
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/ModeSelect' });
    }
    return true;
  }

  onPageShow() {
    this.bgVisible = true;
  }

  onPageHide() {
    this.bgVisible = false;
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
      // 与 ModeSelect 同款：PSP XMB 式波浪
      WaveBackground({ visible: this.bgVisible })

      Scroll() {
        Column() {
          Text('关于')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 110, bottom: 8 })
          TypeWriter({ text: 'Vitreus', fontSize: 14, speed: 70 })
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
          .backgroundEffect({ radius: 65, saturation: 1.3, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
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
          .backgroundEffect({ radius: 65, saturation: 1.3, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
          .alignItems(HorizontalAlign.Start)

          // ── 开源致谢（自动滚动 credits）──
          Column() {
            Column() {
              this.creditRow('Obsidian', '知识管理工具 · 本地模式素材由用户自备', 'https://obsidian.md')
              this.creditRow('ignis · Nystik-gh', '自建同步服务核心 · AGPL v3', 'https://github.com/Nystik-gh/ignis')
              this.creditRow('hqzing', 'libnode 鸿蒙沙箱适配补丁', 'https://github.com/hqzing')
              this.creditRow('ZhaoYuLiOfficial', 'Node.js 鸿蒙移植参考实现', 'https://github.com/ZhaoYuLiOfficial')
              this.creditRow('esbuild · Pillow', '构建与素材生成工具链', 'https://esbuild.github.io')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .translate({ y: this.creditsY })
          }
          .width('86%')
          .height(132)
          .margin({ top: 16 })
          .padding({ left: 22, right: 22 })
          .backgroundEffect({ radius: 65, saturation: 1.3, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
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
            .backgroundEffect({ radius: 65, saturation: 1.3, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
            .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
            .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
            .borderRadius(14)
            .border({ width: 1, color: '#2A2E5E' })
            .alignItems(HorizontalAlign.Start)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 12 }))
              .animation({ duration: 160, curve: Curve.EaseOut }))
          }

          // ── 显示排查：系统高对比度文字会把非纯白文字二值化+描边（深色界面误伤）──
          Column({ space: 8 }) {
            Text('显示排查')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
            Text('若界面文字发黑、带描边导致难读：是系统开启「高对比度文字」所致，与本应用无关。可在 设置 → 辅助功能 → 无障碍 → 高对比度文字 中关闭恢复。')
              .fontSize(12)
              .fontColor('#8F9BD8')
              .textAlign(TextAlign.Start)
          }
          .width('86%')
          .margin({ top: 12 })
          .padding({ left: 22, right: 22, top: 18, bottom: 18 })
          .backgroundEffect({ radius: 65, saturation: 1.3, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
          .borderRadius(14)
          .border({ width: 1, color: '#2A2E5E' })
          .alignItems(HorizontalAlign.Start)
          // ICP 备案号（工信部 801 号文要求显著展示；点击跳工信部查验官网）
          Text('苏ICP备2026062135号')
            .fontSize(11)
            .fontColor('#7A84BE')
            .margin({ top: 32 })
            .onClick(() => {
              hapticLight();
              this.openLink('https://beian.miit.gov.cn');
            })
          Text('AGPL v3 · 开源 · 无广告')
            .fontSize(11)
            .fontColor('#5A649E')
            .margin({ top: 6, bottom: 30 })
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
  // 方向感转场：前进从右滑入（旧页左移淡出）；返回从左回位（旧页向右滑走）
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 200, curve: Curve.EaseOut })
      .translate({ x: 320 })
      .opacity(0.3)
      .translate({ x: 320 })
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
      .opacity(0)
      .translate({ x: -110 })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
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
  creditRow(name: string, role: string, url: string) {
    Row() {
      Column({ space: 3 }) {
        Text(name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E2E6F8')
        Text(role)
          .fontSize(11)
          .fontColor('#8F9BD8')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(18)
        .fontColor('#5A649E')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      hapticLight();
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.openLink(url);
      } catch (e) {
        // 打不开就静默（无浏览器等极端场景）
      }
    })
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
      hapticLight();
      onTap();
    })
  }
}
