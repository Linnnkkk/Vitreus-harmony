import { common } from '@kit.AbilityKit';
import { LanShareApi } from './LanShareApi';
import { AiLanApi } from './AiLanApi';
import { VipService } from './VipService';
import { BackgroundLease } from './BackgroundLease';

// The home controls change service intent, never the remembered entry mode.
export class HomeServiceControl {
  static async change(context: common.UIAbilityContext, kind: string, enabled: boolean): Promise<string> {
    if (enabled && !VipService.isVip()) { return 'vip'; }
    if (AppStorage.get<boolean>('ignisReady') !== true) {
      if (enabled) { return 'startup'; }
      AppStorage.setOrCreate(kind === 'srv' ? 'srvModeEnabled' : 'aiModeEnabled', false);
      AppStorage.setOrCreate(kind === 'srv' ? 'srvRunning' : 'aiRunning', false);
      return '';
    }
    if (enabled && LanShareApi.getLanIp() === '') { return '请先连接 Wi-Fi，或开启热点让电脑接入同一局域网'; }
    if (kind === 'srv') {
      const user = AppStorage.get<string>('lanShareUser') ?? '';
      const pass = AppStorage.get<string>('lanSharePass') ?? '';
      if (enabled && (user === '' || pass === '')) { return 'srvSetup'; }
      const result = enabled ? await LanShareApi.enable(user, pass, AppStorage.get<number>('lanSharePort') ?? 0) : await LanShareApi.disable();
      if (result === null) { return '操作结果未确认，请稍后重试'; }
      AppStorage.setOrCreate('srvRunning', result.running);
      if (result.running === enabled) { AppStorage.setOrCreate('srvModeEnabled', enabled); }
      if (result.running) { AppStorage.setOrCreate('lanSharePort', result.port); }
      if (result.running !== enabled) { return '伺服器状态未改变，请进入伺服器模式查看'; }
    } else {
      if (enabled) {
        const status = await AiLanApi.status();
        if (!AiLanApi.hasAccessPolicy(status)) { return 'aiSetup'; }
        if (!VipService.isVip()) { return 'vip'; }
      }
      const result = enabled ? await AiLanApi.enable() : await AiLanApi.disable();
      if (result === null) { return '操作结果未确认，请稍后重试'; }
      AppStorage.setOrCreate('aiRunning', result.running);
      if (result.running === enabled) { AppStorage.setOrCreate('aiModeEnabled', enabled); }
      if (result.running !== enabled) { return 'AI 连接状态未改变，请进入 AI 连接查看'; }
    }
    const leased = await BackgroundLease.reconcile(context);
    return enabled && !leased ? '服务已开启，后台运行受限，请保持应用在前台' : '';
  }
}
