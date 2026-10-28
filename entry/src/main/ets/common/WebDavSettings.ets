import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';

export interface WebDavConfig {
  enabled: boolean;
  url: string;
  vaultName: string;
  credentialId: string;
}

// 仅保存非敏感配置，凭据由 WebDavCredentialStore 单独管理。
export class WebDavSettings {
  static normalizeUrl(value: string): string {
    const url = value.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/[^/?#@\s]+(?:\/[^?#\s]*)?$/i.test(url) || /[\\\x00-\x1f\x7f]/.test(url)) {
      throw new Error('请填写有效的 HTTP(S) 地址，不要在地址中包含账号、查询参数或片段');
    }
    return url;
  }

  static vaultNameFromUrl(value: string): string {
    const url = WebDavSettings.normalizeUrl(value);
    const path = url.replace(/^https?:\/\/[^/]+/i, '');
    const segment = path.slice(path.lastIndexOf('/') + 1);
    let name: string = '';
    try { name = decodeURIComponent(segment); } catch (e) {
      throw new Error('地址最后一层目录的编码无效，请检查地址');
    }
    if (name === '' || name.trim() !== name || name.startsWith('.') || /[\/\\\x00-\x1f\x7f]/.test(name)) {
      throw new Error('请填写具体的库目录；最后一层目录不能以点开头或包含斜杠、控制字符');
    }
    return name;
  }

  // Identifies a connection without placing account names or passwords in AppStorage.
  static connectionKey(config: WebDavConfig): string {
    return JSON.stringify([config.url, config.vaultName, config.credentialId]);
  }

  static needsRestart(config: WebDavConfig): boolean {
    if (AppStorage.get<boolean>('webDavRuntimeStarted') !== true) { return false; }
    const active = AppStorage.get<string>('webDavRuntimeKey') ?? '';
    return active !== (config.enabled ? WebDavSettings.connectionKey(config) : '');
  }

  static filePath(context: common.UIAbilityContext): string {
    return context.filesDir + '/webdav-settings.json';
  }

  static load(context: common.UIAbilityContext): WebDavConfig | undefined {
    const path = WebDavSettings.filePath(context);
    if (!fs.accessSync(path)) { return undefined; }
    const rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
    if (typeof rec['enabled'] !== 'boolean' || typeof rec['url'] !== 'string' ||
      typeof rec['vaultName'] !== 'string' || typeof rec['credentialId'] !== 'string' ||
      !/^[a-z0-9]+$/.test(rec['credentialId'] as string)) { throw new Error('invalid WebDAV settings'); }
    return { enabled: rec['enabled'] as boolean, url: rec['url'] as string,
      vaultName: rec['vaultName'] as string, credentialId: rec['credentialId'] as string };
  }

  static save(context: common.UIAbilityContext, config: WebDavConfig): boolean {
    const path = WebDavSettings.filePath(context);
    const tmp = path + '.tmp';
    const body = JSON.stringify(config);
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, body); } finally { fs.closeSync(file); }
      if (fs.readTextSync(tmp) !== body) { return false; }
      fs.renameSync(tmp, path);
      return fs.readTextSync(path) === body;
    } catch (e) { return false; }
  }
}
