import common from '@ohos.app.ability.common';
import { fileIo as fs, fileShare, fileUri } from '@kit.CoreFileKit';

export interface VaultRootConfig {
  version: number;
  uri: string;
}

// The file is authoritative; a corrupt saved selection is an error, never a default root.
export class VaultRootSettings {
  static configPath(context: common.UIAbilityContext): string {
    return context.filesDir + '/vault-root-config.json';
  }

  static load(context: common.UIAbilityContext): VaultRootConfig {
    const path = VaultRootSettings.configPath(context);
    if (!fs.accessSync(path)) { return { version: 1, uri: '' }; }
    const value = JSON.parse(fs.readTextSync(path)) as VaultRootConfig;
    if (value === null || typeof value !== 'object' || value.version !== 1 || typeof value.uri !== 'string') {
      throw new Error('笔记库位置配置损坏，请重新选择位置');
    }
    return value;
  }

  static save(context: common.UIAbilityContext, config: VaultRootConfig): void {
    const path = VaultRootSettings.configPath(context);
    const temp = path + '.tmp';
    const body = JSON.stringify(config);
    const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, body); } finally { fs.closeSync(file); }
    if (fs.readTextSync(temp) !== body) { throw new Error('笔记库位置保存失败'); }
    // The rename is the commit point. A failure before it leaves the old selection intact.
    fs.renameSync(temp, path);
  }

  // AI 授权按库名记录；换了笔记库位置，同名库已是另一份笔记，必须在本地服务启动前清空授权。
  // 记录文件缺失时：默认位置视为未换（老用户升级不丢授权），自定义位置视为已换。
  // 清除失败直接抛错，不带着旧授权启动。
  static resetAiGrantsIfRootChanged(filesDir: string, uri: string): boolean {
    const record = filesDir + '/ai-access-root.json';
    const grants = filesDir + '/ignis-data/ai-lan/access.json';
    let changed = uri !== '';
    const known = fs.accessSync(record);
    if (known) {
      try {
        const last = JSON.parse(fs.readTextSync(record)) as VaultRootConfig;
        changed = last === null || typeof last !== 'object' || last.uri !== uri;
      } catch (e) {
        changed = true; // 记录损坏：按已更换处理，宁可让用户重新授权
      }
    }
    if (changed && fs.accessSync(grants)) {
      fs.unlinkSync(grants);
    }
    if (changed || !known) {
      const next: VaultRootConfig = { version: 1, uri: uri };
      const body = JSON.stringify(next);
      const file = fs.openSync(record + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, body); } finally { fs.closeSync(file); }
      fs.renameSync(record + '.tmp', record);
    }
    return changed;
  }

  static policy(uri: string): fileShare.PolicyInfo[] {
    return [{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE }];
  }

  // Never infer a physical path from an unapproved URI or silently replace a broken selection.
  static async resolveConfigured(context: common.UIAbilityContext): Promise<string> {
    const config = VaultRootSettings.load(context);
    if (config.uri === '') { return ''; }
    return await VaultRootSettings.activate(config.uri);
  }

  static async activate(uri: string): Promise<string> {
    if (uri === '') { throw new Error('没有指定笔记库位置'); }
    await fileShare.activatePermission(VaultRootSettings.policy(uri));
    const path = new fileUri.FileUri(uri).path;
    if (!path.startsWith('/') || !fs.statSync(path).isDirectory()) {
      throw new Error('所选笔记库位置不可用，请重新授权');
    }
    fs.listFileSync(path);
    return path;
  }
}
