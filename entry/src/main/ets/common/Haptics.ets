import { vibrator } from '@kit.SensorServiceKit';

// 轻触觉反馈：卡片选中/按钮点击的统一手感（参考 NDS/PPSSPP 鸿蒙版）
// 需 module.json5 声明 ohos.permission.VIBRATE（system_grant，无需弹窗）
// 三档手感：轻点（文字链）/ 选中（卡片、主按钮）/ 成功（导入完成等，双脉冲两响）
export function hapticLight(): void {
  hapticTap(12);
}

export function hapticSelect(): void {
  hapticTap(24);
}

export function hapticSuccess(): void {
  hapticTap(28);
  setTimeout(() => {
    hapticTap(28);
  }, 130);
}

export function hapticTap(duration: number = 22): void {
  try {
    vibrator.startVibration({
      type: 'time',
      duration: duration
    }, {
      id: 0,
      usage: 'touch'
    }).catch(() => {
      // 静默失败：触觉是锦上添花，不干扰主流程
    });
  } catch (e) {
    // 同上
  }
}
