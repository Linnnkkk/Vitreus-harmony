// 液态玻璃动感层（纯 ArkTS，零 NDK）
// 周期扫光（液面反光）+ 边缘厚度光（顶亮底暗厚边）
// 性能设计：间歇式动画——扫 1.4s + 静 3.6s（静止期零重绘；永动动画会吃满帧并吞掉路由转场）
// 用法：.background(this.xxx()) 作为卡片背景层（不参与命中测试，触摸穿透）
@Component
export struct LiquidSheen {
  @Prop cornerRadius: number = 18;
  @State private sweepX: number = 0;   // 0→1 扫光位置
  private areaW: number = 1;
  private phase: number = -1;          // 动画阶段句柄（-1 未启动）

  private sweepOnce(): void {
    // 一次扫光：0 → 1（1.4s），完成后静止 3.6s 再来一轮
    this.getUIContext().animateTo(
      { duration: 1400, curve: Curve.Smooth, onFinish: () => {
        this.sweepX = 0; // 无动画复位（扫光两端在卡外，跳变不可见）
        this.phase = setTimeout(() => { this.sweepOnce(); }, 3600);
      }},
      () => { this.sweepX = 1; }
    );
  }

  private startSweep(): void {
    if (this.phase !== -1) {
      return;
    }
    this.phase = 0;
    // 延迟 700ms 启动：避开路由转场窗口（转场期被满帧动画吃掉=进页无动画的根因）
    this.phase = setTimeout(() => { this.sweepOnce(); }, 700);
  }

  aboutToDisappear() {
    if (this.phase !== -1 && this.phase !== 0) {
      clearTimeout(this.phase);
    }
    this.phase = -1;
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

      // ── 扫光带：斜向亮带从左扫到右（液面反光流动，间歇驱动）──
      Column()
        .width('30%')
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
