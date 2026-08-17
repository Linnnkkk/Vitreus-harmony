import { router } from '@kit.ArkUI';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

@Entry
@Component
struct Splash {
  private timerId: number = 0;
  private permTimerId: number = 0;

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

  // 页面完全上屏后再申请权限：EntryAbility 的 loadContent 回调里弹会被
  // 窗口首帧/页面切换打断（弹窗序列中断，用户来不及点）。这里 onPageShow
  // 已渲染 + 500ms 缓冲，弹窗序列完整不被打断。
  onPageShow() {
    if (AppStorage.get<boolean>('permissionPending') === true) {
      this.permTimerId = setTimeout(() => {
        AppStorage.setOrCreate('permissionPending', false);
        this.requestAllPermissions();
      }, 500);
    }
  }

  private async requestAllPermissions(): Promise<void> {
    const permissions: Permissions[] = [
      'ohos.permission.CAMERA',
      'ohos.permission.READ_IMAGEVIDEO',
      'ohos.permission.WRITE_IMAGEVIDEO',
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await atManager.requestPermissionsFromUser(context, permissions);
    } catch (err) {
      hilog.error(DOMAIN, 'Splash', '权限申请失败: %{public}s', JSON.stringify(err));
    }
  }

  aboutToDisappear() {
    clearTimeout(this.timerId);
    clearTimeout(this.permTimerId);
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
