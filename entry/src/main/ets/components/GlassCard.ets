import { curves } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

// 玻璃卡片：原生背景模糊 + 1px 高光描边 + 进场弹簧动画
// 进场：0.94 缩放 + 透明度 → 1；内容变化引起的高度变化由调用方 animateTo 驱动
@Component
export struct GlassCard {
  @BuilderParam content: () => void = this.defaultContent;
  // 离场淡出由调用方置位
  @Prop faded: boolean = false;
  @State private shown: boolean = false;

  @Builder
  defaultContent() {
  }

  aboutToAppear(): void {
    this.getUIContext().animateTo({
      duration: Theme.MS_ENTER,
      curve: curves.springMotion(0.55, 0.85)
    }, () => {
      this.shown = true;
    });
  }

  build() {
    Column() {
      this.content()
    }
    .width('86%')
    .padding({ top: 26, bottom: 28, left: 22, right: 22 })
    .backgroundColor(Theme.CARD)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, { colorMode: ThemeColorMode.DARK })
    .borderRadius(Theme.R_CARD)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 40, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 12 })
    .alignItems(HorizontalAlign.Center)
    .opacity(this.shown && !this.faded ? 1 : 0)
    .scale({ x: this.shown ? 1 : 0.94, y: this.shown ? 1 : 0.94 })
  }
}
