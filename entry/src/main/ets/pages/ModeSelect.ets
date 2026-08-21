import { router } from '@kit.ArkUI';
import { hapticTap } from '../common/Haptics';

// 模式选择页：卡片式入口。设计语言（全 app 统一）：
//   底色深靛蓝渐变 + 玻璃卡片（半透明白描边）+ 无 emoji（SymbolGlyph 图标）
@Entry
@Component
struct ModeSelect {
  // 入场 stagger：标题→卡片→文字链 依次浮现（40ms 间隔起步）
  @State private t1: boolean = false;
  @State private t2: boolean = false;
  @State private t3: boolean = false;
  // 卡片按压反馈（spring 物理曲线）
  @State private pressedRemote: boolean = false;
  @State private pressedLocal: boolean = false;
  // 点击选中强调：亮边框+微放大，亮完再跳（点击有"被选中"的回应感）
  @State private selectedCard: string = '';
  // KenBurns 动态背景：渐变层极慢呼吸缩放，静而不死（参考 PPSSPP Background）
  @State private bgBreath: boolean = false;

  private enterFx(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
      .animation({ duration: 260, curve: Curve.EaseOut });
  }

  aboutToAppear() {
    setTimeout(() => { this.t1 = true; }, 30);
    setTimeout(() => { this.t2 = true; }, 100);
    setTimeout(() => { this.t3 = true; }, 170);
    // 呼吸起点延迟到入场 stagger 之后，避免抢第一眼的戏
    setTimeout(() => { this.bgBreath = true; }, 800);
  }

  // 选中卡片 → 强调动效亮起 → 短暂停留后跳转（不生硬的关键）
  private selectCard(card: string, mode: string, target: string): void {
    if (this.selectedCard !== '') {
      return; // 防连点重复跳转
    }
    this.selectedCard = card;
    hapticTap();
    AppStorage.setOrCreate('appMode', mode);
    setTimeout(() => {
      router.replaceUrl({ url: target });
    }, 170);
  }

  build() {
    Stack() {
      // 底层：深靛蓝纵向渐变
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
      })
      // KenBurns：8% 缩放来回漂移，26s 一个来回，慢到只剩潜意识感知
      .scale(this.bgBreath ? { x: 1.08, y: 1.08 } : { x: 1, y: 1 })
      .translate(this.bgBreath ? { x: -12, y: 8 } : { x: 0, y: 0 })
      .animation({ duration: 26000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })

      Column() {
        // 品牌区（stagger 第 1 拍）
        if (this.t1) {
          Column() {
            Text('VITREUS')
              .fontSize(15)
              .fontColor('#6E78B8')
              .fontWeight(FontWeight.Medium)
              .letterSpacing(6)
              .margin({ top: 110 })
            Text('选择连接方式')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .margin({ top: 10, bottom: 72 })
          }
          .transition(this.enterFx())
        }

        // ── 模式卡片（stagger 第 2 拍 + 按压缩放反馈）──
        if (this.t2) {
          Column() {
            Button({ stateEffect: true }) {
              Column({ space: 3 }) {
                Text('远程服务器')
                  .fontSize(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                Text('连接自建的线上服务')
                  .fontSize(12)
                  .fontColor('#9AA3D8')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 24, right: 24, top: 20, bottom: 20 })
            }
            .width('100%')
            .height(88)
            .backgroundColor(this.selectedCard === 'remote' ? '#252E5E' : '#1A1E4A')
            .borderRadius(18)
            .border({
              width: this.selectedCard === 'remote' ? 1.5 : 1,
              color: this.selectedCard === 'remote' ? '#7A88E8' : '#3A4078'
            })
            .margin({ bottom: 16 })
            .align(Alignment.Start)
            .scale(this.selectedCard === 'remote'
              ? { x: 1.02, y: 1.02 }
              : (this.pressedRemote ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 }))
            .animation({ duration: 160, curve: 'springMotion(0.3, 0.8)' })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedRemote = true;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedRemote = false;
              }
            })
            .onClick(() => {
              this.selectCard('remote', 'remote', 'pages/Login');
            })

            Button({ stateEffect: true }) {
              Column({ space: 3 }) {
                Text('本地运行')
                  .fontSize(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                Text('完全离线，在本机运行')
                  .fontSize(12)
                  .fontColor('#9AA3D8')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 24, right: 24, top: 20, bottom: 20 })
            }
            .width('100%')
            .height(88)
            .backgroundColor(this.selectedCard === 'local' ? '#252E5E' : '#1A1E4A')
            .borderRadius(18)
            .border({
              width: this.selectedCard === 'local' ? 1.5 : 1,
              color: this.selectedCard === 'local' ? '#7A88E8' : '#3A4078'
            })
            .margin({ bottom: 48 })
            .align(Alignment.Start)
            .scale(this.selectedCard === 'local'
              ? { x: 1.02, y: 1.02 }
              : (this.pressedLocal ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 }))
            .animation({ duration: 160, curve: 'springMotion(0.3, 0.8)' })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedLocal = true;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedLocal = false;
              }
            })
            .onClick(() => {
              this.selectCard('local', 'local', 'pages/NodeTest');
            })
          }
          .width('86%')
          .transition(this.enterFx())
        }

        // ── 文字链（stagger 第 3 拍）──
        if (this.t3) {
          Column() {
            Text('重新导入 Obsidian 资源')
              .fontSize(13)
              .fontColor('#7A85C4')
              .padding({ top: 10, bottom: 6, left: 20, right: 20 })
              .onClick(() => {
                hapticTap();
                AppStorage.setOrCreate('appMode', 'local');
                AppStorage.setOrCreate('forceImportPage', true);
                router.replaceUrl({ url: 'pages/NodeTest' });
              })

            Text('关于与反馈')
              .fontSize(13)
              .fontColor('#7A85C4')
              .padding({ top: 6, bottom: 10, left: 20, right: 20 })
              .onClick(() => {
                hapticTap();
                router.pushUrl({ url: 'pages/About' });
              })
          }
          .transition(this.enterFx())
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
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
}
