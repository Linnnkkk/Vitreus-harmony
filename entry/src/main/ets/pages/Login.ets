import { router } from '@kit.ArkUI';
import { TypeWriter } from '../components/TypeWriter';
import { NetworkBackground } from '../components/AmbientBackground';
import { BackButton } from '../components/BackButton';

// 远程模式登录页：地址输入。卡片式输入区（设计语言同 ModeSelect）
@Entry
@Component
struct Login {
  // 背景动效联通：页面隐藏停表
  @State private bgVisible: boolean = true;
  @State private pressedConnect: boolean = false;
  @State private inputUrl: string = '';

  aboutToAppear() {
    // 回填上次地址
    this.inputUrl = AppStorage.get<string>('serverUrl') ?? '';
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
      // 底层：深靛蓝纵向渐变
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
      })

      // 子页环境动效（与主页面波浪不同款）
      NetworkBackground({ visible: this.bgVisible })

      Column() {
        Text('远程服务器')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 110, bottom: 8 })
        TypeWriter({ text: '输入你的服务器地址', fontSize: 13, speed: 20 })
          .margin({ bottom: 56 })

        // ── 输入卡片 ──
        Column() {
          Text('服务器地址')
            .fontSize(12)
            .fontColor('#7A85C4')
            .margin({ bottom: 8 })
          TextInput({ placeholder: 'https://your.server.com', text: this.inputUrl })
            .width('100%')
            .height(50)
            .type(InputType.Normal)
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#4A5290')
            .placeholderFont({ size: 14 })
            .borderRadius(12)
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
            .padding({ left: 16, right: 16 })
            .onChange((v: string) => { this.inputUrl = v; })

          Text('若服务器需要登录，连接后会自动提示')
            .fontSize(12)
            .fontColor('#5A649E')
            .margin({ top: 14 })
        }
        .width('86%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 22, right: 22, top: 26, bottom: 26 })
        .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
        .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
        .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255,255,255,0.32)' })

        // ── 连接按钮 ──
        Button('连 接')
          .width('86%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
          .fontColor(Color.White)
          .borderRadius(16)
          .margin({ top: 28 })
          .scale(this.pressedConnect ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
          .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.pressedConnect = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.pressedConnect = false;
            }
          })
          .onClick(() => {
            if (this.inputUrl === '') {
              this.getUIContext().getPromptAction().showToast({ message: '请填写服务器地址' });
              return;
            }
            let url = this.inputUrl.trim();
            if (!url.endsWith('/')) { url = url + '/'; }
            AppStorage.setOrCreate('serverUrl', url);
            AppStorage.setOrCreate('appMode', 'remote');
            router.pushUrl({ url: 'pages/Index' });
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      // 左上角常驻返回（回模式选择）
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
}
