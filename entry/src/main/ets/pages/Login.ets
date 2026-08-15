import { router } from '@kit.ArkUI';
import { BackButton } from '../components/BackButton';

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
      Column() {
        Text('Vitreus')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 90, bottom: 10 })

        Text('远程模式 · 请输入服务器地址')
          .fontSize(14)
          .fontColor('#CCFFFFFF')
          .margin({ bottom: 30 })

        TextInput({ placeholder: '服务器地址（如 https://your.server.com/）', text: this.inputUrl })
          .width('100%')
          .height(50)
          .type(InputType.Normal)
          .backgroundColor(Color.White)
          .fontColor(Color.Black)
          .placeholderColor('#888888')
          .placeholderFont({ size: 12 })
          .borderRadius(10)
          .margin({ bottom: 18 })
          .onChange((v: string) => { this.inputUrl = v; })

        Text('若服务器需要登录，连接后会自动弹出账号密码框（可被密码保险箱记住）')
          .fontSize(11)
          .fontColor('#88FFFFFF')
          .margin({ bottom: 30 })

        Button('连接')
          .width('100%')
          .height(50)
          .backgroundColor(Color.White)
          .fontColor('#2A2D6E')
          .fontWeight(FontWeight.Bold)
          .borderRadius(10)
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
      .padding({ left: 36, right: 36 })
      .alignItems(HorizontalAlign.Center)

      // 左上角常驻返回（回模式选择）
      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#2A2D6E')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
