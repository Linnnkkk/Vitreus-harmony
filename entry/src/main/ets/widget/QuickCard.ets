// 速记小组件（1x2）：整卡点击 → postCardAction router → ShareAbility(mode=quicknote)
// 极简入口：卡片只负责识别和启动，不模拟输入界面。
let storage = new LocalStorage();

@Entry(storage)
@Component
struct QuickCard {
  build() {
    Stack() {
      Row({ space: 10 }) {
        Image($r('app.media.foreground'))
          .width(26)
          .height(26)
          .borderRadius(8)
          .opacity(0.88)
          .objectFit(ImageFit.Contain)

        Text('速记')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F3FF')
          .layoutWeight(1)

        Text('＋')
          .fontSize(20)
          .fontWeight(FontWeight.Lighter)
          .fontColor('#E8EAF8')
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.12)')
          .borderRadius(17)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 155,
      colors: [['#171A3D', 0], ['#252A65', 0.58], ['#1B1F49', 1]]
    })
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'ShareAbility',
        'params': {
          'mode': 'quicknote'
        }
      });
    })
  }
}
