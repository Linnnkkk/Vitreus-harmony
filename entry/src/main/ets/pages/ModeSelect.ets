import { router } from '@kit.ArkUI';

@Entry
@Component
struct ModeSelect {
  @State private vpsPressed: boolean = false;
  @State private localPressed: boolean = false;

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

      // VPS 模式：实心白底（主推）
      Column() {
        Text('连接远程服务器')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2A2D6E')
        Text('填写你的 ignis 服务器地址')
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
      .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: 6 })
      .scale(this.vpsPressed ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 })
      .animation({ duration: 120, curve: Curve.EaseInOut })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.vpsPressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.vpsPressed = false;
        }
      })
      .onClick(() => {
        AppStorage.setOrCreate('appMode', 'vps');
        router.replaceUrl({ url: 'pages/Login' });
      })

      // 本地模式：透明底 + 白边框（线框风格，白字在深蓝上清晰）
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
      .borderRadius(14)
      .backgroundColor(Color.Transparent)
      .borderWidth(1.5)
      .borderColor('#FFFFFF99')
      .justifyContent(FlexAlign.Center)
      .scale(this.localPressed ? { x: 0.97, y: 0.97 } : { x: 1, y: 1 })
      .animation({ duration: 120, curve: Curve.EaseInOut })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.localPressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.localPressed = false;
        }
      })
      .onClick(() => {
        AppStorage.setOrCreate('appMode', 'local');
        router.replaceUrl({ url: 'pages/LocalIndex' });
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
