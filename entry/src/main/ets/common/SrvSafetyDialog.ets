// 伺服器凭证保存前的网络安全提示弹窗（样式同 Splash 免责声明：遮罩+玻璃卡+主按钮）
// 触发点：LanServerPage.saveCredAndEnable + LocalWeb 面板两处凭证保存（srv-cred-form / srv-cred）
// 每次保存都提示（不设"不再提醒"——涉及用户数据安全预期）
@Component
export struct SrvSafetyDialog {
  @Prop show: boolean = false;
  onConfirm: () => void = () => {};

  build() {
    if (this.show) {
      Column() {
        Column({ space: 14 }) {
          Text('网络安全提示')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 4 })

          Column({ space: 10 }) {
            Text('1. 伺服器通过局域网传输你的笔记，这一通道没有加密。')
              .fontSize(13)
              .fontColor('#C8CEE8')
              .textAlign(TextAlign.Start)
            Text('2. 在咖啡馆、机场等公共网络下使用，同一网络中的人有可能看到你的内容。')
              .fontSize(13)
              .fontColor('#C8CEE8')
              .textAlign(TextAlign.Start)
            Text('3. 如果确需在外使用，请开启手机的个人热点，只让信任的设备连接——这是最稳妥的方式。')
              .fontSize(13)
              .fontColor('#C8CEE8')
              .textAlign(TextAlign.Start)
            Text('4. 家庭网络下，请安心使用。')
              .fontSize(13)
              .fontColor('#C8CEE8')
              .textAlign(TextAlign.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Button('我已知晓，继续保存')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#4F5AC8')
            .fontColor(Color.White)
            .borderRadius(16)
            .margin({ top: 8 })
            .onClick(() => {
              this.onConfirm();
            })
        }
        .width('86%')
        .padding({ left: 22, right: 22, top: 26, bottom: 26 })
        .backgroundEffect({ radius: 55, saturation: 1.25, brightness: 1.32, color: 'rgba(255,255,255,0.20)', adaptiveColor: AdaptiveColor.AVERAGE })
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
          .animation({ duration: 160, curve: Curve.EaseOut }))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(10,12,32,0.72)')
    }
  }
}
