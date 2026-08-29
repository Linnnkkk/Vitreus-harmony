// 伺服器管理 API 公共封装（仅回环 http://127.0.0.1:6791/api/admin/lan-share）
// LanServerPage（持久开关）与 LocalWeb 悬浮球面板（会话开关）共用同一 serverB
import { http } from '@kit.NetworkKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface LanShareStatus {
  running: boolean;
  port: number;
  since: number;
  user: string;
}

export class LanShareApi {
  // Wi-Fi 本机 IP（整数转点分；无 Wi-Fi 返回空）
  static getLanIp(): string {
    try {
      const n = wifiManager.getIpInfo().ipAddress >>> 0;
      if (n === 0) {
        return '';
      }
      return ((n >>> 24) & 0xff) + '.' + ((n >>> 16) & 0xff) + '.' + ((n >>> 8) & 0xff) + '.' + (n & 0xff);
    } catch (e) {
      return '';
    }
  }

  static fullAddr(st: LanShareStatus): string {
    const ip = LanShareApi.getLanIp();
    return 'http://' + ip + ':' + st.port;
  }

  static async status(): Promise<LanShareStatus | null> {
    return LanShareApi.call(null);
  }

  static async enable(user: string, pass: string, port: number): Promise<LanShareStatus | null> {
    const body: LanShareApiBody = { action: 'enable', user: user, pass: pass, port: port };
    return LanShareApi.call(body);
  }

  static async disable(): Promise<LanShareStatus | null> {
    const body: LanShareApiBody = { action: 'disable' };
    return LanShareApi.call(body);
  }

  private static async call(body: LanShareApiBody | null): Promise<LanShareStatus | null> {
    return new Promise<LanShareStatus | null>((resolve) => {
      const client = http.createHttp();
      const opts: http.HttpRequestOptions = {
        method: body === null ? http.RequestMethod.GET : http.RequestMethod.POST,
        connectTimeout: 3000,
        readTimeout: 6000,
        expectDataType: http.HttpDataType.STRING
      };
      if (body !== null) {
        opts.header = { 'Content-Type': 'application/json' } as Record<string, string>;
        opts.extraData = JSON.stringify(body);
      }
      client.request('http://127.0.0.1:6791/api/admin/lan-share', opts,
        (err: BusinessError, resp: http.HttpResponse) => {
          client.destroy();
          const failed = (err !== undefined && err !== null) || resp.responseCode !== 200;
          if (failed) {
            resolve(null);
            return;
          }
          try {
            resolve(JSON.parse(resp.result as string) as LanShareStatus);
          } catch (e) {
            resolve(null);
          }
        });
    });
  }
}

// 管理API请求体（ArkTS：字面量必须对应显式interface）
interface LanShareApiBody {
  action: string;
  user?: string;
  pass?: string;
  port?: number;
}
