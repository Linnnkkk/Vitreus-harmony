import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// 按需申请权限：网页真正用到相机 / 定位 / 剪贴板的那一刻才调用。
// 已授权直接返回 true，不弹窗；未授权则弹系统授权框，全部通过才返回 true。
export async function ensurePermissions(context: common.UIAbilityContext, permissions: Permissions[]): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = context.applicationInfo.accessTokenId;
    const missing: Permissions[] = [];
    for (const p of permissions) {
      const status = await atManager.checkAccessToken(tokenId, p);
      if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        missing.push(p);
      }
    }
    if (missing.length === 0) {
      return true;
    }
    const res = await atManager.requestPermissionsFromUser(context, missing);
    return res.authResults.every((r: number) => r === 0);
  } catch (err) {
    hilog.error(DOMAIN, 'AppPermissions', '权限申请失败: %{public}s', JSON.stringify(err));
    return false;
  }
}

export const LOCATION_PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];
