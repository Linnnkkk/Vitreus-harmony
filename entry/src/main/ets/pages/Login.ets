import { router } from '@kit.ArkUI';

@Entry
@Component
struct Login {
  @State private inputUrl: string = '';

  aboutToAppear() {
    // 回填上次地址
    this.inputUrl = AppStorage.get<string>('serverUrl') ?? '';
  }

  build() {
    Column() {
      // 返回模式选择
      Row() {
        Text('←')
          .fontSize(26)
          .fontColor('#FFFFFFCC')
          .onClick(() => { router.replaceUrl({ url: 'pages/ModeSelect' }); })
      }
      .width('100%')
      .padding({ top: 50, left: 22 })
      .margin({ bottom: 6 })

      Text('Vitreus')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 10, bottom: 10 })
      Text('请输入服务器地址')
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
          router.replaceUrl({ url: 'pages/Index' });
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 36, right: 36 })
    .backgroundColor('#2A2D6E')
    .alignItems(HorizontalAlign.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
