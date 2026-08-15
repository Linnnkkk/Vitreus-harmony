import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;

  aboutToAppear() {
    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    PersistentStorage.persistProp('appMode', 'remote');
    // 有地址直接进主页，否则去模式选择
    this.timerId = setTimeout(() => {
      const url = AppStorage.get<string>('serverUrl') ?? '';
      const mode = AppStorage.get<string>('appMode') ?? 'remote';
      if (url !== '' && mode === 'remote') {
        router.replaceUrl({ url: 'pages/Index' });
      } else if (url !== '' && mode === 'local') {
        router.replaceUrl({ url: 'pages/NodeTest' });
      } else {
        router.replaceUrl({ url: 'pages/ModeSelect' });
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
