import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { QuickCapture, SharePayload } from '../common/QuickCapture';

const DOMAIN = 0x0000;
const TAG = 'ShareAbility';

// T0 分享接收 + 速记入口（v1.2.0）
// 两个进入路径：
//   1) 系统分享面板（ohos.want.action.sendData）→ 确认页 pages/ShareCapture
//   2) 桌面小组件 router 事件（params.mode === 'quicknote'）→ 输入页 pages/QuickNote
// 独立于 EntryAbility（singleton 各自独立）：分享/速记不打扰 Obsidian 主流程，
// ignis 不在跑也完全可用（直写 fs，见 common/QuickCapture）
export default class ShareAbility extends UIAbility {
  // 最近一次 want 的 mode（onWindowStageCreate 异步加载页面时消费）
  private pendingMode: string = 'share';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.pendingMode = this.wantMode(want);
    this.dumpWant('onCreate', want);
    // 解析结果交给确认页消费（冷启主路径）
    if (this.pendingMode === 'share') {
      AppStorage.setOrCreate('sharePayload', QuickCapture.parseShareWant(want));
    }
  }

  // singleton 热启路径：App 已在跑时再次分享 / 再次点小组件
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.pendingMode = this.wantMode(want);
    this.dumpWant('onNewWant', want);
    // 热启再次分享：写入 sharePayload（若当前 window 已在 ShareCapture 页，
    // 页面 onPageShow 监听 shareNewArrive 变化重新保存）
    const payload = QuickCapture.parseShareWant(want);
    AppStorage.setOrCreate('sharePayload', payload);
    AppStorage.setOrCreate('shareNewText', payload.text);
    AppStorage.setOrCreate('shareNewArrive', Date.now());
  }

  private wantMode(want: Want): string {
    const m = want.parameters?.['mode'];
    if (m === 'quicknote') {
      return 'quicknote';
    }
    return 'share';
  }

  private dumpWant(where: string, want: Want): void {
    hilog.info(DOMAIN, TAG, '%{public}s: action=%{public}s uri=%{public}s bundle=%{public}s',
      where, want.action ?? '', want.uri ?? '', want.bundleName ?? '');
    try {
      const p = want.parameters as Record<string, Object> | undefined;
      if (p) {
        hilog.info(DOMAIN, TAG, '%{public}s params keys: %{public}s', where, JSON.stringify(Object.keys(p)));
      }
    } catch (e) {
      // ignore
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 窗口样式对齐主应用：深蓝底钉住 + 沉浸式状态栏（转场不闪白）
    const mainWindow = windowStage.getMainWindowSync();
    try {
      mainWindow.setWindowBackgroundColor('#0F102B');
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'window style failed: %{public}s', JSON.stringify(err));
    }

    const page = this.pendingMode === 'quicknote' ? 'pages/QuickNote' : 'pages/ShareCapture';
    windowStage.loadContent(page, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
