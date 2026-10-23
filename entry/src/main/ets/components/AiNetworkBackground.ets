// AI 专属轨道 / 节点信号场。仅 Canvas 定时绘制，不使用不可取消的属性动画。
@Component
export struct AiNetworkBackground {
  @Prop @Watch('onVisibilityChanged') visible: boolean = true;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private alive: boolean = false;
  private ready: boolean = false;
  private phase: number = 0;

  aboutToAppear(): void {
    this.alive = true;
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.ready = false;
    this.stop();
  }

  private onVisibilityChanged(): void {
    if (this.visible) {
      this.start();
    } else {
      this.stop();
    }
  }

  private start(): void {
    if (!this.visible || !this.alive || !this.ready || this.timer !== -1) { return; }
    this.draw();
    this.timer = setInterval(() => {
      if (!this.visible || !this.alive) {
        this.stop();
        return;
      }
      this.phase += 0.006;
      this.draw();
    }, 50);
  }

  private stop(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private draw(): void {
    if (!this.visible || !this.alive || !this.ready) { return; }
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) { return; }
    this.ctx.clearRect(0, 0, w, h);
    const cx = w * 0.5;
    const cy = Math.min(h * 0.32, 245);
    const radius = Math.min(w * 0.42, 200);
    // 稀疏同心轨道，刻意留白，不做满屏粒子噪点。
    for (let ring = 0; ring < 3; ring++) {
      const r = radius + ring * 48;
      this.ctx.strokeStyle = ring === 0 ? 'rgba(91,212,221,0.11)' : 'rgba(153,135,229,0.07)';
      this.ctx.lineWidth = 1;
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
      this.ctx.stroke();
      for (let node = 0; node < 5; node++) {
        const a = node * Math.PI * 2 / 5 + ring * 0.7 + this.phase * (ring % 2 === 0 ? 1 : -1);
        const x = cx + Math.cos(a) * r;
        const y = cy + Math.sin(a) * r;
        const nextA = a + Math.PI * 2 / 5;
        this.ctx.strokeStyle = 'rgba(123,172,216,0.06)';
        this.ctx.beginPath();
        this.ctx.moveTo(x, y);
        this.ctx.lineTo(cx + Math.cos(nextA) * r, cy + Math.sin(nextA) * r);
        this.ctx.stroke();
        this.ctx.fillStyle = node % 2 === 0 ? 'rgba(121,223,228,0.42)' : 'rgba(173,153,241,0.36)';
        this.ctx.beginPath();
        this.ctx.arc(x, y, node === 0 ? 3 : 1.8, 0, Math.PI * 2);
        this.ctx.fill();
        // 每条轨道一个短信号尾迹。
        if (node === 0) {
          this.ctx.strokeStyle = 'rgba(121,223,228,0.25)';
          this.ctx.lineWidth = 2;
          this.ctx.beginPath();
          this.ctx.arc(cx, cy, r, a - 0.15, a);
          this.ctx.stroke();
          this.ctx.lineWidth = 1;
        }
      }
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.ready = true;
        this.start();
      })
  }
}
