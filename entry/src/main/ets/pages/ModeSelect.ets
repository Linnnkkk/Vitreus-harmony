import { router } from '@kit.ArkUI';
import { hapticLight, hapticSelect } from '../common/Haptics';
import { WaveBackground } from '../components/WaveBackground';
import { TypeWriter } from '../components/TypeWriter';

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
  // 卡片选中涟漪
  @State private rippleCard: string = '';
  @State private rippleOut: boolean = false;
  // 涟漪跟手：记录按下的触点坐标
  @State private rippleX: number = 0;
  @State private rippleY: number = 0;

  // 涟漪：按下瞬间就从中心扩散（点击后 170ms 就跳页，晚了看不见）
  private startRipple(card: string, x: number, y: number): void {
    if (this.rippleCard !== '') {
      return;
    }
    this.rippleX = x;
    this.rippleY = y;
    this.rippleCard = card;
    this.rippleOut = false;
    this.getUIContext().animateTo({
      duration: 520, curve: Curve.EaseOut,
      onFinish: () => {
        this.rippleCard = '';
        this.rippleOut = false;
      }
    }, () => {
      this.rippleOut = true;
    });
  }

  private enterFx(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
      .animation({ duration: 260, curve: Curve.EaseOut });
  }

  aboutToAppear() {
    setTimeout(() => { this.t1 = true; }, 30);
    setTimeout(() => { this.t2 = true; }, 100);
    setTimeout(() => { this.t3 = true; }, 170);
  }

  // 选中卡片 → 强调动效亮起 → 短暂停留后跳转（不生硬的关键）
  private selectCard(card: string, mode: string, target: string): void {
    if (this.selectedCard !== '') {
      return; // 防连点重复跳转
    }
    this.selectedCard = card;
    hapticSelect();
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

      // PSP XMB 式波浪（PPSSPP WaveAnimation 移植）：底部两条正弦波带缓慢流动
      WaveBackground()

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
            TypeWriter({ text: '选择连接方式', size: 30, color: '#FFFFFF', bold: true })
              .margin({ top: 10, bottom: 72 })
          }
          .transition(this.enterFx())
        }

        // ── 模式卡片（stagger 第 2 拍 + 按压缩放反馈）──
        if (this.t2) {
          Column() {
            Stack({ alignContent: Alignment.Center }) {
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
            .align(Alignment.Start)
            .scale(this.selectedCard === 'remote'
              ? { x: 1.02, y: 1.02 }
              : (this.pressedRemote ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 }))
            .animation({ duration: 160, curve: 'springMotion(0.3, 0.8)' })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedRemote = true;
                this.startRipple('remote', e.touches[0].x, e.touches[0].y);
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedRemote = false;
              }
            })
            .onClick(() => {
              this.selectCard('remote', 'remote', 'pages/Login');
            })

            // 涟漪光圈：选中瞬间从中心扩散
            if (this.rippleCard === 'remote') {
              Column() {
              }
              .width(60)
              .height(60)
              .borderRadius(30)
              .radialGradient({
                center: ['50%', '50%'],
                radius: 30,
                colors: [['rgba(122,136,232,0.42)', 0], ['rgba(122,136,232,0)', 1]]
              })
              .scale(this.rippleOut ? { x: 3.4, y: 3.4 } : { x: 0.3, y: 0.3 })
              .opacity(this.rippleOut ? 0 : 1)
              .position({ x: this.rippleX - 30, y: this.rippleY - 30 })
            }
            }
            .width('100%')
            .margin({ bottom: 16 })

            Stack({ alignContent: Alignment.Center }) {
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
            .align(Alignment.Start)
            .scale(this.selectedCard === 'local'
              ? { x: 1.02, y: 1.02 }
              : (this.pressedLocal ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 }))
            .animation({ duration: 160, curve: 'springMotion(0.3, 0.8)' })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedLocal = true;
                this.startRipple('local', e.touches[0].x, e.touches[0].y);
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedLocal = false;
              }
            })
            .onClick(() => {
              this.selectCard('local', 'local', 'pages/NodeTest');
            })

            if (this.rippleCard === 'local') {
              Column() {
              }
              .width(60)
              .height(60)
              .borderRadius(30)
              .radialGradient({
                center: ['50%', '50%'],
                radius: 30,
                colors: [['rgba(122,136,232,0.42)', 0], ['rgba(122,136,232,0)', 1]]
              })
              .scale(this.rippleOut ? { x: 3.4, y: 3.4 } : { x: 0.3, y: 0.3 })
              .opacity(this.rippleOut ? 0 : 1)
              .position({ x: this.rippleX - 30, y: this.rippleY - 30 })
            }
            }
            .width('100%')
            .margin({ bottom: 48 })
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
                hapticLight();
                AppStorage.setOrCreate('appMode', 'local');
                AppStorage.setOrCreate('forceImportPage', true);
                router.replaceUrl({ url: 'pages/NodeTest' });
              })

            Text('关于与反馈')
              .fontSize(13)
              .fontColor('#7A85C4')
              .padding({ top: 6, bottom: 10, left: 20, right: 20 })
              .onClick(() => {
                hapticLight();
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
