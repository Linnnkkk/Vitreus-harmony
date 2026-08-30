// 液态玻璃动感层（纯 ArkTS，零 NDK）
// 三要素：周期扫光（液面反光）+ 边缘厚度光（顶亮底暗厚边）+ 高光呼吸
// 用法：Stack 叠在卡片内容之上，hitTestBehavior 透传触摸
@Component
export struct LiquidSheen {
  @Prop cornerRadius: number = 18;
  @Prop cycleMs: number = 3600;       // 扫光周期
  @State private sweepX: number = 0;   // 0→1 扫光位置
  @State private breathe: number = 0;  // 呼吸光强 0→1
  private areaW: number = 1;
  private started: boolean = false;

  private startSweep() {
    if (this.started) {
      return;
    }
    this.started = true;
    // 无限循环动画驱动扫光位置（Normal 播完从头，扫光两端在卡外，跳变不可见）
    this.getUIContext().animateTo(
      { duration: this.cycleMs, curve: Curve.Smooth, iterations: -1, playMode: PlayMode.Normal },
      () => { this.sweepX = 1; }
    );
  }

  build() {
    Stack() {
      // ── 边缘厚度光：顶部亮线（玻璃厚边）──
      Column()
        .width('100%')
        .height(1.5)
        .linearGradient({ angle: 90, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.55)', 0.5], ['rgba(255,255,255,0)', 1]] })
        .position({ x: 0, y: 0 })

      // ── 底部反光沿（玻璃底边微亮，液体表面张力感）──
      Column()
        .width('88%')
        .height(1)
        .linearGradient({ angle: 90, colors: [['rgba(160,180,255,0)', 0], ['rgba(160,180,255,0.30)', 0.5], ['rgba(160,180,255,0)', 1]] })
        .position({ x: '6%', y: '100%' })
        .translate({ y: -1 })

      // ── 扫光带：斜向亮带从左扫到右（液面反光流动）──
      Column()
        .width('34%')
        .height('130%')
        .linearGradient({
          angle: 100,
          colors: [
            ['rgba(255,255,255,0)', 0],
            ['rgba(220,235,255,0.16)', 0.45],
            ['rgba(255,255,255,0.26)', 0.6],
            ['rgba(220,235,255,0.12)', 0.75],
            ['rgba(255,255,255,0)', 1]
          ]
        })
        .rotate({ angle: 16 })
        .translate({ x: -this.areaW * 0.4 + this.sweepX * this.areaW * 1.4 })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(this.cornerRadius)
    .hitTestBehavior(HitTestMode.None)
    .onAppear(() => { this.startSweep(); })
    .onAreaChange((_o: Area, n: Area) => {
      this.areaW = Number(n.width) || 1;
    })
  }
}
