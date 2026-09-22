import common from '@ohos.app.ability.common';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { VipService } from './VipService';
import { CapturePathSettings } from './CapturePathSettings';
import { CapturePathTemplate, CapturePathTemplates } from './CapturePathTemplate';

const DOMAIN = 0x0000;
const TAG = 'QuickCapture';

// 默认库名（用户拍板 2026-09-17）：自动建的库叫 vault（ignis 的 "My Vault" 约定不再沿用）
const DEFAULT_VAULT_NAME = 'vault';

// T0 快捷捕获共用层（v1.2.0）：分享速记 + 小组件速记 + 网页剪藏
// 设计约束：不依赖 ignis 是否在跑（冷启分享场景 ignis 未启动）→ 一律直写 fs
export class QuickCapture {
  // 最近一次 vault 解析过程（调试面板用）
  static lastVaultDebug: string = '';

  static isPremiumFeature(): boolean {
    return VipService.isVip();
  }

  static previewQuickTarget(context: common.UIAbilityContext, text: string): string {
    const capture = QuickCapture.createQuickCaptureContextAt(context, text, Date.now());
    return capture.quickPath;
  }

  static destinationLabel(context: common.UIAbilityContext, text: string): string {
    const target = QuickCapture.previewQuickTarget(context, text);
    return target === 'Inbox.md' ? 'Inbox.md' : '自定义规则';
  }

  static createCaptureContext(context: common.UIAbilityContext, title: string, site: string): CaptureContext {
    return QuickCapture.createCaptureContextAt(context, title, site, Date.now());
  }

  static createCaptureContextAt(context: common.UIAbilityContext, title: string, site: string,
    capturedAt: number): CaptureContext {
    const settings = CapturePathSettings.load(context);
    return QuickCapture.createCaptureContextAtWithSettings(context, title, site, capturedAt, settings);
  }

  private static createCaptureContextAtWithSettings(context: common.UIAbilityContext, title: string, site: string,
    capturedAt: number, settings: CapturePathTemplates): CaptureContext {
    const vault = QuickCapture.resolveVault(context);
    const vaultName = QuickCapture.vaultName(vault);
    const actualTitle = title.trim() !== '' ? title.trim() : '速记';
    const actualSite = site.trim() !== '' ? site.trim() : '无站点';
    let quickPath = 'Inbox.md';
    let quickHeading = '';
    let clipPath = '';
    if (vault !== '' && QuickCapture.isPremiumFeature()) {
      const quickValues = CapturePathTemplate.makeValues(capturedAt, actualTitle, '速记', vaultName);
      const headingCheck = CapturePathTemplate.validateHeading(settings.quickNoteHeading);
      if (headingCheck.valid) {
        quickHeading = settings.quickNoteHeading.trim();
      }
      if (settings.quickNotePath !== '') {
        const quick = CapturePathTemplate.expand(settings.quickNotePath, quickValues);
        if (quick.valid) {
          quickPath = quick.path;
        }
      }
      if (settings.clipPath !== '') {
        const clipValues = CapturePathTemplate.makeValues(capturedAt, actualTitle, actualSite, vaultName);
        const clip = CapturePathTemplate.expand(settings.clipPath, clipValues);
        // 剪藏正文不能写到索引目标，也不能写到旧版 Inbox 根文件。
        if (clip.valid && clip.path !== 'Inbox.md' && clip.path !== quickPath) {
          clipPath = clip.path;
        }
      }
    }
    return {
      vault: vault,
      vaultName: vaultName,
      capturedAt: capturedAt,
      title: actualTitle,
      site: actualSite,
      quickPath: quickPath,
      quickHeading: quickHeading,
      clipPath: clipPath
    };
  }

  // 速记回退和纯文本分享共用的上下文入口，标题严格取正文首个非空行。
  static createQuickCaptureContextAt(context: common.UIAbilityContext, text: string,
    capturedAt: number): CaptureContext {
    return QuickCapture.createCaptureContextAt(context, QuickCapture.firstLine(text), '速记', capturedAt);
  }

  // 网页剪藏在抓取完成后才知道标题，但仍沿用抓取开始时传入的时间戳。
  static createClipCaptureContextAt(context: common.UIAbilityContext, title: string, url: string,
    metadata: ClipMetadata | undefined, capturedAt: number): CaptureContext {
    const actualTitle = title.trim() !== '' ? title.trim() : '网页剪藏';
    const site = metadata !== undefined && metadata.site !== '' ? metadata.site :
      CapturePathTemplate.hostFromUrl(url);
    return QuickCapture.createCaptureContextAt(context, actualTitle, site, capturedAt);
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

  // 候选 VAULT_ROOT（按优先级）：持久键 → 沙箱文件 → 沙箱默认目录
  private static candidateRoots(context: common.UIAbilityContext): string[] {
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
    return roots;
  }

  // 列出所有库（多库支持）：root 下每个子目录 = 一个库；带 .obsidian 的排前面
  static listVaults(context: common.UIAbilityContext): VaultEntry[] {
    const roots = QuickCapture.candidateRoots(context);
    const found: VaultEntry[] = [];
    const seenPaths: string[] = [];
    for (const root of roots) {
      let names: string[] = [];
      try {
        if (root === '' || !fs.accessSync(root)) {
          continue;
        }
        names = fs.listFileSync(root).map((n: string) => n);
      } catch (e) {
        continue;
      }
      const withMeta: string[] = [];
      const others: string[] = [];
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
        if (fs.accessSync(p + '/.obsidian')) {
          withMeta.push(n);
        } else {
          others.push(n);
        }
      }
      const ordered = withMeta.concat(others);
      for (const n of ordered) {
        const fullPath = root + '/' + n;
        if (seenPaths.indexOf(fullPath) < 0) {
          seenPaths.push(fullPath);
          // 显式类型变量：ArkTS 严格模式对匿名对象字面量会报 arkts-no-untyped-obj-literals
          const ent: VaultEntry = { name: n, path: fullPath };
          found.push(ent);
        }
      }
    }
    // 同名库也要能在多库选择页中区分；写入时始终按 path 记忆，避免误落到另一个根目录。
    const nameCounts: Record<string, number> = {};
    for (const v of found) {
      const count: number = nameCounts[v.name] ?? 0;
      nameCounts[v.name] = count + 1;
    }
    const out: VaultEntry[] = [];
    for (const v of found) {
      const displayName = (nameCounts[v.name] ?? 0) > 1 ? v.name + ' (' + v.path + ')' : v.name;
      const ent: VaultEntry = { name: displayName, path: v.path };
      out.push(ent);
    }
    return out;
  }

  // 记住用户选的目标库（多库时用；跨进程持久）。保存完整路径，避免同名库被根目录优先级误选。
  static setActiveVault(name: string): void {
    AppStorage.setOrCreate('activeVault', name);
    // 旧式按名称设置必须清掉旧路径，否则名称选择会被路径记忆覆盖。
    AppStorage.setOrCreate('activeVaultPath', '');
  }

  static setActiveVaultPath(path: string): void {
    AppStorage.setOrCreate('activeVaultPath', path);
    const slash = path.lastIndexOf('/');
    AppStorage.setOrCreate('activeVault', slash >= 0 ? path.substring(slash + 1) : path);
  }

  // 同步解析 vault 目录：优先用户选过的库，其次带 .obsidian 的首个；找不到返回 ''
  static resolveVault(context: common.UIAbilityContext): string {
    const list = QuickCapture.listVaults(context);
    const detail: string[] = [];
    detail.push('库数=' + list.length + ' [' + list.map((v: VaultEntry) => v.name).join(', ') + ']');
    if (list.length > 0) {
      const wantedPath: string = AppStorage.get<string>('activeVaultPath') ?? '';
      if (wantedPath !== '') {
        for (const v of list) {
          if (v.path === wantedPath) {
            detail.push('选中(记忆)=' + v.path);
            QuickCapture.lastVaultDebug = detail.join('\n');
            return v.path;
          }
        }
        detail.push('记忆的库路径不存在: ' + wantedPath);
      }
      const want: string = AppStorage.get<string>('activeVault') ?? '';
      if (want !== '') {
        const matches: VaultEntry[] = list.filter((v: VaultEntry) => v.name === want);
        if (matches.length === 1) {
          detail.push('选中(兼容名称)=' + matches[0].name);
          QuickCapture.lastVaultDebug = detail.join('\n');
          return matches[0].path;
        }
        if (matches.length > 1) {
          detail.push('记忆的库名称有歧义: ' + want);
        } else {
          detail.push('记忆的库不存在: ' + want);
        }
      }
      detail.push('选中(默认)=' + list[0].name);
      QuickCapture.lastVaultDebug = detail.join('\n');
      return list[0].path;
    }
    // 一个库都没有：根存在则自动建默认库，避免"未找到笔记库"卡死快捷捕获
    for (const root of QuickCapture.candidateRoots(context)) {
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

  static vaultName(vaultPath: string): string {
    if (vaultPath === '') {
      return '';
    }
    const i = vaultPath.lastIndexOf('/');
    return i >= 0 ? vaultPath.substring(i + 1) : vaultPath;
  }

  // ── 写入 ──

  // 追加一条速记到当前有效目标。返回写入的完整行，失败返回 ''。
  static appendInbox(context: common.UIAbilityContext, text: string, source: string): string {
    return QuickCapture.appendInboxAt(context, text, source, Date.now());
  }

  // 使用调用方提供的时间戳，保证模板路径与可见时间来自同一次捕获。
  static appendInboxAt(context: common.UIAbilityContext, text: string, source: string,
    capturedAt: number): string {
    const line = QuickCapture.formatEntryAt(text, source, capturedAt);
    if (line === '') {
      return '';
    }
    const capture = QuickCapture.createQuickCaptureContextAt(context, text, capturedAt);
    if (capture.vault === '') {
      hilog.warn(DOMAIN, TAG, 'no vault found, skip append');
      return '';
    }
    const target = capture.quickPath;
    if (QuickCapture.appendLine(capture.vault, target, line, capture.quickHeading)) {
      return line;
    }
    // 自定义目录或目标写入失败时，仍保留旧版可靠落点。
    if (target !== 'Inbox.md' && QuickCapture.appendLine(capture.vault, 'Inbox.md', line)) {
      return line;
    }
    return '';
  }

  // 使用已解析上下文写入速记，供一次分享流水线复用同一份路径快照。
  static appendInboxWithContext(context: CaptureContext, text: string, source: string): string {
    const line = QuickCapture.formatEntryAt(text, source, context.capturedAt);
    if (line === '' || context.vault === '') {
      return '';
    }
    if (QuickCapture.appendLine(context.vault, context.quickPath, line, context.quickHeading)) {
      return line;
    }
    if (context.quickPath !== 'Inbox.md' && QuickCapture.appendLine(context.vault, 'Inbox.md', line)) {
      return line;
    }
    return '';
  }

  // 追加一行到 vault-relative Markdown 文件；先临时文件后原子替换。
  private static appendLine(vault: string, relativePath: string, line: string,
    heading: string = ''): boolean {
    const file = vault + '/' + relativePath;
    const tmp = file + '.tmp';
    try {
      const slash = file.lastIndexOf('/');
      if (slash > 0 && !QuickCapture.ensureDir(file.substring(0, slash))) {
        return false;
      }
      let prev = '';
      if (fs.accessSync(file)) {
        prev = fs.readTextSync(file);
      } else {
        prev = relativePath === 'Inbox.md' ? '# Inbox\n\n' : '';
      }
      const updated = CapturePathTemplate.insertUnderHeading(prev, line, heading);
      const f = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, updated);
      fs.closeSync(f);
      fs.renameSync(tmp, file);
      return true;
    } catch (e) {
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (cleanup) {
        // 临时文件清理失败不覆盖原始写入错误。
      }
      hilog.error(DOMAIN, TAG, 'appendLine failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  // 网页剪藏落盘：默认 Clippings/<日期 时间 标题>.md，VIP 时使用自定义模板。
  // 返回去掉 .md 的 vault-relative 笔记名，供 wikilink；失败返回 ''。
  static saveClip(context: common.UIAbilityContext, title: string, url: string, body: string,
    metadata?: ClipMetadata): string {
    const capturedAt = Date.now();
    const capture = QuickCapture.createClipCaptureContextAt(context, title, url, metadata, capturedAt);
    return QuickCapture.saveClipWithContext(capture, title, url, body, metadata);
  }

  // 使用共享捕获上下文写入正文；索引可继续复用同一时间戳和路径快照。
  static saveClipWithContext(capture: CaptureContext, title: string, url: string, body: string,
    metadata?: ClipMetadata): string {
    if (capture.vault === '') {
      return '';
    }
    const d = new Date(capture.capturedAt);
    const stamp = '' + d.getFullYear() + '-' + QuickCapture.pad2(d.getMonth() + 1) + '-' +
      QuickCapture.pad2(d.getDate()) + ' ' + QuickCapture.pad2(d.getHours()) +
      QuickCapture.pad2(d.getMinutes()) + QuickCapture.pad2(d.getSeconds());
    const actualTitle = title.trim() !== '' ? title.trim() : '网页剪藏';
    const custom = capture.clipPath;
    const written = QuickCapture.writeClip(capture.vault, custom, actualTitle, url, body, metadata, stamp);
    if (written !== '') {
      return written;
    }
    return QuickCapture.writeClip(capture.vault, '', actualTitle, url, body, metadata, stamp);
  }

  private static writeClip(vault: string, relativeTarget: string, title: string, url: string, body: string,
    metadata: ClipMetadata | undefined, stamp: string): string {
    let tmp = '';
    try {
      let baseName = relativeTarget;
      if (baseName === '') {
        const safeTitle = QuickCapture.safeName(title);
        baseName = 'Clippings/' + stamp + ' ' + safeTitle + '.md';
      }
      if (!baseName.endsWith('.md')) {
        baseName += '.md';
      }
      const slash = baseName.lastIndexOf('/');
      const dir = slash >= 0 ? vault + '/' + baseName.substring(0, slash) : vault;
      if (!QuickCapture.ensureDir(dir)) {
        return '';
      }
      const relWithoutExt = baseName.substring(0, baseName.length - 3);
      let name = relWithoutExt;
      let file = vault + '/' + name + '.md';
      let suffix = 2;
      while (fs.accessSync(file) && suffix <= 50) {
        name = relWithoutExt + ' (' + suffix + ')';
        file = vault + '/' + name + '.md';
        suffix += 1;
      }
      if (fs.accessSync(file)) {
        hilog.error(DOMAIN, TAG, 'saveClip: too many filename collisions');
        return '';
      }
      let head = '---\nsource: ' + QuickCapture.yamlValue(url) + '\nclipped: ' +
        QuickCapture.yamlValue(stamp);
      if (metadata !== undefined) {
        if (metadata.description !== '') {
          head += '\ndescription: ' + QuickCapture.yamlValue(metadata.description);
        }
        if (metadata.site !== '') {
          head += '\nsite: ' + QuickCapture.yamlValue(metadata.site);
        }
        if (metadata.author !== '') {
          head += '\nauthor: ' + QuickCapture.yamlValue(metadata.author);
        }
        if (metadata.published !== '') {
          head += '\npublished: ' + QuickCapture.yamlValue(metadata.published);
        }
        if (metadata.canonical !== '') {
          head += '\ncanonical: ' + QuickCapture.yamlValue(metadata.canonical);
        }
      }
      head += '\n---\n\n# ' + title + '\n\n> 来源：' + url + '\n\n';
      tmp = file + '.tmp';
      const f = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, head + body + '\n');
      fs.closeSync(f);
      fs.renameSync(tmp, file);
      hilog.info(DOMAIN, TAG, 'clip saved: %{public}s', file);
      return name;
    } catch (e) {
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (cleanup) {
        // 临时文件清理失败不覆盖原始写入错误。
      }
      hilog.error(DOMAIN, TAG, 'saveClip failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  // Inbox 里的剪藏索引行：VIP 有效时跟随速记模板，否则使用旧 Inbox.md。
  static appendClipIndex(context: common.UIAbilityContext, noteName: string, url: string): string {
    const capturedAt = Date.now();
    const title = noteName !== '' ? noteName.substring(noteName.lastIndexOf('/') + 1) : '网页剪藏';
    const capture = QuickCapture.createCaptureContextAt(context, title, CapturePathTemplate.hostFromUrl(url), capturedAt);
    return QuickCapture.appendClipIndexWithContext(capture, noteName, url);
  }

  // 使用同一网页标题和同一时间戳生成索引，避免正文与索引模板展开不一致。
  static appendClipIndexWithContext(capture: CaptureContext, noteName: string, url: string): string {
    if (capture.vault === '') {
      return '';
    }
    const d = new Date(capture.capturedAt);
    const line = '- ' + QuickCapture.pad2(d.getHours()) + ':' + QuickCapture.pad2(d.getMinutes()) +
      ' 📄 [[' + noteName + ']]  <' + url + '>';
    if (QuickCapture.appendLine(capture.vault, capture.quickPath !== '' ? capture.quickPath : 'Inbox.md', line,
      capture.quickHeading)) {
      return line;
    }
    if (capture.quickPath !== '' && capture.quickPath !== 'Inbox.md' &&
      QuickCapture.appendLine(capture.vault, 'Inbox.md', line)) {
      return line;
    }
    return '';
  }


  private static firstLine(text: string): string {
    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines = normalized.split('\n');
    for (const raw of lines) {
      const line = raw.trim();
      if (line !== '') {
        return line;
      }
    }
    return '';
  }

  // 文件名安全化：去掉路径分隔符与 wikilink/正则敏感字符
  private static safeName(s: string): string {
    let t = s.replace(/[\\/:*?"<>|\[\]#^\r\n]/g, ' ');
    t = t.replace(/\s+/g, ' ').trim();
    if (t.length > 40) {
      t = t.substring(0, 40);
      const last = t.charCodeAt(t.length - 1);
      if (last >= 55296 && last <= 56319) {
        t = t.substring(0, t.length - 1);
      }
    }
    return t !== '' ? t : '网页剪藏';
  }

  static formatEntry(text: string, source: string): string {
    return QuickCapture.formatEntryAt(text, source, Date.now());
  }

  static formatEntryAt(text: string, source: string, capturedAt: number): string {
    const d = new Date(capturedAt);
    const hh = QuickCapture.pad2(d.getHours());
    const mm = QuickCapture.pad2(d.getMinutes());
    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
    const rawLines: string[] = normalized.split('\n');
    const lines: string[] = [];
    for (const raw of rawLines) {
      const line = raw.trim();
      if (line !== '') {
        lines.push(line);
      }
    }
    if (lines.length === 0) {
      return '';
    }
    const src = source !== '' ? ' (来自 ' + source + ')' : '';
    const out: string[] = [];
    out.push('- ' + hh + ':' + mm + ' ' + lines[0] + src);
    for (let i = 1; i < lines.length; i++) {
      // 两个空格让 Markdown 把后续行视为同一个列表项，而不是新条目。
      out.push('  ' + lines[i]);
    }
    return out.join('\n');
  }

  // 写入 YAML frontmatter 时统一双引号并清掉换行，避免元数据破坏 frontmatter 结构。
  private static yamlValue(value: string): string {
    const clean = value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\r\n]+/g, ' ');
    return '"' + clean + '"';
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

// 库条目（多库选择用）
export interface CaptureContext {
  vault: string;
  vaultName: string;
  capturedAt: number;
  title: string;
  site: string;
  quickPath: string;
  quickHeading: string;
  clipPath: string;
}

export interface VaultEntry {
  name: string;
  path: string;
}

export interface SharePayload {
  text: string;
  source: string;
}

// 网页剪藏可识别的元数据；未识别字段保持空字符串，不虚构内容。
export interface ClipMetadata {
  description: string;
  site: string;
  author: string;
  published: string;
  canonical: string;
}
