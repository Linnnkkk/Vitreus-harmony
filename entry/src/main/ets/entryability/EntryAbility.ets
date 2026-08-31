import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { VipService } from '../common/VipService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // VIP 权益键持久化注册（进程最早点）：漏注册时 AppStorage 只在内存，杀进程权益即丢
    // （2026-08-30 恶性 bug：悬浮球开通会员→杀 App 重进→已购掉，根因即这三个键从未 persistProp）
    PersistentStorage.persistProp('vipPermanent', false);
    PersistentStorage.persistProp('vipUntil', 0);
    PersistentStorage.persistProp('vipSubProduct', '');
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    const mainWindow = windowStage.getMainWindowSync();
    mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false);

    // 窗口背景钉深蓝（App 全深色设计语言）：转场淡出露底时露出深蓝与页面渐变连续，
    // 而非系统默认白底——2026-09-01 真机抓拍实锤：旧页 opacity 淡出时左移残影区泛白
    try {
      mainWindow.setWindowBackgroundColor('#0F102B');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set window background. Cause: %{public}s', JSON.stringify(err));
    }

    // 沉浸式状态栏：全屏布局 + 状态栏透明，让 Obsidian 页面背景延伸到状态栏区域
    try {
      mainWindow.setWindowLayoutFullScreen(true);
      // 状态栏文字颜色固定白色（登录/启动页紫底需要；Obsidian 多为深色顶栏）
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set immersive status bar. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Splash', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 权限申请由网页页（Index/LocalWeb）onPageEnd 触发：启动阶段任何时点弹
      // 都会被窗口切换/首帧打断弹窗序列，等网页真正加载完再弹才稳
      AppStorage.setOrCreate('permissionPending', true);
      // 启动即恢复会员权益（queryPurchases 异步，不阻塞启动；失败保留旧值）
      VipService.restore(this.context).catch(() => {
        // IAP 环境异常（未签约设备等）静默：功能入口会在使用时给出提示
      });
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 长时任务自愈：用户删掉"数据传输"通知=系统注销任务，锁屏后 serverB 会被冻结。
    // 回前台时若伺服器还开着，重新申请长时任务（通知回来，无需杀进程重开 app）。
    if (AppStorage.get<boolean>('srvRunning') === true) {
      this.reapplyKeepAlive();
    }
  }

  private async reapplyKeepAlive(): Promise<void> {
    const ctx = this.context;
    try {
      // 先停再启：清掉系统侧残留（任务被注销但 app 内状态未同步时直接 start 会报已存在）
      await backgroundTaskManager.stopBackgroundRunning(ctx);
    } catch (e) {
      // 原本就没任务时 stop 会抛，无碍
    }
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      hilog.info(DOMAIN, 'testTag', 'keepalive reapplied on foreground');
    } catch (e) {
      // 重新申请也失败（罕见，如系统限制）：降级为关闭态，用户手动重开即可走全新流程
      hilog.error(DOMAIN, 'testTag', 'keepalive reapply failed: %{public}s', JSON.stringify(e));
      AppStorage.setOrCreate('srvModeEnabled', false);
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}