import { router } from '@kit.ArkUI';

@Entry
@Component
struct ModeSelect {
  build() {
    Column() {
      Text('Vitreus')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 100, bottom: 6 })

      Text('选择连接方式')
        .fontSize(14)
        .fontColor('#99FFFFFF')
        .margin({ bottom: 60 })

      // 远程模式（原主流程）
      Button('☁️ 远程服务器')
        .width('86%')
        .height(64)
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor(Color.White)
        .borderRadius(14)
        .border({ width: 1.5, color: '#66FFFFFF' })
        .margin({ bottom: 20 })
        .onClick(() => {
          AppStorage.setOrCreate('appMode', 'remote');
          router.replaceUrl({ url: 'pages/Login' });
        })

      Text('连接你部署在 VPS 上的 ignis，手机/平板随时随地访问')
        .fontSize(11)
        .fontColor('#80FFFFFF')
        .margin({ bottom: 40 })

      // 本地模式（Node 嵌入）
      Button('📱 本地运行')
        .width('86%')
        .height(64)
        .fontSize(18)
        .backgroundColor(Color.Transparent)
        .fontColor('#B8C0FF')
        .borderRadius(14)
        .border({ width: 1.5, color: '#50B8C0FF' })
        .margin({ bottom: 20 })
        .onClick(() => {
          AppStorage.setOrCreate('appMode', 'local');
          router.replaceUrl({ url: 'pages/NodeTest' });
        })

      Text('在本机内嵌 Node.js 运行时，完全离线使用')
        .fontSize(11)
        .fontColor('#80FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#2A2D6E')
    .alignItems(HorizontalAlign.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
