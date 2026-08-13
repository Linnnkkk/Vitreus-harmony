import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;

  aboutToAppear() {
    // 注册持久化键（首次写磁盘，已存在则读出），之后 AppStorage 读写自动持久化
    PersistentStorage.persistProp('appMode', '');
    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    // authPwd 不持久化：交给鸿蒙密码保险箱，不明文存盘

    this.timerId = setTimeout(() => {
      const mode = AppStorage.get<string>('appMode') ?? '';
      if (mode === 'vps') {
        // 上次选了 VPS：有地址（+凭证）直接进主页，否则去填
        const url = AppStorage.get<string>('serverUrl') ?? '';
        if (url !== '') {
          router.replaceUrl({ url: 'pages/Index' });
        } else {
          router.replaceUrl({ url: 'pages/Login' });
        }
      } else if (mode === 'local') {
        // 本地模式（开发中：fs + JS Bridge 验证页）
        router.replaceUrl({ url: 'pages/LocalIndex' });
      } else {
        // 首次或未选 → 模式选择
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
