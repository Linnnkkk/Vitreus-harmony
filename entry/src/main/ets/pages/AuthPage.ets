import { router } from '@kit.ArkUI';

@Entry
@Component
struct AuthPage {
  @State private inputUser: string = '';
  @State private inputPwd: string = '';

  aboutToAppear() {
    // 回填账号（持久化）；密码不回填，靠保险箱 AutoFill 填
    this.inputUser = AppStorage.get<string>('authUser') ?? '';
  }

  build() {
    Column() {
      Text('服务器需要登录')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 120, bottom: 8 })
      Text(AppStorage.get<string>('serverUrl') ?? '')
        .fontSize(12)
        .fontColor('#88FFFFFF')
        .margin({ bottom: 30 })

      TextInput({ placeholder: '账号', text: this.inputUser })
        .width('100%')
        .height(50)
        .type(InputType.USER_NAME)
        .enableAutoFill(true)
        .backgroundColor(Color.White)
        .fontColor(Color.Black)
        .placeholderColor('#888888')
        .borderRadius(10)
        .margin({ bottom: 14 })
        .onChange((v: string) => { this.inputUser = v; })
      TextInput({ placeholder: '密码' })
        .width('100%')
        .height(50)
        .type(InputType.Password)
        .enableAutoFill(true)
        .backgroundColor(Color.White)
        .fontColor(Color.Black)
        .placeholderColor('#888888')
        .borderRadius(10)
        .margin({ bottom: 30 })
        .onChange((v: string) => { this.inputPwd = v; })

      Button('登录')
        .width('100%')
        .height(50)
        .backgroundColor(Color.White)
        .fontColor('#2A2D6E')
        .fontWeight(FontWeight.Bold)
        .borderRadius(10)
        .onClick(() => {
          if (this.inputUser === '' || this.inputPwd === '') {
            this.getUIContext().getPromptAction().showToast({ message: '请输入账号和密码' });
            return;
          }
          // 账号存 AppStorage（会持久化）；密码只存内存（保险箱记住，不持久化磁盘）
          AppStorage.setOrCreate('authUser', this.inputUser.trim());
          AppStorage.setOrCreate('authPwd', this.inputPwd);
          // router 跳转 = 密码保险箱「保存提示」触发信号
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
