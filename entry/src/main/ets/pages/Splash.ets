import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;

  aboutToAppear() {
    // 2秒后自动跳转主页
    this.timerId = setTimeout(() => {
      router.replaceUrl({ url: 'pages/ModeSelect' });
    }, 2000);
  }

  aboutToDisappear() {
    clearTimeout(this.timerId);
  }

  build() {
    Stack() {
      // 全屏启动图 —— 替换成你的图片资源
      Image($r('app.media.splash'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
