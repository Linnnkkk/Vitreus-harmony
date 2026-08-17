import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;

  aboutToAppear() {
    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    PersistentStorage.persistProp('appMode', 'remote');
    // 记住上次模式直接进（远程→Index；本地→本地流程），没记录才去模式选择。
    // 悬浮球点"‹"回 ModeSelect 后走重新选择流程（选择页不跳过）。
    this.timerId = setTimeout(() => {
      const url = AppStorage.get<string>('serverUrl') ?? '';
      const mode = AppStorage.get<string>('appMode') ?? '';
      if (mode === 'remote' && url !== '') {
        router.replaceUrl({ url: 'pages/Index' });
      } else if (mode === 'local') {
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
