// 速记小组件（2x2）：整卡点击 → postCardAction router → ShareAbility(mode=quicknote)
// 白边修复：①去掉 1px 白色描边 ②去掉自绘圆角+clip
// （桌面容器自带圆角，自绘半径与容器不一致就会在四角露出容器底色 = 白边）
// 渐变改挂在根 Stack 上，铺满整卡，圆角交给桌面
let storage = new LocalStorage();

@Entry(storage)
@Component
struct QuickCard {
  build() {
    Stack() {
      Column() {
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
    .linearGradient({
      angle: 155,
      colors: [['#23265C', 0], ['#2E3172', 0.52], ['#1B1E47', 1]]
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