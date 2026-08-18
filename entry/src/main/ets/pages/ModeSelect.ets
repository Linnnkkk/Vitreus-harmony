import { router } from '@kit.ArkUI';

// 模式选择页：卡片式入口。设计语言（全 app 统一）：
//   底色深靛蓝渐变 + 玻璃卡片（半透明白描边）+ 无 emoji（SymbolGlyph 图标）
@Entry
@Component
struct ModeSelect {
  // 入场 stagger：标题→卡片→文字链 依次浮现（40ms 间隔起步）
  @State private t1: boolean = false;
  @State private t2: boolean = false;
  @State private t3: boolean = false;
  // 卡片按压反馈（scale 0.97）
  @State private pressedRemote: boolean = false;
  @State private pressedLocal: boolean = false;

  private enterFx(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
      .animation({ duration: 260, curve: Curve.EaseOut });
  }

  aboutToAppear() {
    setTimeout(() => { this.t1 = true; }, 30);
    setTimeout(() => { this.t2 = true; }, 100);
    setTimeout(() => { this.t3 = true; }, 170);
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
            .backgroundColor('#1A1E4A')
            .borderRadius(18)
            .border({ width: 1, color: '#3A4078' })
            .margin({ bottom: 16 })
            .align(Alignment.Start)
            .scale(this.pressedRemote ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 })
            .animation({ duration: 130, curve: Curve.EaseOut })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedRemote = true;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedRemote = false;
              }
            })
            .onClick(() => {
              AppStorage.setOrCreate('appMode', 'remote');
              router.replaceUrl({ url: 'pages/Login' });
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
            .backgroundColor('#1A1E4A')
            .borderRadius(18)
            .border({ width: 1, color: '#3A4078' })
            .margin({ bottom: 48 })
            .align(Alignment.Start)
            .scale(this.pressedLocal ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 })
            .animation({ duration: 130, curve: Curve.EaseOut })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressedLocal = true;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressedLocal = false;
              }
            })
            .onClick(() => {
              AppStorage.setOrCreate('appMode', 'local');
              router.replaceUrl({ url: 'pages/NodeTest' });
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
                AppStorage.setOrCreate('appMode', 'local');
                AppStorage.setOrCreate('forceImportPage', true);
                router.replaceUrl({ url: 'pages/NodeTest' });
              })

            Text('关于与反馈')
              .fontSize(13)
              .fontColor('#7A85C4')
              .padding({ top: 6, bottom: 10, left: 20, right: 20 })
              .onClick(() => {
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
