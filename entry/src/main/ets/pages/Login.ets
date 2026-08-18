import { router } from '@kit.ArkUI';
import { BackButton } from '../components/BackButton';

// 远程模式登录页：地址输入。卡片式输入区（设计语言同 ModeSelect）
@Entry
@Component
struct Login {
  @State private inputUrl: string = '';

  aboutToAppear() {
    // 回填上次地址
    this.inputUrl = AppStorage.get<string>('serverUrl') ?? '';
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

      Column() {
        Text('远程服务器')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 110, bottom: 8 })
        Text('输入你的 ignis 服务器地址')
          .fontSize(13)
          .fontColor('#9AA3D8')
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
            .backgroundColor('#141740')
            .fontColor(Color.White)
            .placeholderColor('#4A5290')
            .placeholderFont({ size: 14 })
            .borderRadius(12)
            .border({ width: 1, color: '#3A4078' })
            .padding({ left: 16, right: 16 })
            .onChange((v: string) => { this.inputUrl = v; })

          Text('需要登录的服务器，连接后会自动弹出登录框')
            .fontSize(12)
            .fontColor('#5A649E')
            .margin({ top: 14 })
        }
        .width('86%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 22, right: 22, top: 26, bottom: 26 })
        .backgroundColor('#1A1E4A')
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })

        // ── 连接按钮 ──
        Button('连 接')
          .width('86%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#4F5AC8')
          .fontColor(Color.White)
          .borderRadius(16)
          .margin({ top: 28 })
          .onClick(() => {
            if (this.inputUrl === '') {
              this.getUIContext().getPromptAction().showToast({ message: '请填写服务器地址' });
              return;
            }
            let url = this.inputUrl.trim();
            if (!url.endsWith('/')) { url = url + '/'; }
            AppStorage.setOrCreate('serverUrl', url);
            AppStorage.setOrCreate('appMode', 'remote');
            router.replaceUrl({ url: 'pages/Index' });
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
  pageTransition() {
    PageTransitionEnter({ duration: 260, curve: Curve.EaseOut })
      .translate({ y: 24 })
      .opacity(0)
    PageTransitionExit({ duration: 180, curve: Curve.EaseIn })
      .opacity(0)
  }
}
