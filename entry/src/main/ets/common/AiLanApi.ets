import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LanShareApi } from './LanShareApi';

export interface AiLanAccess {
  vaultIds: string[];
  allowWrite: boolean;
}

export interface AiLanVault {
  id: string;
}

export interface AiLanStatus {
  running: boolean;
  port: number;
  deviceId: string;
  fingerprint: string;
  pairedClients: number;
  discoveryAvailable: boolean;
  discoveryError?: string;
  pairingCode?: string;
  pairingExpiresAt?: number;
  // Optional for older servers: absence must never imply authorization.
  access?: AiLanAccess;
  availableVaults?: AiLanVault[];
}

export class AiLanApi {
  private static readonly ENDPOINT: string = 'http://127.0.0.1:6791/api/admin/ai-lan';

  static async status(): Promise<AiLanStatus | null> {
    return AiLanApi.call(null);
  }

  static async enable(port?: number): Promise<AiLanStatus | null> {
    const body: AiLanRequest = { action: 'enable', ips: LanShareApi.getAllLanIps() };
    if (port !== undefined) {
      body.port = port;
    }
    const result = await AiLanApi.call(body);
    return result;
  }

  static async disable(): Promise<AiLanStatus | null> {
    const result = await AiLanApi.call({ action: 'disable' });
    return result;
  }

  static async pair(): Promise<AiLanStatus | null> {
    return AiLanApi.call({ action: 'pair' });
  }

  static async revoke(): Promise<AiLanStatus | null> {
    return AiLanApi.call({ action: 'revoke' });
  }

  static async setAccess(vaultIds: string[], allowWrite: boolean): Promise<AiLanStatus | null> {
    const access: AiLanAccess = { vaultIds: vaultIds.slice(), allowWrite: allowWrite };
    return AiLanApi.call({ action: 'access', access: access });
  }

  static hasAccessPolicy(status: AiLanStatus | null): boolean {
    if (status === null) {
      return false;
    }
    const access = status.access;
    const vaults = status.availableVaults;
    if (access === undefined || access === null || vaults === undefined || vaults === null ||
      !Array.isArray(access.vaultIds) || typeof access.allowWrite !== 'boolean' || !Array.isArray(vaults)) {
      return false;
    }
    for (let i = 0; i < access.vaultIds.length; i++) {
      if (typeof access.vaultIds[i] !== 'string' || access.vaultIds[i] === '') {
        return false;
      }
    }
    for (let i = 0; i < vaults.length; i++) {
      if (vaults[i] === null || typeof vaults[i] !== 'object' || typeof vaults[i].id !== 'string' || vaults[i].id === '') {
        return false;
      }
    }
    return true;
  }

  static pairingInfo(status: AiLanStatus): string {
    const info: AiLanPairingInfo = {
      version: 1,
      deviceId: status.deviceId,
      address: LanShareApi.getLanIp(),
      port: status.port,
      fingerprint: status.fingerprint,
      pairingCode: status.pairingCode ?? ''
    };
    return JSON.stringify(info);
  }

  private static async call(body: AiLanRequest | null): Promise<AiLanStatus | null> {
    return new Promise<AiLanStatus | null>((resolve) => {
      let client: http.HttpRequest | null = null;
      try {
        client = http.createHttp();
        const options: http.HttpRequestOptions = {
          method: body === null ? http.RequestMethod.GET : http.RequestMethod.POST,
          connectTimeout: 3000,
          readTimeout: 6000,
          expectDataType: http.HttpDataType.STRING
        };
        if (body !== null) {
          options.header = { 'Content-Type': 'application/json' } as Record<string, string>;
          options.extraData = JSON.stringify(body);
        }
        client.request(AiLanApi.ENDPOINT, options, (err: BusinessError, response: http.HttpResponse) => {
          if (client !== null) {
            client.destroy();
            client = null;
          }
          if ((err !== undefined && err !== null) || response.responseCode !== 200) {
            resolve(null);
            return;
          }
          try {
            resolve(JSON.parse(response.result as string) as AiLanStatus);
          } catch (e) {
            resolve(null);
          }
        });
      } catch (e) {
        if (client !== null) {
          client.destroy();
          client = null;
        }
        resolve(null);
      }
    });
  }
}

interface AiLanRequest {
  action: string;
  ips?: string[];
  port?: number;
  access?: AiLanAccess;
}

interface AiLanPairingInfo {
  version: number;
  deviceId: string;
  address: string;
  port: number;
  fingerprint: string;
  pairingCode: string;
}
