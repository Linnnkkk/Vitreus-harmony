// 成功时刻动效 v2：Canvas 逐帧绘制（像素级可控，不再依赖 Path 组件的坐标空间）
// 96x96：圆环弹出 → 对勾真实"描边式"生长（先短边后长边）→ 柔光收尾
@Component
export struct SuccessCheck {
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
    if (t > 1.6) {
      if (this.timer !== -1) {
        clearInterval(this.timer);
        this.timer = -1;
      }
      return; // 保留最终帧（圆环+完整对勾）
    }
    this.ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2;

    // ① 圆环：0-0.3s 弹出（带一点过冲）
    const p1 = Math.min(t / 0.3, 1);
    const over = 1 + 0.12 * Math.sin(Math.PI * p1); // 轻微呼吸过冲
    const r = 36 * (0.45 + 0.55 * (1 - Math.pow(1 - p1, 3))) * over;
    this.ctx.strokeStyle = 'rgba(122,136,232,' + (0.9 * p1).toFixed(3) + ')';
    this.ctx.lineWidth = 2.5;
    this.ctx.beginPath();
    this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
    this.ctx.stroke();
    // 圆环底填充
    this.ctx.fillStyle = 'rgba(79,90,200,' + (0.16 * p1).toFixed(3) + ')';
    this.ctx.beginPath();
    this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
    this.ctx.fill();

    // ② 对勾：0.28-0.78s 两段依次生长（真实描边感）
    const cp = Math.max(0, Math.min((t - 0.28) / 0.5, 1));
    const s1 = Math.min(cp / 0.4, 1);        // 短边 (31,50)→(42,60)
    const s2 = Math.max(0, Math.min((cp - 0.4) / 0.6, 1)); // 长边 (42,60)→(65,38)
    this.ctx.strokeStyle = '#9BE8B4';
    this.ctx.lineWidth = 6.5;
    this.ctx.lineCap = 'round';
    this.ctx.lineJoin = 'round';
    this.ctx.beginPath();
    this.ctx.moveTo(31, 50);
    this.ctx.lineTo(31 + (42 - 31) * s1, 50 + (60 - 50) * s1);
    if (s2 > 0) {
      this.ctx.lineTo(42 + (65 - 42) * s2, 60 + (38 - 60) * s2);
    }
    this.ctx.stroke();

    // ③ 对勾根部柔光
    if (cp > 0) {
      const gl = this.ctx.createRadialGradient(48, 49, 0, 48, 49, 40);
      gl.addColorStop(0, 'rgba(155,232,180,' + (0.16 * cp).toFixed(3) + ')');
      gl.addColorStop(1, 'rgba(155,232,180,0)');
      this.ctx.fillStyle = gl;
      this.ctx.beginPath();
      this.ctx.arc(48, 49, 40, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  build() {
    Canvas(this.ctx)
      .width(96)
      .height(96)
      .hitTestBehavior(HitTestMode.None)
  }
}
