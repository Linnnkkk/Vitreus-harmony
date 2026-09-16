// 速记小组件（2x2）：整卡点击 → postCardAction router → ShareAbility(mode=quicknote)
// 卡片为静态布局（ArkTS 卡片不支持输入框），深蓝品牌渐变 + 棱镜 logo + 行动提示
let storage = new LocalStorage();

@Entry(storage)
@Component
struct QuickCard {
  build() {
    Stack() {
      // 品牌渐变底
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 155,
          colors: [['#23265C', 0], ['#2E3172', 0.52], ['#1B1E47', 1]]
        })

      Column() {
        // 头部：棱镜 logo + 标题
        Row({ space: 10 }) {
          Image($r('app.media.foreground'))
            .width(36)
            .height(36)
            .borderRadius(10)
            .objectFit(ImageFit.Contain)

          Column({ space: 1 }) {
            Text('速记')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('存入笔记库')
              .fontSize(10)
              .fontColor('#9AA3D8')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        // 行动提示胶囊
        Text('＋ 写一条')
          .fontSize(11)
          .fontColor('#E6E9FF')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('rgba(255,255,255,0.16)')
          .borderRadius(14)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .borderRadius(20)
    .border({ width: 1, color: 'rgba(255,255,255,0.14)' })
    .clip(true)
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
