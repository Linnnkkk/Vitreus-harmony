// 成功时刻动效：圆环弹出 + 对勾弹性放大（导入完成等"大时刻"专用）
@Component
export struct SuccessCheck {
  @State private ringScale: number = 0.3;
  @State private ringAlpha: number = 0;
  @State private markScale: number = 0.2;

  aboutToAppear() {
    // 圆环先弹开
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.ringScale = 1;
      this.ringAlpha = 1;
    });
    // 对勾随后弹性就位（轻微过冲，像盖了个章）
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 450, curve: 'springMotion(0.34, 0.8)' }, () => {
        this.markScale = 1;
      });
    }, 200);
  }

  build() {
    Stack() {
      Circle({ width: 76, height: 76 })
        .fill('rgba(79,90,200,0.16)')
        .stroke('#7A88E8')
        .strokeWidth(2)
        .scale({ x: this.ringScale, y: this.ringScale })
        .opacity(this.ringAlpha)
      Path()
        .commands('M25 38 L34 47 L51 29')
        .width(76)
        .height(76)
        .stroke('#9BE8B4')
        .strokeWidth(5)
        .strokeLineCap(LineCapStyle.Round)
        .fillOpacity(0)
        .scale({ x: this.markScale, y: this.markScale })
    }
    .width(76)
    .height(76)
  }
}
