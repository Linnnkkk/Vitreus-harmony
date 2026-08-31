// 子页环境动效 2.0——三个经典款，各配各的主题（参考业界成熟范式）：
//   NetworkBackground  = plexus 粒子网络（particles.js 经典），Login"连接"主题
//   StarfieldBackground = 星野闪烁 + 周期流星，AuthPage 夜空验证仪式感
//   MatrixRainBackground = Markdown 符号雨（低调版 matrix），NodeTest 终端主题
// 全部 Canvas 30fps，离页自停，hitTestBehavior(None) 不挡触摸

@Component
export struct NetworkBackground {
  // 页面隐藏时停表省电（pushUrl 后父页不销毁，aboutToDisappear 不再触发）
  @Prop @Watch('onVis') visible: boolean = true;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private delayT: number = -1; // 延迟启动句柄（转场结束后才开跑）
  private xs: number[] = [];
  private ys: number[] = [];
  private vxs: number[] = [];
  private vys: number[] = [];
  private lastW: number = 0;
  private lastH: number = 0;

  aboutToAppear() {
    // 转场期(约200ms)不跑动画循环：新页首帧构建/转场动画不与30fps Canvas争主线程——延迟启动
    this.delayT = setTimeout(() => { this.startT(); }, 280);
  }

  aboutToDisappear() {
    if (this.delayT !== -1) {
      clearTimeout(this.delayT);
      this.delayT = -1;
    }
    this.stopT();
  }

  onVis() {
    if (this.visible) { this.startT(); } else { this.stopT(); }
  }

  private startT(): void {
    if (this.timer !== -1) { return; }
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  private stopT(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.xs = [];
    this.ys = [];
    this.vxs = [];
    this.vys = [];
    for (let i = 0; i < 34; i++) {
      this.xs.push(Math.random() * w);
      this.ys.push(Math.random() * h);
      const ang = Math.random() * Math.PI * 2;
      const sp = 0.1 + Math.random() * 0.22;
      this.vxs.push(Math.cos(ang) * sp);
      this.vys.push(Math.sin(ang) * sp);
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
    this.ctx.clearRect(0, 0, w, h);
    // 连线：邻近点之间，距离越近越亮
    const maxD = 110;
    for (let i = 0; i < this.xs.length; i++) {
      for (let j = i + 1; j < this.xs.length; j++) {
        const dx = this.xs[i] - this.xs[j];
        const dy = this.ys[i] - this.ys[j];
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < maxD) {
          const a = (1 - d / maxD) * 0.20;
          this.ctx.strokeStyle = 'rgba(154,163,216,' + a.toFixed(3) + ')';
          this.ctx.lineWidth = 1;
          this.ctx.beginPath();
          this.ctx.moveTo(this.xs[i], this.ys[i]);
          this.ctx.lineTo(this.xs[j], this.ys[j]);
          this.ctx.stroke();
        }
      }
    }
    // 点
    this.ctx.fillStyle = 'rgba(154,163,216,0.55)';
    for (let i = 0; i < this.xs.length; i++) {
      this.ctx.beginPath();
      this.ctx.arc(this.xs[i], this.ys[i], 1.7, 0, Math.PI * 2);
      this.ctx.fill();
      this.xs[i] += this.vxs[i];
      this.ys[i] += this.vys[i];
      if (this.xs[i] < 0) { this.xs[i] = w; }
      if (this.xs[i] > w) { this.xs[i] = 0; }
      if (this.ys[i] < 0) { this.ys[i] = h; }
      if (this.ys[i] > h) { this.ys[i] = 0; }
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
export struct StarfieldBackground {
  // 页面隐藏时停表省电（pushUrl 后父页不销毁，aboutToDisappear 不再触发）
  @Prop @Watch('onVis') visible: boolean = true;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private delayT: number = -1; // 延迟启动句柄（转场结束后才开跑）
  private t0: number = 0;
  private xs: number[] = [];
  private ys: number[] = [];
  private phases: number[] = [];
  private sizes: number[] = [];
  private lastW: number = 0;
  private lastH: number = 0;
  private nextMeteor: number = 3000; // 距开场 ms
  private meteorT0: number = -1;
  private meteorX: number = 0;
  private meteorY: number = 0;

  aboutToAppear() {
    this.t0 = Date.now();
    // 转场期(约200ms)不跑动画循环：新页首帧构建/转场动画不与30fps Canvas争主线程——延迟启动
    this.delayT = setTimeout(() => { this.startT(); }, 280);
  }

  aboutToDisappear() {
    if (this.delayT !== -1) {
      clearTimeout(this.delayT);
      this.delayT = -1;
    }
    this.stopT();
  }

  onVis() {
    if (this.visible) { this.startT(); } else { this.stopT(); }
  }

  private startT(): void {
    if (this.timer !== -1) { return; }
    this.timer = setInterval(() => {
      this.draw();
    }, 33);
  }

  private stopT(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.xs = [];
    this.ys = [];
    this.phases = [];
    this.sizes = [];
    for (let i = 0; i < 60; i++) {
      this.xs.push(Math.random() * w);
      this.ys.push(Math.random() * h);
      this.phases.push(Math.random() * Math.PI * 2);
      this.sizes.push(0.7 + Math.random() * 1.2);
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
    const now = Date.now();
    const t = (now - this.t0) / 1000;
    this.ctx.clearRect(0, 0, w, h);
    // 星野：每颗按自己的相位呼吸
    for (let i = 0; i < this.xs.length; i++) {
      const a = 0.18 + 0.30 * (0.5 + 0.5 * Math.sin(t * 1.4 + this.phases[i]));
      this.ctx.fillStyle = 'rgba(200,208,240,' + a.toFixed(3) + ')';
      this.ctx.beginPath();
      this.ctx.arc(this.xs[i], this.ys[i], this.sizes[i], 0, Math.PI * 2);
      this.ctx.fill();
    }
    // 流星：每 6~10s 一颗，从上部随机点向左下划过 0.9s
    if (this.meteorT0 < 0 && now - this.t0 > this.nextMeteor) {
      this.meteorT0 = now;
      this.meteorX = w * (0.3 + Math.random() * 0.6);
      this.meteorY = h * Math.random() * 0.3;
    }
    if (this.meteorT0 >= 0) {
      const p = (now - this.meteorT0) / 900; // 0..1
      if (p > 1) {
        this.meteorT0 = -1;
        this.nextMeteor = 6000 + Math.random() * 4000;
      } else {
        const len = 90;
        const dx = -0.85;
        const dy = 0.5;
        const hx = this.meteorX + p * 300;
        const hy = this.meteorY + p * 177;
        const fade = Math.sin(Math.PI * p); // 入场淡、出场淡
        const g = this.ctx.createLinearGradient(hx, hy, hx - dx * len, hy - dy * len);
        g.addColorStop(0, 'rgba(230,235,255,' + (0.55 * fade).toFixed(3) + ')');
        g.addColorStop(1, 'rgba(230,235,255,0)');
        this.ctx.strokeStyle = g;
        this.ctx.lineWidth = 1.5;
        this.ctx.beginPath();
        this.ctx.moveTo(hx, hy);
        this.ctx.lineTo(hx - dx * len, hy - dy * len);
        this.ctx.stroke();
        // 头部亮点
        this.ctx.fillStyle = 'rgba(255,255,255,' + (0.7 * fade).toFixed(3) + ')';
        this.ctx.beginPath();
        this.ctx.arc(hx, hy, 1.6, 0, Math.PI * 2);
        this.ctx.fill();
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

@Component
export struct MatrixRainBackground {
  // 页面隐藏时停表省电（pushUrl 后父页不销毁，aboutToDisappear 不再触发）
  @Prop @Watch('onVis') visible: boolean = true;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private delayT: number = -1; // 延迟启动句柄（转场结束后才开跑）
  private cols: number = 0;
  private colY: number[] = [];
  private colV: number[] = [];
  private lastW: number = 0;
  private lastH: number = 0;
  private glyphs: string[] = ['#', '*', '>', '\u0060', '-', '[', ']', '|', '=', '~'];

  aboutToAppear() {
    // 转场期(约200ms)不跑动画循环：新页首帧构建/转场动画不与30fps Canvas争主线程——延迟启动
    this.delayT = setTimeout(() => { this.startT(); }, 280);
  }

  aboutToDisappear() {
    if (this.delayT !== -1) {
      clearTimeout(this.delayT);
      this.delayT = -1;
    }
    this.stopT();
  }

  onVis() {
    if (this.visible) { this.startT(); } else { this.stopT(); }
  }

  private startT(): void {
    if (this.timer !== -1) { return; }
    this.timer = setInterval(() => {
      this.draw();
    }, 66); // 字符雨 15fps 跳格感
  }

  private stopT(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private regen(w: number, h: number): void {
    this.lastW = w;
    this.lastH = h;
    this.cols = Math.floor(w / 19);
    this.colY = [];
    this.colV = [];
    for (let i = 0; i < this.cols; i++) {
      this.colY.push(Math.random() * -h);
      this.colV.push(0.6 + Math.random() * 1.1); // 格/帧
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
    // 半透明覆盖代替 clearRect：新帧叠旧帧，形成自然拖尾
    // 渐变三停与页面根渐变(#1E2150/#2A2D6E/#23265C)同款: 稳定态视觉与全App页面背景一致
    const trail = this.ctx.createLinearGradient(0, 0, 0, h);
    trail.addColorStop(0, 'rgba(30,33,80,0.34)');
    trail.addColorStop(0.55, 'rgba(42,45,110,0.34)');
    trail.addColorStop(1, 'rgba(35,38,92,0.34)');
    this.ctx.fillStyle = trail;
    this.ctx.fillRect(0, 0, w, h);
    this.ctx.font = '13px monospace';
    for (let i = 0; i < this.cols; i++) {
      const x = i * 22 + 6;
      const y = this.colY[i];
      // 头字符亮，往下 8 格渐隐
      for (let k = 0; k < 12; k++) {
        const gy = y - k * 16;
        if (gy < -16 || gy > h + 16) {
          continue;
        }
        const a = 0.55 * (1 - k / 12);
        this.ctx.fillStyle = 'rgba(195,205,239,' + a.toFixed(3) + ')';
        this.ctx.fillText(this.glyphs[Math.floor(Math.random() * this.glyphs.length)], x, gy);
      }
      this.colY[i] += this.colV[i] * 16;
      if (this.colY[i] - 12 * 16 > h) {
        this.colY[i] = Math.random() * -200;
        this.colV[i] = 0.5 + Math.random();
      }
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        // 首帧立即铺不透明底色：拖尾叠加的沉淀一步到位，消除延迟启动后的~1s渐深
        const base = this.ctx.createLinearGradient(0, 0, 0, this.ctx.height);
        base.addColorStop(0, '#1E2150');
        base.addColorStop(0.55, '#2A2D6E');
        base.addColorStop(1, '#23265C');
        this.ctx.fillStyle = base;
        this.ctx.fillRect(0, 0, this.ctx.width, this.ctx.height);
      })
  }
}

// ── 信号波纹（伺服器页专属）：同心圆从底部中心缓慢扩散淡出 ──
// 语义呼应"伺服器对外广播"；绿青低饱和呼应在线色。Canvas 30fps，离页自停。
@Component
export struct SignalRippleBackground {
  @Prop @Watch('onVis') visible: boolean = true;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private delayT: number = -1; // 延迟启动句柄（转场结束后才开跑）
  private t: number = 0;

  aboutToAppear() {
    // 转场期(约200ms)不跑动画循环：新页首帧构建/转场动画不与30fps Canvas争主线程——延迟启动
    this.delayT = setTimeout(() => { this.startT(); }, 280);
  }

  aboutToDisappear() {
    if (this.delayT !== -1) {
      clearTimeout(this.delayT);
      this.delayT = -1;
    }
    this.stopT();
  }

  onVis() {
    if (this.visible) { this.startT(); } else { this.stopT(); }
  }

  startT() {
    if (this.timer !== -1) { return; }
    this.timer = setInterval(() => {
      this.t += 1;
      this.draw();
    }, 33);
  }

  stopT() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  draw() {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) { return; }
    this.ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h * 0.72;
    const maxR = Math.max(w, h) * 0.75;
    // 4 道波纹，相位错开，周期 480 帧（~16s）缓慢扩散
    for (let i = 0; i < 4; i++) {
      let p = ((this.t + i * 120) % 480) / 480;
      const r = 30 + p * maxR;
      const alpha = 0.16 * (1 - p) * (1 - p);
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
      this.ctx.strokeStyle = 'rgba(155, 232, 180, ' + alpha.toFixed(3) + ')';
      this.ctx.lineWidth = 1.2;
      this.ctx.stroke();
    }
    // 中心微光
    const g = this.ctx.createRadialGradient(cx, cy, 0, cx, cy, 90);
    g.addColorStop(0, 'rgba(155, 232, 180, 0.10)');
    g.addColorStop(1, 'rgba(155, 232, 180, 0)');
    this.ctx.fillStyle = g;
    this.ctx.fillRect(cx - 90, cy - 90, 180, 180);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}
