import { router, display } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  private timerId: number = 0;
  // 窄屏（手机竖屏）用 9:19.5 竖版图，宽屏/平板用方图——方图在窄屏会被
  // objectFit(Cover) 放大裁切，棱镜和字标显示不全
  private splashSrc: Resource = $r('app.media.splash');

  aboutToAppear() {
    // 按屏幕长宽比选图：>1.6 视为窄屏手机，用竖版开屏图
    try {
      const dm = display.getDefaultDisplaySync();
      if (dm.height / dm.width > 1.6) {
        this.splashSrc = $r('app.media.splash_tall');
      }
    } catch (e) {
      // 拿不到屏幕信息就默认方图
    }

    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    PersistentStorage.persistProp('appMode', 'remote');
    // 记住上次模式直接进（远程→Index；本地→本地流程），没记录才去模式选择。
    // 悬浮球点"‹"回 ModeSelect 后走重新选择流程（选择页不跳过）。
    // 权限申请不在启动阶段：由网页页（Index/LocalWeb）加载完成后触发，
    // 启动期窗口切换会把没点完的权限弹窗序列打断。
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
      Image(this.splashSrc)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
