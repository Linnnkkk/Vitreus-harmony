import common from '@ohos.app.ability.common';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'QuickCapture';

// 默认库名：与 ignis config.js 的 AUTO_CREATE_DEFAULT 约定一致
const DEFAULT_VAULT_NAME = 'My Vault';

// T0 快捷捕获共用层（v1.2.0）：分享速记 + 小组件速记 + 网页剪藏
// 设计约束：不依赖 ignis 是否在跑（冷启分享场景 ignis 未启动）→ 一律直写 fs
export class QuickCapture {
  // 最近一次 vault 解析过程（调试面板用）
  static lastVaultDebug: string = '';

  static isPremiumFeature(): boolean {
    return false;
  }

  // ── vault 根定位 ──
  // 真实 VAULT_ROOT = NodeTest 用 DOWNLOAD 模式 picker 拿到的 Download 区目录
  // （node_embed.cpp: vaultOverride 探针通过则用它，失败才退回沙箱 filesDir/vaults）
  // 冷启动（app 没开）时必须能拿到，所以做了三重来源 + 沙箱文件落盘：
  //   1. AppStorage 持久键 vaultRootPath（PersistentStorage）
  //   2. 沙箱文件 filesDir/vault-root.txt（同步可读，不依赖 AppStorage 时序）
  //   3. filesDir/vaults（沙箱模式兜底）
  // 三处都没有 → 页面层再用 picker 兜底（见 resolveVaultAsync）

  static vaultRootFile(context: common.UIAbilityContext): string {
    return context.filesDir + '/vault-root.txt';
  }

  static readVaultRootFile(context: common.UIAbilityContext): string {
    try {
      const p = QuickCapture.vaultRootFile(context);
      if (fs.accessSync(p)) {
        return fs.readTextSync(p).trim();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readVaultRootFile failed: %{public}s', JSON.stringify(e));
    }
    return '';
  }

  // 记录 vault 根（AppStorage + 沙箱文件双写，确保冷启动可读）
  static saveVaultRoot(context: common.UIAbilityContext, root: string): void {
    if (root === '') {
      return;
    }
    AppStorage.setOrCreate('vaultRootPath', root);
    try {
      const p = QuickCapture.vaultRootFile(context);
      const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, root);
      fs.closeSync(f);
      hilog.info(DOMAIN, TAG, 'vault root saved: %{public}s', root);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveVaultRoot failed: %{public}s', JSON.stringify(e));
    }
  }

  // 同步解析 vault 目录（找不到返回 ''）
  static resolveVault(context: common.UIAbilityContext): string {
    const roots: string[] = [];
    const persisted: string = AppStorage.get<string>('vaultRootPath') ?? '';
    if (persisted !== '') {
      roots.push(persisted);
    }
    const fromFile = QuickCapture.readVaultRootFile(context);
    if (fromFile !== '' && roots.indexOf(fromFile) < 0) {
      roots.push(fromFile);
    }
    const sandbox = context.filesDir + '/vaults';
    if (roots.indexOf(sandbox) < 0) {
      roots.push(sandbox);
    }
    const detail: string[] = [];
    for (const root of roots) {
      const v = QuickCapture.pickVaultIn(root);
      detail.push(root + ' → ' + (v === '' ? '(无库)' : v));
      if (v !== '') {
        QuickCapture.lastVaultDebug = detail.join('\n');
        return v;
      }
    }
    // 根存在但没有子库 → 自动建默认库，避免"未找到笔记库"卡死快捷捕获
    for (const root of roots) {
      try {
        if (root !== '' && fs.accessSync(root)) {
          const created = QuickCapture.createVault(root, DEFAULT_VAULT_NAME);
          if (created !== '') {
            detail.push('已自动建库: ' + created);
            QuickCapture.lastVaultDebug = detail.join('\n');
            return created;
          }
        }
      } catch (e) {
        // ignore
      }
    }
    QuickCapture.lastVaultDebug = detail.join('\n') + '\n(均无库)';
    return '';
  }

  // 页面层兜底（需 UIContext，故不在 Ability.onCreate 里调）：
  // 三重来源都失败时用 picker 解析 Download 落点并落盘
  static async resolveVaultAsync(context: common.UIAbilityContext): Promise<string> {
    const v = QuickCapture.resolveVault(context);
    if (v !== '') {
      return v;
    }
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const opt = new picker.DocumentSaveOptions();
      opt.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris: string[] = await docPicker.save(opt);
      if (uris.length > 0) {
        const root = new fileUri.FileUri(uris[0]).path;
        QuickCapture.saveVaultRoot(context, root);
        QuickCapture.ensureDir(root);
        const created = QuickCapture.createVault(root, DEFAULT_VAULT_NAME);
        QuickCapture.lastVaultDebug += '\npicker → ' + root + ' → ' + created;
        return created;
      }
    } catch (e) {
      QuickCapture.lastVaultDebug += '\npicker 失败: ' + JSON.stringify(e);
      hilog.error(DOMAIN, TAG, 'picker vault resolve failed: %{public}s', JSON.stringify(e));
    }
    return '';
  }

  // 取（或建）指定名字的库；返回库目录路径，失败返回 ''
  private static createVault(root: string, name: string): string {
    try {
      const dir = root + '/' + name;
      QuickCapture.ensureDir(dir);
      QuickCapture.ensureDir(dir + '/.obsidian');
      if (fs.accessSync(dir)) {
        return dir;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'createVault failed: %{public}s', JSON.stringify(e));
    }
    return '';
  }

  private static ensureDir(path: string): boolean {
    try {
      if (fs.accessSync(path)) {
        return true;
      }
      const parts: string[] = path.split('/');
      let cur = '';
      for (const p of parts) {
        if (p === '') {
          cur = '/';
          continue;
        }
        cur = cur === '/' ? '/' + p : (cur === '' ? p : cur + '/' + p);
        if (!fs.accessSync(cur)) {
          fs.mkdirSync(cur);
        }
      }
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'ensureDir failed (%{public}s): %{public}s', path, JSON.stringify(e));
      return false;
    }
  }

  // 在一个 VAULT_ROOT 里挑库：优先含 .obsidian 的子目录；否则第一个子目录
  private static pickVaultIn(root: string): string {
    try {
      if (root === '' || !fs.accessSync(root)) {
        return '';
      }
      let firstDir = '';
      const names: string[] = fs.listFileSync(root).map((n: string) => n);
      for (const n of names) {
        if (n.startsWith('.')) {
          continue;
        }
        const p = root + '/' + n;
        try {
          if (!fs.statSync(p).isDirectory()) {
            continue;
          }
        } catch (e) {
          continue;
        }
        if (firstDir === '') {
          firstDir = p;
        }
        if (fs.accessSync(p + '/.obsidian')) {
          return p;
        }
      }
      if (firstDir !== '') {
        return firstDir;
      }
      if (fs.accessSync(root + '/.obsidian')) {
        return root;
      }
      return '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pickVaultIn failed (%{public}s): %{public}s', root, JSON.stringify(e));
      return '';
    }
  }

  static vaultName(vaultPath: string): string {
    if (vaultPath === '') {
      return '';
    }
    const i = vaultPath.lastIndexOf('/');
    return i >= 0 ? vaultPath.substring(i + 1) : vaultPath;
  }

  // ── 写入 ──

  // 追加一条速记到 Inbox.md（不存在则创建）。返回写入的完整行，失败返回 ''
  static appendInbox(context: common.UIAbilityContext, text: string, source: string): string {
    const vault = QuickCapture.resolveVault(context);
    if (vault === '') {
      hilog.warn(DOMAIN, TAG, 'no vault found, skip append');
      return '';
    }
    const line = QuickCapture.formatEntry(text, source);
    return QuickCapture.appendLine(vault, line) ? line : '';
  }

  // 追加一行到 vault 的 Inbox.md
  private static appendLine(vault: string, line: string): boolean {
    try {
      const inbox = vault + '/Inbox.md';
      let prev = '';
      if (fs.accessSync(inbox)) {
        prev = fs.readTextSync(inbox);
        if (prev.length > 0 && !prev.endsWith('\n')) {
          prev += '\n';
        }
      } else {
        prev = '# Inbox\n\n';
      }
      const f = fs.openSync(inbox, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, prev + line + '\n');
      fs.closeSync(f);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'appendLine failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  // 网页剪藏落盘：Clippings/<日期 时间 标题>.md，返回笔记名（不含扩展名，供 wikilink），失败返回 ''
  static saveClip(context: common.UIAbilityContext, title: string, url: string, body: string): string {
    const vault = QuickCapture.resolveVault(context);
    if (vault === '') {
      return '';
    }
    try {
      const dir = vault + '/Clippings';
      if (!QuickCapture.ensureDir(dir)) {
        return '';
      }
      const d = new Date();
      const stamp = '' + d.getFullYear() + '-' + QuickCapture.pad2(d.getMonth() + 1) + '-' +
        QuickCapture.pad2(d.getDate()) + ' ' + QuickCapture.pad2(d.getHours()) + QuickCapture.pad2(d.getMinutes());
      const safeTitle = QuickCapture.safeName(title !== '' ? title : '网页剪藏');
      const name = stamp + ' ' + safeTitle;
      const file = dir + '/' + name + '.md';
      const head = '---\nsource: ' + url + '\nclipped: ' + stamp + '\n---\n\n# ' + (title !== '' ? title : '网页剪藏') + '\n\n> 来源：' + url + '\n\n';
      const f = fs.openSync(file, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, head + body + '\n');
      fs.closeSync(f);
      hilog.info(DOMAIN, TAG, 'clip saved: %{public}s', file);
      return name;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveClip failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  // Inbox 里的剪藏索引行：- HH:mm [[笔记名]]
  static appendClipIndex(context: common.UIAbilityContext, noteName: string, url: string): string {
    const vault = QuickCapture.resolveVault(context);
    if (vault === '') {
      return '';
    }
    const d = new Date();
    const line = '- ' + QuickCapture.pad2(d.getHours()) + ':' + QuickCapture.pad2(d.getMinutes()) +
      ' 📄 [[' + noteName + ']]  <' + url + '>';
    return QuickCapture.appendLine(vault, line) ? line : '';
  }

  // 文件名安全化：去掉路径分隔符与 wikilink/正则敏感字符
  private static safeName(s: string): string {
    let t = s.replace(/[\\/:*?"<>|\[\]#^\r\n]/g, ' ');
    t = t.replace(/\s+/g, ' ').trim();
    if (t.length > 40) {
      t = t.substring(0, 40);
    }
    return t !== '' ? t : '网页剪藏';
  }

  static formatEntry(text: string, source: string): string {
    const d = new Date();
    const hh = QuickCapture.pad2(d.getHours());
    const mm = QuickCapture.pad2(d.getMinutes());
    const flat = text.replace(/[\r\n]+/g, ' ').trim();
    const src = source !== '' ? ' (来自 ' + source + ')' : '';
    return '- ' + hh + ':' + mm + ' ' + flat + src;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  // ── 兜底解析（非 Share Kit 直发 sendData want 的场景）──
  static parseWantFallback(want: Want): SharePayload {
    const out: SharePayload = { text: '', source: '' };
    try {
      const params = want.parameters as Record<string, Object> | undefined;
      let best = '';
      let bestScore = 0;
      if (params) {
        const keys = Object.keys(params);
        for (const k of keys) {
          const v = params[k];
          if (typeof v !== 'string' || k.startsWith('ability.') ||
            k.startsWith('ohos.extra.param.key.form')) {
            continue;
          }
          const s = v.trim();
          if (s === '') {
            continue;
          }
          // 打分而非"第一个非空"：URL 型最优，其次长文本，避免捞到
          // 发送方的附属标记（真机实测曾写入 "entry" 这类垃圾值）
          let score = 1;
          if (s.startsWith('http://') || s.startsWith('https://')) {
            score = 3;
          } else if (s.length >= 16) {
            score = 2;
          }
          if (score > bestScore) {
            bestScore = score;
            best = s;
          }
        }
      }
      if (best !== '') {
        out.text = best;
      } else if (want.uri && want.uri !== 'undefined') {
        out.text = want.uri;
      }
      out.source = '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parseWantFallback failed: %{public}s', JSON.stringify(e));
    }
    return out;
  }
}

export interface SharePayload {
  text: string;
  source: string;
}
