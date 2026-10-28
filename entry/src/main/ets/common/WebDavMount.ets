import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { WebDavSettings } from './WebDavSettings';
import { VipService } from './VipService';

interface MountedVault {
  id: string;
  remote?: boolean;
}

export class WebDavMount {
  static async verify(context: common.UIAbilityContext): Promise<string> {
    const config = WebDavSettings.load(context);
    if (config === undefined || !config.enabled) { return ''; }
    if (!VipService.isVip()) { throw new Error('WebDAV 远程库需要会员权益，请先开通或恢复购买'); }
    const request = http.createHttp();
    try {
      const response = await request.request('http://127.0.0.1:6791/api/vault/list', {
        method: http.RequestMethod.GET, connectTimeout: 5000, readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 200) { throw new Error('无法读取笔记库列表，请重试'); }
      const vaults = JSON.parse(response.result as string) as MountedVault[];
      const remote = vaults.find((vault: MountedVault) => vault.id === config.vaultName && vault.remote === true);
      if (remote === undefined) {
        throw new Error('远程库未挂载，请检查连接测试结果，并在保存后完全退出应用再打开；本地同名库也会阻止挂载');
      }
      return remote.id;
    } finally { request.destroy(); }
  }
}
