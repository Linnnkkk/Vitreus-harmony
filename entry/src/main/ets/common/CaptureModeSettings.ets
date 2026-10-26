import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';
import { StartupPreferences } from './StartupPreferences';

// 捕获选择独立于主浏览模式；未显式选择时才跟随主模式。文件是唯一权威。
export class CaptureModeSettings {
  static isRemote(context: common.UIAbilityContext): boolean {
    try {
      const path = context.filesDir + '/capture-mode.json';
      if (fs.accessSync(path)) {
        const rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
        if (rec['mode'] === 'remote') { return true; }
        if (rec['mode'] === 'local') { return false; }
      }
    } catch (e) {
      // 未选择/损坏时回到主模式；空、AI、伺服器入口都按本地处理。
    }
    return StartupPreferences.load(context).lastMode === 'remote';
  }

  static save(context: common.UIAbilityContext, remote: boolean): boolean {
    const path = context.filesDir + '/capture-mode.json';
    const tmp = path + '.tmp';
    const body = JSON.stringify({ mode: remote ? 'remote' : 'local' });
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
}
