import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { VipService } from '../common/VipService';
import { CapturePathSettings } from '../common/CapturePathSettings';
import { RemoteServerSettings } from '../common/RemoteServerSettings';
import { AiLanApi } from '../common/AiLanApi';
import { BackgroundLease } from '../common/BackgroundLease';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private vipCheckQueue: Promise<void> = Promise.resolve();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('aiRunning', false);
    // 预热 ArkWeb 内核（官方要求在 onCreate 调，早于任何 Web 组件创建）：
    // 否则进本地/远程网页页时要现场拉起渲染进程，白屏时间平白多出一截
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (e) {
      hilog.warn(DOMAIN, 'Vitreus', 'initializeWebEngine failed');
    }
    // VIP 权益键持久化注册（进程最早点）：漏注册时 AppStorage 只在内存，杀进程权益即丢
    // （2026-08-30 恶性 bug：悬浮球开通会员→杀 App 重进→已购掉，根因即这三个键从未 persistProp）
    PersistentStorage.persistProp('vipPermanent', false);
    PersistentStorage.persistProp('vipUntil', 0);
    PersistentStorage.persistProp('vipSubProduct', '');
    // vault 根（Download 区 picker 返回目录）：分享速记/小组件在 ShareAbility 里
    // 要用与 ignis 同一个 VAULT_ROOT 落点，由 NodeTest 启动本地模式时写入
    PersistentStorage.persistProp('vaultRootPath', '');
    // 多库时用户选定的目标库（速记/剪藏落点）
    PersistentStorage.persistProp('activeVault', '');
    PersistentStorage.persistProp('activeVaultPath', '');
    // 一次性版本公告按公告 ID 记录，后续新公告可再次展示。
    PersistentStorage.persistProp('lastSeenNoticeId', '');
    // 【⑤】VIP 权益从显式状态文件读回（飞行模式实验实锤 PersistentStorage 不可靠）。
    // 必须在所有 persistProp 之后：文件值是权威，覆盖不可靠的持久化默认值
    VipService.init(this.context);
    CapturePathSettings.init(this.context);
    // 远程服务器地址/账号标签同样从文件权威恢复（冷启动比 PersistentStorage 可靠）
    try {
      RemoteServerSettings.restore(this.context);
    } catch (e) {
      hilog.warn(DOMAIN, 'Vitreus', 'restore remote server failed');
    }
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
      // 启动即恢复会员权益（queryPurchases 异步，不阻塞启动；失败保留旧值）
      VipService.restore(this.context).catch(() => {
        // IAP 环境异常（未签约设备等）静默：功能入口会在使用时给出提示
      });
      // VIP 运行中复检（2026-09-20 审计④）：伺服器只在开启时刻过门禁，订阅过期后进程不死会一直跑。
      // 进程级 10 分钟定时器（2026-10-13 用户四条规则：不重启 10 分钟内探测收回）——
      // restore 拉华为侧真值后本地踢；enforceFull 内置 10 分钟节流，周期多 5 秒保证每轮都能过闸
      setInterval(() => {
        this.enforceVipAndAi();
      }, 10 * 60 * 1000 + 5000);
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // VIP 复检（⑥b 完全体）：走 enforceFull=网络 restore（含⑥退款撤权）+本地踢，
    // enforceFull 内置 10 分钟节流（高频回前台只做零网络本地踢，节流命中自动降级）。
    // 退款白嫖窗口由此从 12h 收紧到"回前台+10min 节流"。
    // 放在长时任务自愈之前：先踢再自愈，踢完 srvRunning=false 不会再申请
    this.enforceVipAndAi().then(() => {
      if (AppStorage.get<boolean>('srvRunning') === true || AppStorage.get<boolean>('aiRunning') === true) {
        this.reapplyKeepAlive();
      }
    });
  }

  private async reapplyKeepAlive(): Promise<void> {
    const ctx = this.context;
    try {
      const leaseOk = await BackgroundLease.reapply(ctx);
      if (!leaseOk) {
        throw new Error('DATA_TRANSFER unavailable');
      }
      hilog.info(DOMAIN, 'testTag', 'keepalive reapplied on foreground');
    } catch (e) {
      // 重新申请也失败（罕见，如系统限制）：降级为关闭态，用户手动重开即可走全新流程
      hilog.error(DOMAIN, 'testTag', 'keepalive reapply failed: %{public}s', JSON.stringify(e));
      // Background permission failure is not a change to the owner's saved switch.
    }
  }

  private enforceVipAndAi(): Promise<void> {
    this.vipCheckQueue = this.vipCheckQueue.then(async () => {
      await VipService.enforceFull(this.context);
      if (AppStorage.get<boolean>('aiRunning') === true && !VipService.isVip()) {
        const aiStatus = await AiLanApi.disable();
        if (aiStatus !== null) {
          AppStorage.setOrCreate('aiRunning', aiStatus.running);
        }
      }
      if (AppStorage.get<boolean>('srvRunning') !== true && AppStorage.get<boolean>('aiRunning') !== true) {
        await BackgroundLease.reconcile(this.context);
      }
    }).catch(() => {
    });
    return this.vipCheckQueue;
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}