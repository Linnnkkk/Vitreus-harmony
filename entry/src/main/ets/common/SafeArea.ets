import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

// PAD-like 顶部状态栏高度(vp)：折叠屏展开也通过逻辑宽度命中。
// 手机移动布局返回 0，避免移动版 Obsidian 双重下移。
const PAD_MIN_WIDTH_VP = 600;
export async function getStatusbarHeightVp(ctx: common.UIAbilityContext): Promise<number> {
  try {
    const win = await window.getLastWindow(ctx);
    const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const screen = display.getDefaultDisplaySync();
    const density = screen.densityPixels;
    if (density <= 0 || screen.width / density < PAD_MIN_WIDTH_VP) {
      return 0;
    }
    return Math.max(0, area.topRect.height / density);
  } catch (e) {
    return 0;
  }
}