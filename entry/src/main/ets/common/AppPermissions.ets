import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// 权限申请（一次启动只弹一轮）：EntryAbility 启动时设 permissionPending=true，
// 网页页（Index/LocalWeb）加载完成后调本函数——网页上屏了弹窗才不会被窗口
// 切换/首帧打断（之前在 loadContent 回调/onPageShow 里弹都被打断过）。
export async function requestAppPermissionsOnce(context: common.UIAbilityContext): Promise<void> {
  if (AppStorage.get<boolean>('permissionPending') !== true) {
    return;
  }
  AppStorage.setOrCreate('permissionPending', false);
  const permissions: Permissions[] = [
    'ohos.permission.CAMERA',
    'ohos.permission.APPROXIMATELY_LOCATION',
    'ohos.permission.LOCATION'
  ];
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    await atManager.requestPermissionsFromUser(context, permissions);
  } catch (err) {
    hilog.error(DOMAIN, 'AppPermissions', '权限申请失败: %{public}s', JSON.stringify(err));
  }
}
