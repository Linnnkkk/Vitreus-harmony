import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';

export interface StartupPreference {
  lastMode: string;
  remember: boolean;
}

// filesDir 是启动偏好的唯一权威；appMode 仅用于旧版首次迁移和运行中兼容。
export class StartupPreferences {
  static validMode(mode: string): boolean {
    return mode === 'local' || mode === 'remote' || mode === 'ai' || mode === 'srv';
  }

  static filePath(context: common.UIAbilityContext): string {
    return context.filesDir + '/startup-preferences.json';
  }

  static load(context: common.UIAbilityContext): StartupPreference {
    const path = StartupPreferences.filePath(context);
    try {
      if (fs.accessSync(path)) {
        const rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
        const mode = typeof rec['lastMode'] === 'string' ? rec['lastMode'] as string : '';
        return { lastMode: StartupPreferences.validMode(mode) ? mode : '', remember: rec['remember'] !== false };
      }
    } catch (e) {
      // 已有文件但无法读取时不拿旧内存覆盖它，也不猜测入口。
      return { lastMode: '', remember: true };
    }
    const legacy = AppStorage.get<string>('appMode') ?? '';
    const config: StartupPreference = { lastMode: StartupPreferences.validMode(legacy) ? legacy : '', remember: true };
    // 只在文件不存在时迁移；保存失败仍可使用本次旧值，下次继续尝试。
    StartupPreferences.save(context, config);
    return config;
  }

  private static save(context: common.UIAbilityContext, config: StartupPreference): boolean {
    const path = StartupPreferences.filePath(context);
    const tmp = path + '.tmp';
    const body = JSON.stringify(config);
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, body); } finally { fs.closeSync(file); }
      if (fs.readTextSync(tmp) !== body) { return false; }
      fs.renameSync(tmp, path);
      return fs.readTextSync(path) === body;
    } catch (e) {
      return false;
    }
  }

  static restore(context: common.UIAbilityContext): StartupPreference {
    const config = StartupPreferences.load(context);
    AppStorage.setOrCreate('appMode', config.lastMode);
    return config;
  }

  static enterMode(context: common.UIAbilityContext, mode: string): boolean {
    if (!StartupPreferences.validMode(mode)) { return false; }
    const config = StartupPreferences.load(context);
    if (!StartupPreferences.save(context, { lastMode: mode, remember: config.remember })) { return false; }
    AppStorage.setOrCreate('appMode', mode);
    return true;
  }

  static setRemember(context: common.UIAbilityContext, remember: boolean): boolean {
    const config = StartupPreferences.load(context);
    return StartupPreferences.save(context, { lastMode: config.lastMode, remember: remember });
  }
}
