import { common } from '@kit.AbilityKit';
import { AiLanApi } from './AiLanApi';
import { LanShareApi } from './LanShareApi';
import { VipService } from './VipService';
import { BackgroundLease } from './BackgroundLease';

// Three independent axes: appMode = default entry; *ModeEnabled = saved
// owner intent; *Running = current process truth. Only cold Node bootstrap
// consumes saved intent. Page polling and floating controls never restore it.
export class ServiceRestore {
  private static task: Promise<void> | null = null;

  static once(context: common.UIAbilityContext): Promise<void> {
    if (ServiceRestore.task === null) {
      ServiceRestore.task = ServiceRestore.restore(context);
    }
    return ServiceRestore.task;
  }

  private static async restore(context: common.UIAbilityContext): Promise<void> {
    if (!VipService.isVip()) {
      AppStorage.setOrCreate('srvModeEnabled', false);
      AppStorage.setOrCreate('aiModeEnabled', false);
      return;
    }
    // Independent attempts: failure of one must not suppress the other.
    try {
      const status = await LanShareApi.status();
      if (status !== null) {
        let running = status.running;
        if (!running && AppStorage.get<boolean>('srvModeEnabled') === true) {
          const user = AppStorage.get<string>('lanShareUser') ?? '';
          const pass = AppStorage.get<string>('lanSharePass') ?? '';
          if (user !== '' && pass !== '' && VipService.isVip()) {
            const result = await LanShareApi.enable(user, pass, AppStorage.get<number>('lanSharePort') ?? 0);
            if (result !== null) {
              running = result.running;
              if (running) { AppStorage.setOrCreate('lanSharePort', result.port); }
            }
          }
        }
        AppStorage.setOrCreate('srvRunning', running);
      }
    } catch (error) { /* UI reports actual state; saved preference remains retryable next launch. */ }
    try {
      const status = await AiLanApi.status();
      if (status !== null) {
        let running = status.running;
        if (!running && AppStorage.get<boolean>('aiModeEnabled') === true &&
          VipService.isVip() && AiLanApi.hasAccessPolicy(status) && LanShareApi.getLanIp() !== '') {
          const result = await AiLanApi.enable();
          if (result !== null) { running = result.running; }
        }
        AppStorage.setOrCreate('aiRunning', running);
      }
    } catch (error) { /* Do not couple AI restoration to server restoration. */ }
    await BackgroundLease.reconcile(context);
  }
}
