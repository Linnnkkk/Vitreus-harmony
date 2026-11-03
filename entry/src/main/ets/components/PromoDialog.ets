import { VipPromo } from '../common/VipPromo';

// 首页限时活动提示：仅非会员、活动期内、未点过「不再提示」时由 ModeSelect 展示一次。
@Component
export struct PromoDialog {
  onOpen: () => void = () => {};
  onDismiss: () => void = () => {};

  build() {
    Column() {
      Column({ space: 12 }) {
        Text('包月会员，首月 ' + VipPromo.PRICE_TEXT)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F3FF')
          .width('100%')
          .textAlign(TextAlign.Start)
        Text('11 月 4 日至 11 日，首次订阅包月会员，首月 ' + VipPromo.PRICE_TEXT + '。')
          .fontSize(14)
          .fontColor('#E4E8FF')
          .lineHeight(22)
          .width('100%')
          .textAlign(TextAlign.Start)
        Text('解锁 WebDAV 远程库，以及用电脑浏览器、AI 访问本设备笔记。')
          .fontSize(13)
          .fontColor('#C4C9E8')
          .lineHeight(21)
          .width('100%')
          .textAlign(TextAlign.Start)
        Text('次月起 ' + VipPromo.ORIGINAL_MONTHLY_TEXT + '/月自动续费，可随时在「设置 → 华为账号 → 付款与购买 → 订阅」中取消。')
          .fontSize(12)
          .fontColor('#9AA3CC')
          .lineHeight(19)
          .width('100%')
          .textAlign(TextAlign.Start)
        Button('查看会员')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
          .borderRadius(14)
          .margin({ top: 6 })
          .onClick(() => {
            this.onOpen();
          })
        Button('不再提示')
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor('#AEB8E8')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onDismiss();
          })
      }
      .width('82%')
      .padding({ left: 22, right: 22, top: 24, bottom: 14 })
      .backgroundColor('rgba(23,26,61,0.96)')
      .borderRadius(22)
      .border({ width: 1, color: 'rgba(190,199,255,0.28)' })
      .shadow({ radius: 36, color: 'rgba(0,0,0,0.45)', offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(5,7,24,0.48)')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .zIndex(20)
  }
}
