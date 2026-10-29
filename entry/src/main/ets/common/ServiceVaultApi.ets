import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface ServiceVault {
  id: string;
  remote: boolean;
}

export interface ServiceVaultStatus {
  availableVaults: ServiceVault[];
  activeVault: string;
  srvDefaultVault: string;
  aiDefaultVault: string;
  srvResolvedVault: string;
  aiResolvedVault: string;
}

interface ServiceVaultRequest {
  action: string;
  kind: string;
  vault: string;
}

export class ServiceVaultApi {
  private static readonly ENDPOINT: string = 'http://127.0.0.1:6791/api/admin/service-vaults';

  static async status(): Promise<ServiceVaultStatus | null> {
    return ServiceVaultApi.call(null);
  }

  // Empty vault follows the last active vault. This never changes AI authorization.
  static async set(kind: string, vault: string): Promise<ServiceVaultStatus | null> {
    if (kind !== 'srv' && kind !== 'ai') { return null; }
    return ServiceVaultApi.call({ action: 'set', kind: kind, vault: vault });
  }

  static async active(): Promise<string> {
    const status = await ServiceVaultApi.status();
    return status === null ? '' : status.activeVault;
  }

  private static valid(status: ServiceVaultStatus): boolean {
    if (status === null || typeof status !== 'object' || !Array.isArray(status.availableVaults) ||
      typeof status.activeVault !== 'string' || typeof status.srvDefaultVault !== 'string' ||
      typeof status.aiDefaultVault !== 'string' || typeof status.srvResolvedVault !== 'string' ||
      typeof status.aiResolvedVault !== 'string') { return false; }
    for (let i = 0; i < status.availableVaults.length; i++) {
      const vault = status.availableVaults[i];
      if (vault === null || typeof vault !== 'object' || typeof vault.id !== 'string' ||
        vault.id === '' || typeof vault.remote !== 'boolean') { return false; }
    }
    return true;
  }

  private static async call(body: ServiceVaultRequest | null): Promise<ServiceVaultStatus | null> {
    return new Promise<ServiceVaultStatus | null>((resolve) => {
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
        client.request(ServiceVaultApi.ENDPOINT, options, (err: BusinessError, response: http.HttpResponse) => {
          if (client !== null) { client.destroy(); client = null; }
          if ((err !== undefined && err !== null) || response === undefined || response === null ||
            response.responseCode !== 200) { resolve(null); return; }
          try {
            const status = JSON.parse(response.result as string) as ServiceVaultStatus;
            resolve(ServiceVaultApi.valid(status) ? status : null);
          } catch (error) { resolve(null); }
        });
      } catch (error) {
        if (client !== null) { client.destroy(); client = null; }
        resolve(null);
      }
    });
  }
}
