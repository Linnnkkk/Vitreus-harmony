import { router } from '@kit.ArkUI';

// 模式选择页：卡片式入口。设计语言（全 app 统一）：
//   底色深靛蓝渐变 + 玻璃卡片（半透明白描边）+ 无 emoji（SymbolGlyph 图标）
@Entry
@Component
struct ModeSelect {
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
        // 品牌区
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

        // ── 远程模式卡片 ──
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
        .width('86%')
        .height(88)
        .backgroundColor('#1A1E4A')
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })
        .margin({ bottom: 16 })
        .align(Alignment.Start)
        .onClick(() => {
          AppStorage.setOrCreate('appMode', 'remote');
          router.replaceUrl({ url: 'pages/Login' });
        })

        // ── 本地模式卡片 ──
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
        .width('86%')
        .height(88)
        .backgroundColor('#1A1E4A')
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })
        .margin({ bottom: 48 })
        .align(Alignment.Start)
        .onClick(() => {
          AppStorage.setOrCreate('appMode', 'local');
          router.replaceUrl({ url: 'pages/NodeTest' });
        })

        // ── 重新导入（次级操作，文字链样式）──
        Text('重新导入 Obsidian 资源')
          .fontSize(13)
          .fontColor('#7A85C4')
          .padding({ top: 10, bottom: 10, left: 20, right: 20 })
          .onClick(() => {
            AppStorage.setOrCreate('appMode', 'local');
            AppStorage.setOrCreate('forceImportPage', true);
            router.replaceUrl({ url: 'pages/NodeTest' });
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
