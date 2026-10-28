import { http } from '@kit.NetworkKit';

interface DisableResponse {
  ok: boolean;
  localVault: string;
}

export class WebDavRuntime {
  static async disable(): Promise<string> {
    if (AppStorage.get<boolean>('ignisReady') !== true) {
      WebDavRuntime.cleared('');
      return '';
    }
    const request = http.createHttp();
    try {
      const result = await request.request('http://127.0.0.1:6791/api/vault/webdav/disable', {
        method: http.RequestMethod.POST, connectTimeout: 2000, readTimeout: 3000,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode !== 200) { throw new Error('远程库关闭未确认，请重试'); }
      const response = JSON.parse(result.result as string) as DisableResponse;
      if (response.ok !== true) { throw new Error('远程库关闭未确认，请重试'); }
      const local = typeof response.localVault === 'string' ? response.localVault : '';
      WebDavRuntime.cleared(local);
      return local;
    } finally { request.destroy(); }
  }

  private static cleared(local: string): void {
    AppStorage.setOrCreate('webDavRuntimeKey', '');
    AppStorage.setOrCreate('webDavOpenVault', '');
    AppStorage.setOrCreate('webDavPreferLocal', true);
    AppStorage.setOrCreate('webDavLocalVault', local);
  }
}
