// 液态玻璃光效层组件：内容在下，XComponent 光效层在上（菲涅尔边缘光+流光+触摸高光+涟漪）
// 架构：真实背景磨砂由卡片的 backgroundEffect 提供；本组件只叠光效（中心全透）
// native 侧：entry so 的 vtGlass* 系列（vt_glass_napi.cpp）
// ArkUI 组件/枚举（XComponent/XComponentController/XComponentType/HitTestMode）为全局符号，无需 import
import { vtGlassRegister, vtGlassUnregister, vtGlassSetParams, vtGlassStart, vtGlassStop, vtGlassTouch, vtGlassRipple } from 'libentry.so';

@Component
export struct GlassOverlay {
  @BuilderParam content: () => void = this.emptyContent;
  @Prop intensity: number = 1.0;    // 光效强度
  @Prop waveSpeed: number = 1.2;    // 边缘流光速度
  @Prop cornerRadius: number = 18;
  // 静态计数器保证 XComponent id 唯一（重复 id 会渲染错乱）
  private static nextId: number = 0;
  private glassId: string = 'vtg' + (++GlassOverlay.nextId) + '_' + Date.now();
  private areaW: number = 1;
  private areaH: number = 1;
  private lastRipple: number = 0;   // 涟漪 50ms 节流（NAPI 桥负载）

  @Builder
  emptyContent() {}

  aboutToAppear() {
    vtGlassRegister(this.glassId);
  }

  aboutToDisappear() {
    vtGlassStop(this.glassId);
    vtGlassUnregister(this.glassId);
  }

  build() {
    Stack() {
      this.content()

      XComponent({
        id: this.glassId,
        type: XComponentType.SURFACE,
        libraryname: 'entry'
      })
        .width('100%')
        .height('100%')
        .borderRadius(this.cornerRadius)
        .onLoad(() => {
          vtGlassSetParams(this.glassId, this.intensity, this.waveSpeed);
          vtGlassStart(this.glassId);
        })
        .onDestroy(() => {
          vtGlassStop(this.glassId);
          vtGlassUnregister(this.glassId);
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .borderRadius(this.cornerRadius)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 宽高缓存用于触摸坐标归一化（onTouch 里没有组件尺寸）
      this.areaW = Number(newArea.width) || 1;
      this.areaH = Number(newArea.height) || 1;
    })
    .onTouch((ev: TouchEvent) => {
      const nx = ev.touches[0].x / this.areaW;
      const ny = ev.touches[0].y / this.areaH;
      if (ev.type === TouchType.Down || ev.type === TouchType.Move) {
        vtGlassTouch(this.glassId, nx, ny);
        if (ev.type === TouchType.Down) {
          const now = Date.now();
          if (now - this.lastRipple >= 50) {
            vtGlassRipple(this.glassId, nx, ny, 1.0);
            this.lastRipple = now;
          }
        }
      }
    })
  }
}
