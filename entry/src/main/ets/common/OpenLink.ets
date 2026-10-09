import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

// 客服与反馈入口（GitHub Issues）：应用内含付费项目须提供客服联系方式
export const SUPPORT_ISSUES_URL: string = 'https://github.com/Linnnkkk/Vitreus-harmony/issues';

// 客服邮箱（审核要求除 GitHub Issues 外另留邮箱）
export const SUPPORT_EMAIL: string = 'vitreus@tutamail.com';

// 复制文本到剪贴板并提示
export function copyText(text: string, tip: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: tip });
    }).catch((err: BusinessError) => {
      console.error(`[OpenLink] copy failed: ${err.code} ${err.message}`);
    });
  } catch (e) {
    console.error('[OpenLink] copy failed: ' + JSON.stringify(e));
  }
}

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
