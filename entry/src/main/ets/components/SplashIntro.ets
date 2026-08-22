// 开场动效：一束光从左上射入，命中中心后散射出七彩光，随后淡出、
// 显出底下的开屏 logo 图——把"棱镜"的成像过程讲一遍
// 时间线：0-0.7s 光束射入 / 0.7-1.5s 七彩散射+中心辉光 / 1.5-2.2s 整体淡出
@Component
export struct SplashIntro {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;
  private colors: string[] = ['#FF5A5A', '#FF9F43', '#FFD93D', '#6BCB77', '#4D96FF', '#7B61FF', '#B983FF'];

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
    // 整体淡出（第三幕）
    let alpha = 1;
    if (t > 1.5) {
      alpha = Math.max(0, 1 - (t - 1.5) / 0.7);
      if (alpha <= 0) {
        if (this.timer !== -1) {
          clearInterval(this.timer);
          this.timer = -1;
        }
        return;
      }
    }
    this.ctx.globalAlpha = alpha;

    const cx = w / 2;
    const cy = h / 2;
    // 光束方向：左上 → 中心
    const dirX = 0.87;
    const dirY = 0.5;

    // 第一幕：光束射入（头部 + 渐变尾迹）
    const p1 = Math.min(t / 0.7, 1);
    const ease1 = 1 - Math.pow(1 - p1, 3); // easeOutCubic
    const headX = -0.12 * w + (cx + 0.12 * w) * ease1;
    const headY = 0.1 * h + (cy - 0.1 * h) * ease1;
    const tail = 170;
    const g = this.ctx.createLinearGradient(headX, headY, headX - dirX * tail, headY - dirY * tail);
    g.addColorStop(0, 'rgba(255,255,255,0.95)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    this.ctx.strokeStyle = g;
    this.ctx.lineWidth = 2.5;
    this.ctx.beginPath();
    this.ctx.moveTo(headX, headY);
    this.ctx.lineTo(headX - dirX * tail, headY - dirY * tail);
    this.ctx.stroke();
    // 光束头部亮点
    const hg = this.ctx.createRadialGradient(headX, headY, 0, headX, headY, 14);
    hg.addColorStop(0, 'rgba(255,255,255,0.9)');
    hg.addColorStop(1, 'rgba(255,255,255,0)');
    this.ctx.fillStyle = hg;
    this.ctx.beginPath();
    this.ctx.arc(headX, headY, 14, 0, Math.PI * 2);
    this.ctx.fill();

    // 第二幕：命中中心 → 七彩扇形散射 + 中心辉光
    if (t > 0.65) {
      const p2 = Math.min((t - 0.65) / 0.85, 1);
      const ease2 = 1 - Math.pow(1 - p2, 2.4);
      // 中心辉光
      const cg = this.ctx.createRadialGradient(cx, cy, 0, cx, cy, 70 + 50 * ease2);
      cg.addColorStop(0, 'rgba(255,255,255,' + (0.55 * ease2 * (1 - p2 * 0.5)).toFixed(3) + ')');
      cg.addColorStop(1, 'rgba(255,255,255,0)');
      this.ctx.fillStyle = cg;
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, 70 + 50 * ease2, 0, Math.PI * 2);
      this.ctx.fill();
      // 七道彩光：沿光束前进方向 ±66° 扇形展开
      for (let i = 0; i < 7; i++) {
        const spread = -66 + i * 22; // 度
        const rad = (spread * Math.PI) / 180;
        const baseAng = Math.atan2(dirY, dirX);
        const ang = baseAng + rad;
        const len = ease2 * (0.30 + 0.05 * (i % 2)) * w;
        const ex = cx + Math.cos(ang) * len;
        const ey = cy + Math.sin(ang) * len;
        const rg = this.ctx.createLinearGradient(cx, cy, ex, ey);
        rg.addColorStop(0, this.colors[i]);
        rg.addColorStop(1, this.hexToRgba(this.colors[i], 0));
        this.ctx.strokeStyle = rg;
        this.ctx.lineWidth = 2.5;
        this.ctx.beginPath();
        this.ctx.moveTo(cx, cy);
        this.ctx.lineTo(ex, ey);
        this.ctx.stroke();
        // 每道光头部一个小亮点
        this.ctx.fillStyle = this.hexToRgba(this.colors[i], 0.85 * ease2 * alpha);
        this.ctx.beginPath();
        this.ctx.arc(ex, ey, 2, 0, Math.PI * 2);
        this.ctx.fill();
      }
    }
    this.ctx.globalAlpha = 1;
  }

  private hexToRgba(hex: string, a: number): string {
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    return 'rgba(' + r + ',' + g + ',' + b + ',' + a.toFixed(3) + ')';
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}
