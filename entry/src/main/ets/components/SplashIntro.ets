// 开场动效 v3：完全基于 gen_splash_v9.py 的 logo 光路几何复现——
// 同一入射点/出射点/棱镜顶点/色散扇形，光效骑在 logo 自己的光路上：
//   0-0.34s  入射光束沿 logo 光轴从左缘射到棱镜入射点
//   0.32-0.9s 入射点白斑 + 棱镜内折射亮线生长 + 棱镜边线闪亮
//   0.5-0.95s 从出射点展开色散扇（六段高饱和光谱，戏剧性主秀）
//   0.95-1.4s 色散颜色向静态 logo 同款青蓝色板收敛（消除归位色彩跳水）
//   1.32-1.66s 整体渐隐归位——此时色彩已与底下 logo 本体一致，真正无缝
@Component
export struct SplashIntro {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private t0: number = 0;
  // gen_splash_v9.py 的光谱色标（t 0→1：紫→红）
  private stopT: number[] = [0, 0.2, 0.4, 0.6, 0.8, 1];
  private stopC: number[][] = [[190, 148, 255], [128, 182, 255], [108, 228, 232], [148, 246, 180], [255, 228, 122], [255, 156, 108]];
  // 归位色板：splash.png 色散扇实测采样（出射点近白→青→蓝→深蓝融底），
  // 动画后期向它收敛，保证光效消失时与底下静态图零落差
  private homeT: number[] = [0, 0.35, 0.7, 1];
  private homeC: number[][] = [[214, 216, 224], [150, 200, 204], [96, 152, 198], [70, 92, 140]];

  // 光路几何（按 logo 生成参数推导）
  private cx: number = 0;
  private cy: number = 0;
  private apexX: number = 0; private apexY: number = 0;
  private prX: number = 0; private prY: number = 0;
  private plX: number = 0; private plY: number = 0;
  private inX: number = 0; private inY: number = 0;   // 入射点 left_mid
  private exX: number = 0; private exY: number = 0;   // 出射点 exit_pt
  private specBase: number = 0; // 色散中心角（弧度）
  private specLen: number = 0;
  private geoReady: boolean = false;

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

  private buildGeo(w: number, h: number): void {
    // 关键：logo 图是 objectFit(Cover) 铺满屏幕——宽屏时方图按宽放大、垂直裁切居中，
    // 图片实际显示区 ≠ 画布。动画几何必须先换算出显示区，在显示区坐标系里套
    // logo 生成参数，否则 PC/平板上光效和棱镜错位（手机恰好比例接近所以看不出来）。
    // 选图规则与 Splash.ets 一致：h/w>1.6 用竖版图(1080x2280)，否则方图(1200x1200)
    const tall = h / w > 1.6;
    const iw = tall ? 1080 : 1200;
    const ih = tall ? 2280 : 1200;
    const scale = Math.max(w / iw, h / ih); // Cover：放大到两边都盖住
    const dispW = iw * scale;
    const dispH = ih * scale;
    const offX = (w - dispW) / 2;
    const offY = (h - dispH) / 2;
    // 竖版图：R=0.20w, cy=0.535h；方图：R=0.125w, cy=0.53h（gen_splash_v9.py）
    const R = tall ? 0.20 * dispW : 0.125 * dispW;
    this.cx = offX + 0.5 * dispW;
    this.cy = offY + (tall ? 0.535 * dispH : 0.53 * dispH);
    const tilt = 4 * Math.PI / 180;
    const a1 = -90 * Math.PI / 180 + tilt;
    const a2 = 30 * Math.PI / 180 + tilt;
    const a3 = 150 * Math.PI / 180 + tilt;
    this.apexX = this.cx + R * Math.cos(a1); this.apexY = this.cy + R * Math.sin(a1);
    this.prX = this.cx + R * Math.cos(a2); this.prY = this.cy + R * Math.sin(a2);
    this.plX = this.cx + R * Math.cos(a3); this.plY = this.cy + R * Math.sin(a3);
    // 入射点 = 左边中点；出射点 = 0.55*pr + 0.45*apex
    this.inX = (this.plX + this.apexX) / 2;
    this.inY = (this.plY + this.apexY) / 2;
    this.exX = this.prX * 0.55 + this.apexX * 0.45;
    this.exY = this.prY * 0.55 + this.apexY * 0.45;
    const refr = Math.atan2(this.exY - this.inY, this.exX - this.inX);
    this.specBase = refr + 5 * Math.PI / 180;
    this.specLen = 0.5 * dispW;
    this.geoReady = true;
  }

  private specColor(t: number): number[] {
    const tt = Math.max(0, Math.min(1, t));
    for (let i = 0; i < this.stopT.length - 1; i++) {
      if (tt <= this.stopT[i + 1]) {
        const f = (tt - this.stopT[i]) / (this.stopT[i + 1] - this.stopT[i]);
        const a = this.stopC[i];
        const b = this.stopC[i + 1];
        return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
      }
    }
    return this.stopC[this.stopC.length - 1];
  }

  // 归位色板采样（与 specColor 同构）
  private homeSpecColor(t: number): number[] {
    const tt = Math.max(0, Math.min(1, t));
    for (let i = 0; i < this.homeT.length - 1; i++) {
      if (tt <= this.homeT[i + 1]) {
        const f = (tt - this.homeT[i]) / (this.homeT[i + 1] - this.homeT[i]);
        const a = this.homeC[i];
        const b = this.homeC[i + 1];
        return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
      }
    }
    return this.homeC[this.homeC.length - 1];
  }

  // 光谱→归位 混合比例：0.95s 色散扇长完后开始收敛，1.4s 完全变成静态同款
  private homeMix(t: number): number {
    if (t <= 0.95) return 0;
    if (t >= 1.4) return 1;
    const p = (t - 0.95) / 0.45;
    return 1 - Math.pow(1 - p, 2); // ease-out
  }

  private rgba(c: number[], a: number): string {
    return 'rgba(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ',' + a.toFixed(3) + ')';
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    if (!this.geoReady) {
      this.buildGeo(w, h);
    }
    const t = (Date.now() - this.t0) / 1000;
    // 整体收尾淡出：1.32s 起 0.34s 真渐隐（原公式锚点错位导致 1.5s 处硬切，已修）
    let fade = 1;
    if (t > 1.32) {
      fade = Math.max(0, 1 - (t - 1.32) / 0.34);
      if (fade <= 0) {
        // 关键：停表前清屏，否则最后一帧光效永久冻结、盖住底下的静态 logo
        this.ctx.clearRect(0, 0, w, h);
        if (this.timer !== -1) {
          clearInterval(this.timer);
          this.timer = -1;
        }
        return;
      }
    }
    this.ctx.clearRect(0, 0, w, h);
    this.ctx.globalAlpha = fade;

    // ① 入射光束：头部从左缘沿光轴推进到入射点
    const p1 = Math.min(t / 0.34, 1);
    const e1 = 1 - Math.pow(1 - p1, 3);
    if (p1 < 1) {
      const headX = this.inX * e1;
      const tailX = Math.max(-10, headX - 150);
      const y = this.inY;
      const g = this.ctx.createLinearGradient(tailX, y, headX, y);
      g.addColorStop(0, 'rgba(238,244,255,0)');
      g.addColorStop(1, 'rgba(255,255,255,0.95)');
      this.ctx.strokeStyle = g;
      this.ctx.lineWidth = 2.6;
      this.ctx.beginPath();
      this.ctx.moveTo(tailX, y);
      this.ctx.lineTo(headX, y);
      this.ctx.stroke();
      // 头部辉点
      const hg = this.ctx.createRadialGradient(headX, y, 0, headX, y, 16);
      hg.addColorStop(0, 'rgba(255,255,255,0.9)');
      hg.addColorStop(1, 'rgba(255,255,255,0)');
      this.ctx.fillStyle = hg;
      this.ctx.beginPath();
      this.ctx.arc(headX, y, 16, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // ② 入射点白斑（到达后 0.2s 内闪一下）
    if (t > 0.32 && t < 0.62) {
      const p = (t - 0.32) / 0.3;
      const env = Math.sin(Math.PI * Math.min(p, 1));
      const sg = this.ctx.createRadialGradient(this.inX, this.inY, 0, this.inX, this.inY, 34);
      sg.addColorStop(0, this.rgba([255, 255, 255], 0.55 * env));
      sg.addColorStop(1, 'rgba(255,255,255,0)');
      this.ctx.fillStyle = sg;
      this.ctx.beginPath();
      this.ctx.arc(this.inX, this.inY, 34, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // ③ 棱镜内折射亮线：入射点 → 出射点 生长
    if (t > 0.55) {
      const p3 = Math.min((t - 0.34) / 0.2, 1);
      const ex = this.inX + (this.exX - this.inX) * p3;
      const ey = this.inY + (this.exY - this.inY) * p3;
      const rg = this.ctx.createLinearGradient(this.inX, this.inY, ex, ey);
      rg.addColorStop(0, 'rgba(240,248,255,0.7)');
      rg.addColorStop(1, 'rgba(240,248,255,0.25)');
      this.ctx.strokeStyle = rg;
      this.ctx.lineWidth = 2;
      this.ctx.beginPath();
      this.ctx.moveTo(this.inX, this.inY);
      this.ctx.lineTo(ex, ey);
      this.ctx.stroke();
      // 棱镜边线同步闪亮（logo 三顶点同款）
      const fl = Math.min((t - 0.34) / 0.22, 1) * (1 - Math.max(0, (t - 0.85) / 0.4));
      if (fl > 0) {
        this.ctx.strokeStyle = this.rgba([226, 238, 255], 0.5 * fl);
        this.ctx.lineWidth = 1.8;
        this.ctx.beginPath();
        this.ctx.moveTo(this.apexX, this.apexY);
        this.ctx.lineTo(this.prX, this.prY);
        this.ctx.lineTo(this.plX, this.plY);
        this.ctx.closePath();
        this.ctx.stroke();
      }
    }

    // ④ 色散扇：出射点向 base±13° 展开，光谱连续映射
    if (t > 0.5) {
      const p4 = Math.min((t - 0.5) / 0.45, 1);
      const e4 = 1 - Math.pow(1 - p4, 2.4);
      // 出射点暖晕
      const wg = this.ctx.createRadialGradient(this.exX, this.exY, 0, this.exX, this.exY, 30);
      wg.addColorStop(0, this.rgba([255, 250, 238], 0.5 * e4));
      wg.addColorStop(1, 'rgba(255,250,238,0)');
      this.ctx.fillStyle = wg;
      this.ctx.beginPath();
      this.ctx.arc(this.exX, this.exY, 30, 0, Math.PI * 2);
      this.ctx.fill();
      // 44 条细射线铺满扇形
      const N = 44;
      const spread = 26 * Math.PI / 180;
      for (let i = 0; i < N; i++) {
        const tt = i / (N - 1);
        const ang = this.specBase - spread / 2 + tt * spread;
        const len = this.specLen * (0.9 + 0.1 * Math.sin(tt * Math.PI)) * e4;
        const ex = this.exX + Math.cos(ang) * len;
        const ey = this.exY + Math.sin(ang) * len;
        // v3：展开期用六段光谱，0.95s 后向静态 logo 同款青蓝色板收敛
        const hm = this.homeMix(t);
        const spec = this.specColor(tt);
        const home = this.homeSpecColor(tt);
        const col = hm <= 0 ? spec : [spec[0] + (home[0] - spec[0]) * hm, spec[1] + (home[1] - spec[1]) * hm, spec[2] + (home[2] - spec[2]) * hm];
        const lg = this.ctx.createLinearGradient(this.exX, this.exY, ex, ey);
        lg.addColorStop(0, this.rgba(col, 0.5 * e4));
        lg.addColorStop(0.8, this.rgba(col, 0.12 * e4));
        lg.addColorStop(1, this.rgba(col, 0));
        this.ctx.strokeStyle = lg;
        this.ctx.lineWidth = 2.2;
        this.ctx.beginPath();
        this.ctx.moveTo(this.exX, this.exY);
        this.ctx.lineTo(ex, ey);
        this.ctx.stroke();
      }
    }
    this.ctx.globalAlpha = 1;
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}
