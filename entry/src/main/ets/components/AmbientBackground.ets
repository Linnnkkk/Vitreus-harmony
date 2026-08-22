// 子页环境动效——三个独立组件，与主页面波浪不同款。
// 灵感来自 PPSSPP Background.cpp 动画家族：
//   SymbolsBackground = FloatingSymbolsAnimation 移植（漂浮 Markdown 符号，Login）
//   DriftBackground   = 柔光球 Lissajous 轨迹漂移（AuthPage）
//   DotsBackground    = 缓升粒子流（NodeTest）
// 注：不共用带参父组件——@Prop 在部分设备上初始化时序不稳，独立 struct 零悬念

@Component
export struct SymbolsBackground {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;
  private xs: number[] = [];
  private ys: number[] = [];
  private sizes: number[] = [];
  private glyphs: string[] = [];
  private lastW: number = 0;
  private lastH: number = 0;
  private readonly chars: string[] = ['#', '*', '>', '\u0060', '-', '[', ']', '|'];

  aboutToAppear() {
    this.t0 = Date.now();
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }

  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.xs = [];
    this.ys = [];
    this.sizes = [];
    this.glyphs = [];
    for (let i = 0; i < 30; i++) {
      this.xs.push(Math.random() * w);
      this.ys.push(Math.random() * h);
      this.sizes.push(16 + Math.random() * 20);
      this.glyphs.push(this.chars[Math.floor(Math.random() * this.chars.length)]);
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
    this.ctx.fillStyle = 'rgba(170,180,235,0.16)';
    this.ctx.textAlign = 'center';
    this.ctx.textBaseline = 'middle';
    for (let i = 0; i < this.xs.length; i++) {
      const y = this.ys[i] + 44 * Math.cos(i * 7.2 + t * 1.3);
      const angle = Math.sin(i + t * 0.6) * 0.4;
      this.ctx.save();
      this.ctx.translate(this.xs[i], y);
      this.ctx.rotate(angle);
      this.ctx.font = Math.round(this.sizes[i]) + 'px sans-serif';
      this.ctx.fillText(this.glyphs[i], 0, 0);
      this.ctx.restore();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct DriftBackground {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;

  aboutToAppear() {
    this.t0 = Date.now();
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const t = (Date.now() - this.t0) / 1000;
    this.ctx.clearRect(0, 0, w, h);
    // 三颗柔光球，Lissajous 轨迹频率错开
    const centers: number[][] = [[0.30, 0.42, 0.050, 0.041, 0.0], [0.72, 0.30, 0.037, 0.053, 2.1], [0.55, 0.68, 0.044, 0.031, 4.2]];
    const radii: number[] = [230, 200, 260];
    const colors: string[] = ['rgba(122,136,232,0.18)', 'rgba(140,110,190,0.16)', 'rgba(79,90,200,0.15)'];
    for (let k = 0; k < centers.length; k++) {
      const o = centers[k];
      const cx = w * (o[0] + 0.22 * Math.sin(t * o[2] + o[4]));
      const cy = h * (o[1] + 0.20 * Math.cos(t * o[3] + o[4] * 1.7));
      const r = radii[k];
      const g = this.ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      g.addColorStop(0, colors[k]);
      g.addColorStop(1, 'rgba(122,136,232,0)');
      this.ctx.fillStyle = g;
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct DotsBackground {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private xs: number[] = [];
  private ys: number[] = [];
  private vs: number[] = [];
  private als: number[] = [];
  private rs: number[] = [];
  private lastW: number = 0;
  private lastH: number = 0;

  aboutToAppear() {
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }

  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.xs = [];
    this.ys = [];
    this.vs = [];
    this.als = [];
    this.rs = [];
    for (let i = 0; i < 46; i++) {
      this.xs.push(Math.random() * w);
      this.ys.push(Math.random() * h);
      this.vs.push(0.3 + Math.random() * 0.6);
      this.als.push(0.10 + Math.random() * 0.16);
      this.rs.push(1.6 + Math.random() * 1.2);
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
    const t = performance.now() / 1000;
    this.ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < this.xs.length; i++) {
      const x = this.xs[i] + Math.sin(t * 0.5 + i) * 6;
      this.ctx.fillStyle = 'rgba(154,163,216,' + this.als[i].toFixed(3) + ')';
      this.ctx.beginPath();
      this.ctx.arc(x, this.ys[i], this.rs[i], 0, Math.PI * 2);
      this.ctx.fill();
      this.ys[i] -= this.vs[i];
      if (this.ys[i] < -4) {
        this.ys[i] = this.lastH + 4;
        this.xs[i] = Math.random() * this.lastW;
      }
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}
