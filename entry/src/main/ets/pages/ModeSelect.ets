import { router } from '@kit.ArkUI';

@Entry
@Component
struct ModeSelect {
  @State private localTip: string = '';

  build() {
    Column() {
      Text('Vitreus')
        .fontSize(42)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 150, bottom: 8 })
      Text('兼容 Obsidian 的运行环境')
        .fontSize(13)
        .fontColor('#CCFFFFFF')
        .margin({ bottom: 8 })
      Text('第三方独立工具 · 非官方产品')
        .fontSize(11)
        .fontColor('#88FFFFFF')
        .margin({ bottom: 64 })

      // VPS 模式：连接用户自己的远程 ignis 服务器
      Column() {
        Text('连接远程服务器')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2A2D6E')
        Text('填写你的 ignis 服务器地址与凭证')
          .fontSize(12)
          .fontColor('#992A2D6E')
          .margin({ top: 4 })
      }
      .width('100%')
      .height(78)
      .backgroundColor(Color.White)
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 16 })
      .onClick(() => {
        AppStorage.setOrCreate('appMode', 'vps');
        router.replaceUrl({ url: 'pages/Login' });
      })

      // 本地模式：ignis 跑在本机（攻关中）
      Column() {
        Text('本地运行')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text('使用你自备的 Obsidian 文件 · 开发中')
          .fontSize(12)
          .fontColor('#CCFFFFFF')
          .margin({ top: 4 })
      }
      .width('100%')
      .height(78)
      .backgroundColor('#FFFFFF22')
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .borderWidth(1)
      .borderColor('#33FFFFFF')
      .onClick(() => {
        this.getUIContext().getPromptAction().showToast({ message: '本地模式正在开发中，敬请期待' });
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
