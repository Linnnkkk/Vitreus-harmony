// 子页环境动效——同源不同款，避免与主页面波浪重复。
// 灵感均来自 PPSSPP Background.cpp 的动画家族：
//   symbols = FloatingSymbolsAnimation 移植（漂浮符号，Login 用）
//   drift   = 柔光漂移（Lissajous 轨迹，AuthPage 用）
//   dots    = 缓升粒子流（数据流质感，NodeTest 用）
@Component
export struct AmbientBackground {
  @Prop mode: string = 'symbols';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;
  // symbols 布点
  private symX: number[] = [];
  private symY: number[] = [];
  private symSize: number[] = [];
  private symGlyph: number[] = [];
  private lastW: number = 0;
  private lastH: number = 0;
  // dots 布点
  private dotX: number[] = [];
  private dotY: number[] = [];
  private dotV: number[] = [];
  private dotA: number[] = [];
  private readonly glyphs: string[] = ['#', '*', '>', '\u0060', '-', '[', ']', '|'];

  aboutToAppear() {
    this.t0 = Date.now();
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 尺寸变化时重新布点（对应 PPSSPP Regenerate 思路）
  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.symX = [];
    this.symY = [];
    this.symSize = [];
    this.symGlyph = [];
    const count = 34;
    for (let i = 0; i < count; i++) {
      this.symX.push(Math.random() * w);
      this.symY.push(Math.random() * h);
      this.symSize.push(13 + Math.random() * 20);
      this.symGlyph.push(Math.floor(Math.random() * this.glyphs.length));
    }
    this.dotX = [];
    this.dotY = [];
    this.dotV = [];
    this.dotA = [];
    const dcount = 42;
    for (let i = 0; i < dcount; i++) {
      this.dotX.push(Math.random() * w);
      this.dotY.push(Math.random() * h);
      this.dotV.push(0.25 + Math.random() * 0.55); // px/frame，缓慢上升
      this.dotA.push(0.05 + Math.random() * 0.12);
    }
  }

  private drawSymbols(w: number, h: number, t: number): void {
    this.ctx.fillStyle = 'rgba(170,180,235,0.07)';
    this.ctx.textAlign = 'center';
    this.ctx.textBaseline = 'middle';
    for (let i = 0; i < this.symX.length; i++) {
      const x = this.symX[i];
      const y = this.symY[i] + 40 * Math.cos(i * 7.2 + t * 1.3);
      const angle = Math.sin(i + t * 0.6) * 0.4;
      this.ctx.save();
      this.ctx.translate(x, y);
      this.ctx.rotate(angle);
      this.ctx.font = Math.round(this.symSize[i]) + 'px sans-serif';
      this.ctx.fillText(this.glyphs[this.symGlyph[i]], 0, 0);
      this.ctx.restore();
    }
  }

  private drawDrift(w: number, h: number, t: number): void {
    // 三个柔光球各走各的 Lissajous 轨迹，频率错开
    const orbs: number[][] = [
      [0.30, 0.42, 0.050, 0.041, 0.0, 230, 0],
      [0.72, 0.30, 0.037, 0.053, 2.1, 200, 1],
      [0.55, 0.68, 0.044, 0.031, 4.2, 260, 2]
    ];
    const colors: string[] = [
      'rgba(122,136,232,0.10)',
      'rgba(90,74,122,0.10)',
      'rgba(79,90,200,0.08)'
    ];
    for (const o of orbs) {
      const cx = w * (o[0] + 0.22 * Math.sin(t * o[2] + o[4]));
      const cy = h * (o[1] + 0.20 * Math.cos(t * o[3] + o[4] * 1.7));
      const r = o[5];
      const g = this.ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      g.addColorStop(0, colors[o[6]]);
      g.addColorStop(1, 'rgba(122,136,232,0)');
      this.ctx.fillStyle = g;
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  private drawDots(t: number): void {
    for (let i = 0; i < this.dotX.length; i++) {
      // 缓慢上升 + 水平微摆
      const x = this.dotX[i] + Math.sin(t * 0.5 + i) * 6;
      const y = this.dotY[i];
      this.ctx.fillStyle = 'rgba(154,163,216,' + this.dotA[i].toFixed(3) + ')';
      this.ctx.beginPath();
      this.ctx.arc(x, y, 1.4, 0, Math.PI * 2);
      this.ctx.fill();
      // 推进（画布坐标向上 = 减）
      this.dotY[i] -= this.dotV[i];
      if (this.dotY[i] < -4) {
        this.dotY[i] = this.lastH + 4;
        this.dotX[i] = Math.random() * this.lastW;
      }
    }
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    if (w !== this.lastW || h !== this.lastH) {
      this.regen(w, h);
    }
    const t = (Date.now() - this.t0) / 1000;
    this.ctx.clearRect(0, 0, w, h);
    if (this.mode === 'symbols') {
      this.drawSymbols(w, h, t);
    } else if (this.mode === 'drift') {
      this.drawDrift(w, h, t);
    } else {
      this.drawDots(t);
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None) // 纯背景，不挡任何触摸
  }
}
