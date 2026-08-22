import { router } from '@kit.ArkUI';

// 全局返回按钮：左上角圆形半透明箭头，所有页面可用
// target 传目标页路径则跳指定页，空则 router.back() 回退
@Component
export struct BackButton {
  target: string = '';
  @State private pressed: boolean = false;

  aboutToAppear() {
  }

  build() {
    Button({ stateEffect: true }) {
      // Stack 居中（'‹' 字形本身偏左偏上，translate 精确补偿到视觉中心）
      Stack({ alignContent: Alignment.Center }) {
        Text('‹')
          .fontSize(32)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .translate({ x: -1, y: -2 })
      }
      .width('100%')
      .height('100%')
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor('#33FFFFFF')
    .margin({ top: 56, left: 16 })
    .padding(0)
    .scale(this.pressed ? { x: 0.88, y: 0.88 } : { x: 1, y: 1 })
    .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (router.getLength() > 1) {
        router.back();
      } else if (this.target !== '') {
        router.replaceUrl({ url: this.target });
      } else {
        router.back();
      }
    })
  }
}
