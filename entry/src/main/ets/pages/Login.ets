import { router } from '@kit.ArkUI';

@Entry
@Component
struct Login {
  @State private inputUrl: string = '';
  @State private inputUser: string = '';
  @State private inputPwd: string = '';
  @State private authFailed: boolean = false;

  aboutToAppear() {
    // 主页凭证错误（401）跳回时，读取标志显示「账号或密码错误」
    this.authFailed = AppStorage.get<boolean>('authFailed') ?? false;
    AppStorage.setOrCreate('authFailed', false);
    // 回填上次填的服务器地址，方便用户
    this.inputUrl = AppStorage.get<string>('serverUrl') ?? '';
  }

  build() {
    Column() {
      Text('Vitreus')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 80, bottom: 10 })
      Text(this.authFailed ? '账号或密码错误，请重新输入' : '请输入服务器信息')
        .fontSize(14)
        .fontColor(this.authFailed ? '#FFD7D7' : '#CCFFFFFF')
        .margin({ bottom: 30 })

      TextInput({ placeholder: '服务器地址（如 https://your.server.com:6080/）', text: this.inputUrl })
        .width('100%')
        .height(50)
        .type(InputType.Normal)
        .backgroundColor(Color.White)
        .fontColor(Color.Black)
        .placeholderColor('#888888')
        .placeholderFont({ size: 13 })
        .borderRadius(10)
        .margin({ bottom: 14 })
        .onChange((v: string) => { this.inputUrl = v; })

      TextInput({ placeholder: '账号' })
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

      Button('连接')
        .width('100%')
        .height(50)
        .backgroundColor(Color.White)
        .fontColor('#2A2D6E')
        .fontWeight(FontWeight.Bold)
        .borderRadius(10)
        .onClick(() => {
          // 空输入校验
          if (this.inputUrl === '' || this.inputUser === '' || this.inputPwd === '') {
            this.getUIContext().getPromptAction().showToast({ message: '请填写完整信息' });
            return;
          }
          // 规范化地址：确保以 / 结尾
          let url = this.inputUrl.trim();
          if (!url.endsWith('/')) { url = url + '/'; }
          AppStorage.setOrCreate('serverUrl', url);
          AppStorage.setOrCreate('authUser', this.inputUser);
          AppStorage.setOrCreate('authPwd', this.inputPwd);
          // 页面跳转 = 密码保险箱「保存提示」的触发信号
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
