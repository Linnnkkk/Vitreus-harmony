// 网页弹窗（window.open / OAuth 登录）的底部半屏面板：
// 从下方滑入，高度小于 Obsidian 界面（露出顶部一截，Obsidian 没有被盖掉）；右上角 ✕ 关闭；
// 顶部把手/标题栏可下拉关闭；Web 内容由调用方通过尾随闭包提供（事件绑定仍在各页面里，本组件只管外框与动画）。
@Component
export struct WebPopupSheet {
  @Prop @Watch('onShowChange') show: boolean = false;
  @Prop host: string = '';
  onClose: () => void = () => {};
  @State private dragY: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder emptyContent() {}

  onShowChange(): void {
    if (this.show) {
      this.dragY = 0;
    }
  }

  // 下拉关闭：先滑出屏幕再通知调用方（调用方把 show 置 false，面板随即移除）
  private dismissByDrag(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseIn,
      onFinish: () => { this.onClose(); }
    }, () => { this.dragY = 1200; });
  }

  build() {
    if (this.show) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 遮罩：吞掉触摸，不响应点击关闭（登录进行到一半时误触遮罩会丢进度，只给 ✕ 和下拉两个明确关闭手段）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(6,8,24,0.55)')
          .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut }))

        Column() {
          Column() {
            Column()
              .width(38)
              .height(4)
              .borderRadius(2)
              .backgroundColor('rgba(232,234,244,0.32)')
              .margin({ top: 8 })
            Row({ space: 8 }) {
              Text(this.host === '' ? '网页' : this.host)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#E8EAF4')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('✕')
                .fontSize(15)
                .fontColor('#E8EAF4')
                .width(32)
                .height(32)
                .textAlign(TextAlign.Center)
                .borderRadius(16)
                .backgroundColor('rgba(255,255,255,0.12)')
                .onClick(() => { this.onClose(); })
            }
            .width('100%')
            .height(44)
            .padding({ left: 18, right: 12 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .gesture(
            PanGesture({ direction: PanDirection.Down, distance: 6 })
              .onActionUpdate((e: GestureEvent) => {
                this.dragY = Math.max(0, e.offsetY);
              })
              .onActionEnd(() => {
                if (this.dragY > 120) {
                  this.dismissByDrag();
                } else {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.dragY = 0; });
                }
              })
          )

          this.content()
        }
        .width('100%')
        .height('90%')
        .backgroundColor('#141736')
        .borderRadius({ topLeft: 22, topRight: 22 })
        .clip(true)
        .translate({ y: this.dragY })
        .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 340, curve: Curve.Friction }))
      }
      .width('100%')
      .height('100%')
      .zIndex(30)
    }
  }
}
