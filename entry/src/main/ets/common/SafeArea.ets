import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

// 状态栏高度(vp)：横屏平板的时钟会压住全屏 Web 的顶部 UI(issue#1)，
// Web 布局需从状态栏下方开始。失败返回 0（手机竖屏沉浸优先，退化为原布局）。
export async function getStatusbarHeightVp(ctx: common.UIAbilityContext): Promise<number> {
  try {
    const win = await window.getLastWindow(ctx);
    const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const density = display.getDefaultDisplaySync().density;
    if (density <= 0) {
      return 0;
    }
    return area.windowRect.height / density;
  } catch (e) {
    return 0;
  }
}