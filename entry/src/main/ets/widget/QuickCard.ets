// 速记小组件（2x2 静态卡）：整卡点击 → postCardAction router → ShareAbility(mode=quicknote)
// 卡片为静态布局（ArkTS 卡片不支持输入框），深蓝品牌渐变 + 棱镜前景图 + 引导文案
let storage = new LocalStorage();

@Entry(storage)
@Component
struct QuickCard {
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
        })

      Column({ space: 6 }) {
        Image($r('app.media.foreground'))
          .width(44)
          .height(44)
          .borderRadius(10)
          .objectFit(ImageFit.Contain)
        Text('速记')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text('一键记录到 Inbox')
          .fontSize(11)
          .fontColor('#9AA3D8')
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
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
