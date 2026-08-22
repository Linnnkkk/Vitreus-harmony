// PSP XMB 式波浪背景——移植自 PPSSPP Background.cpp 的 WaveAnimation：
// 两条多重正弦叠加的波带，从波峰到底部垂直渐隐，随时间横向流动。
// 原作公式：sin(i*0.005+t*0.8)*0.05 + sin(i*0.002+t*0.25)*0.02 + sin(i*0.001+t*0.3)*0.03 + 0.625
@Component
export struct WaveBackground {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;

  aboutToAppear() {
    this.t0 = Date.now();
    this.timer = setInterval(() => {
      this.draw();
    }, 33); // ~30fps：波浪缓慢，肉眼无差别，省电
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 单条波带：从波峰 yTop 渐隐到底部（对应原作 RectVGradient + 抗锯齿带）
  private band(x: number, sw: number, yTop: number, w: number, h: number): void {
    if (yTop >= h) {
      return;
    }
    const g = this.ctx.createLinearGradient(0, yTop, 0, h);
    g.addColorStop(0, 'rgba(170,180,235,0.11)');
    g.addColorStop(1, 'rgba(170,180,235,0)');
    this.ctx.fillStyle = g;
    this.ctx.fillRect(x, yTop, sw + 1, h - yTop);
    // 抗锯齿带：波峰上方 3px 反向渐变（对应原作的 antialiasing pass）
    const ga = this.ctx.createLinearGradient(0, yTop - 3, 0, yTop);
    ga.addColorStop(0, 'rgba(170,180,235,0)');
    ga.addColorStop(1, 'rgba(170,180,235,0.11)');
    this.ctx.fillStyle = ga;
    this.ctx.fillRect(x, yTop - 3, sw + 1, 3);
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const t = (Date.now() - this.t0) / 1000;
    this.ctx.clearRect(0, 0, w, h);
    const step = 10;
    for (let x = 0; x < w; x += step) {
      const i = x * 1280 / w;
      // 波带一（原作 wave0）
      const wave0 = Math.sin(i * 0.005 + t * 0.8) * 0.05
        + Math.sin(i * 0.002 + t * 0.25) * 0.02
        + Math.sin(i * 0.001 + t * 0.3) * 0.03 + 0.625;
      // 波带二（原作 wave1）
      const wave1 = Math.sin(i * 0.0044 + t * 0.4) * 0.07
        + Math.sin(i * 0.003 + t * 0.1) * 0.02
        + Math.sin(i * 0.001 + t * 0.3) * 0.01 + 0.625;
      this.band(x, step, wave0 * h, w, h);
      this.band(x, step, wave1 * h, w, h);
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None) // 纯背景，不挡任何触摸
  }
}
