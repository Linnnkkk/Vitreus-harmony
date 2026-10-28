// 受控开关：只发送切换意图，由调用方确认状态后回填 isOn。
@Component
export struct ServiceSwitch {
  @Prop isOn: boolean = false;
  @Prop interactive: boolean = true;
  @Prop label: string = '';
  onChange: (value: boolean) => void = (value: boolean): void => {};

  build() {
    Button({ stateEffect: false }) {
      Row() {
        Circle({ width: 22, height: 22 })
          .fill('#FFFFFF')
          .margin({ left: this.isOn ? 25 : 3 })
          .shadow({ radius: 4, color: '#00000055', offsetY: 1 })
          .animation({ duration: 180, curve: Curve.EaseOut })
      }
      .width(50)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.isOn ? '#5F6BD8' : '#3A4078')
    }
    .width(50)
    .height(28)
    .padding(0)
    .borderRadius(14)
    .backgroundColor(Color.Transparent)
    .enabled(this.interactive)
    .opacity(this.interactive ? 1 : 0.5)
    .accessibilityText(this.label + (this.isOn ? '，已开启' : '，已关闭'))
    .onClick(() => {
      if (this.interactive) {
        this.onChange(!this.isOn);
      }
    })
  }
}
