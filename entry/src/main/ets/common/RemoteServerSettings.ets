import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RemoteServerSettings';

export interface RemoteServerConfig {
  server: string;
}

// 远程服务器地址的权威存储。
// 只靠 PersistentStorage 记地址时，分享/速记独立冷启动会读不到，
// 表现为"关闭 App 后速记报尚未配置远程服务器"。这里落一个小 JSON 文件，
// 与 VipService / CapturePathSettings 同一思路：冷启动同步读得到。
export class RemoteServerSettings {
  static filePath(context: common.UIAbilityContext): string {
    return context.filesDir + '/remote-server.json';
  }

  static load(context: common.UIAbilityContext): RemoteServerConfig | undefined {
    try {
      const path = RemoteServerSettings.filePath(context);
      if (!fs.accessSync(path)) {
        return undefined;
      }
      const rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      const server = typeof rec['server'] === 'string' ? (rec['server'] as string).trim() : '';
      if (server === '' || !/^https?:\/\/[^/?#@\s]+/i.test(server)) {
        return undefined;
      }
      return { server: server };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load failed');
      return undefined;
    }
  }

  static save(context: common.UIAbilityContext, server: string): boolean {
    const normalized = server.trim().replace(/\/+$/, '');
    if (normalized === '' || !/^https?:\/\/[^/?#@\s]+/i.test(normalized)) {
      return false;
    }
    const body = '{"server":' + JSON.stringify(normalized) + '}';
    const path = RemoteServerSettings.filePath(context);
    const tmp = path + '.tmp';
    try {
      const f = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, body);
      } finally {
        fs.closeSync(f);
      }
      if (fs.readTextSync(tmp) !== body) {
        throw new Error('temporary verification failed');
      }
      fs.renameSync(tmp, path);
      // 不把 rename 成功当作保存成功：回读校验真实内容
      const stored = RemoteServerSettings.load(context);
      return stored !== undefined && stored.server === normalized;
    } catch (e) {
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (ignored) {
        // 清理失败不影响原文件
      }
      hilog.error(DOMAIN, TAG, 'save failed');
      return false;
    }
  }

  // 冷启动把文件里的地址灌回 AppStorage，供页面与捕获流程直接读取。
  static restore(context: common.UIAbilityContext): RemoteServerConfig | undefined {
    const config = RemoteServerSettings.load(context);
    if (config === undefined) {
      return undefined;
    }
    AppStorage.setOrCreate('serverUrl', config.server);
    return config;
  }
}
