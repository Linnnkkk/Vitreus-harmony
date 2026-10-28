import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// 独立固定别名，不与 ignis 远程服务器凭据共享。
const ALIAS_PREFIX = 'vitreus.webdav.v1.';
const encoder = new util.TextEncoder();

export interface WebDavCredential {
  user: string;
  pwd: string;
}

export class WebDavCredentialStore {
  // 仅 NOT_FOUND 代表尚未配置；其他错误必须向调用方报告，避免覆盖旧凭据。
  static async load(credentialId: string): Promise<WebDavCredential | undefined> {
    if (!/^[a-z0-9]+$/.test(credentialId)) { throw new Error('invalid credential id'); }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encoder.encode(ALIAS_PREFIX + credentialId));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) { return undefined; }
      const secret = rows[0].get(asset.Tag.SECRET) as Uint8Array | undefined;
      if (secret === undefined) { throw new Error('missing credential'); }
      const text = new util.TextDecoder().decodeToString(secret);
      const split = text.indexOf('\u0000');
      if (split < 0) { throw new Error('invalid credential'); }
      return { user: text.substring(0, split), pwd: text.substring(split + 1) };
    } catch (e) {
      if ((e as BusinessError).code === 24000002) { return undefined; }
      throw new Error('credential read failed');
    }
  }

  static async save(credentialId: string, user: string, pwd: string): Promise<boolean> {
    if (!/^[a-z0-9]+$/.test(credentialId) || user.indexOf('\u0000') >= 0) { return false; }
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, encoder.encode(ALIAS_PREFIX + credentialId));
    attrs.set(asset.Tag.SECRET, encoder.encode(user + '\u0000' + pwd));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.THIS_DEVICE);
    // 永不覆盖已有别名，碰撞或失败时保留原配置与凭据。
    try { await asset.add(attrs); return true; } catch (e) { return false; }
  }
}
