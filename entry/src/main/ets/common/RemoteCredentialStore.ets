import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// 远程保存的服务器账号凭据。
// 明文只存在于进程内存；落盘走系统保险箱（AssetStoreKit），与 Cetus 的服务器密码同一做法：
// 只在本设备可用（DEVICE_FIRST_UNLOCKED），不参与任何云同步（SYNC_TYPE.THIS_DEVICE）。
const ALIAS_PREFIX = 'vitreus.remote.';
const encoder = new util.TextEncoder();

export interface RemoteCredential {
  server: string;
  user: string;
  pwd: string;
}

export class RemoteCredentialStore {
  private static cache: Map<string, RemoteCredential> = new Map<string, RemoteCredential>();

  private static normalizeServer(server: string): string {
    return server.trim().replace(/\/+$/, '');
  }

  private static aliasOf(server: string): string {
    // 别名里不放明文服务器地址：字符串哈希稳定、不泄露主机名
    let hash = 5381;
    for (let i = 0; i < server.length; i++) {
      hash = ((hash << 5) + hash + server.charCodeAt(i)) | 0;
    }
    return ALIAS_PREFIX + (hash >>> 0).toString(36);
  }

  static remember(server: string, user: string, pwd: string): void {
    server = RemoteCredentialStore.normalizeServer(server);
    const item: RemoteCredential = { server: server, user: user, pwd: pwd };
    RemoteCredentialStore.cache.set(server, item);
  }

  static forget(server: string): void {
    server = RemoteCredentialStore.normalizeServer(server);
    RemoteCredentialStore.cache.delete(server);
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encoder.encode(RemoteCredentialStore.aliasOf(server)));
    asset.remove(query).catch(() => {
      // 条目不存在视为已删除
    });
  }

  // 进程内取用（界面已经输入过的凭据）
  static memory(server: string): RemoteCredential | undefined {
    return RemoteCredentialStore.cache.get(RemoteCredentialStore.normalizeServer(server));
  }

  static async save(server: string, user: string, pwd: string): Promise<boolean> {
    server = RemoteCredentialStore.normalizeServer(server);
    if (server === '' || user.indexOf('\u0000') >= 0) {
      return false;
    }
    const alias = RemoteCredentialStore.aliasOf(server);
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encoder.encode(alias));
    const update: asset.AssetMap = new Map();
    update.set(asset.Tag.SECRET, encoder.encode(user + '\u0000' + pwd));
    try {
      // SDK: update(query: AssetMap, attributesToUpdate: AssetMap): Promise<void>.
      // 不先 remove：更新失败时旧凭据和 cache 都保持不变。
      await asset.update(query, update);
    } catch (e) {
      if ((e as BusinessError).code !== 24000002) {
        return false;
      }
      // 只有 NOT_FOUND 才创建，设备锁定/服务异常等错误绝不当作「无条目」。
      const attrs: asset.AssetMap = new Map();
      attrs.set(asset.Tag.ALIAS, encoder.encode(alias));
      attrs.set(asset.Tag.SECRET, encoder.encode(user + '\u0000' + pwd));
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.THIS_DEVICE);
      try {
        await asset.add(attrs);
      } catch (addError) {
        return false;
      }
    }
    RemoteCredentialStore.remember(server, user, pwd);
    return true;
  }

  // 冷启动读取：先查内存，再查系统保险箱
  static async load(server: string): Promise<RemoteCredential | undefined> {
    server = RemoteCredentialStore.normalizeServer(server);
    const cached = RemoteCredentialStore.cache.get(server);
    if (cached !== undefined) {
      return cached;
    }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encoder.encode(RemoteCredentialStore.aliasOf(server)));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) {
        return undefined;
      }
      const secret = rows[0].get(asset.Tag.SECRET) as Uint8Array | undefined;
      if (secret === undefined) {
        return undefined;
      }
      const text = new util.TextDecoder().decodeToString(secret);
      const split = text.indexOf('\u0000');
      if (split < 0) {
        return undefined;
      }
      const item: RemoteCredential = {
        server: server,
        user: text.substring(0, split),
        pwd: text.substring(split + 1)
      };
      RemoteCredentialStore.cache.set(server, item);
      return item;
    } catch (e) {
      return undefined;
    }
  }
}
