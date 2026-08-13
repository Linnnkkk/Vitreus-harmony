import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;

  aboutToAppear() {
    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    // 纯 VPS 模式：有地址直接进主页，否则去登录页
    this.timerId = setTimeout(() => {
      const url = AppStorage.get<string>('serverUrl') ?? '';
      if (url !== '') {
        router.replaceUrl({ url: 'pages/Index' });
      } else {
        router.replaceUrl({ url: 'pages/Login' });
      }
    }, 2000);
  }

  aboutToDisappear() {
    clearTimeout(this.timerId);
  }

  build() {
    Stack() {
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
