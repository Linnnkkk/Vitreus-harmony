import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 客服与反馈入口（GitHub Issues）：应用内含付费项目须提供客服联系方式
export const SUPPORT_ISSUES_URL: string = 'https://github.com/Linnnkkk/Vitreus-harmony/issues';

// 拉起系统默认浏览器（隐式 Want：viewData + browsable）
export function openExternalLink(ctx: common.UIAbilityContext, url: string): void {
  try {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    ctx.startAbility(want).catch((err: BusinessError) => {
      console.error(`[OpenLink] startAbility failed: ${err.code} ${err.message}`);
    });
  } catch (e) {
    console.error('[OpenLink] open failed: ' + JSON.stringify(e));
  }
}
