import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CapturePathTemplate, CapturePathTemplates } from './CapturePathTemplate';
import { QuickCapture } from './QuickCapture';
import { WebClip } from './WebClip';

export interface RemoteResponse {
  status: number;
  body: string;
  contentType: string;
  error: string;
  // 401 时的 WWW-Authenticate 原文，用于 Basic/Digest 认证
  authChallenge?: string;
}
export type RemoteRequester = (method: string, route: string, body: string) => Promise<RemoteResponse>;
export interface RemoteVault { id: string; name: string; }
export interface RemoteWriteBody {
  vault: string;
  path: string;
  content: string;
  encoding: string;
  recursive: boolean;
}
export interface RemoteCaptureOperation {
  version: number;
  id: string;
  text: string;
  isTask: boolean;
  addTime: boolean;
  kind: string;
  capturedAt: number;
  serverURL: string;
  stage: string;
  vault: string;
  quickPath: string;
  quickHeading: string;
  clipPath: string;
  clipBody: string;
  entry: string;
  before: string;
  after: string;
  existed: boolean;
  templates: CapturePathTemplates;
  premium: boolean;
  clipFallbackPath?: string;
}


export class RemoteCaptureFailure extends Error {
  code: string;
  status: number;
  constructor(code: string, message: string, status: number = 0) {
    super(message); this.code = code; this.status = status;
  }
}

// A single durable operation, never a local-vault fallback. Credentials are not part of this record.
export class RemoteCapture {
  static isRemote(): boolean {
    return AppStorage.get<string>('appMode') === 'remote' &&
      (AppStorage.get<string>('serverUrl') ?? '').trim() !== '';
  }
  static normalizeServer(value: string): string {
    const url = value.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/[^/?#@]+(?::\d+)?(?:\/[^?#]*)?$/i.test(url) || /[\s\\]/.test(url)) {
      throw new Error('请输入不含账号、查询参数或片段的 HTTP(S) 服务器地址');
    }
    const path = url.replace(/^https?:\/\/[^/]+/i, '');
    if (path !== '') { throw new Error('当前验证版只支持根地址部署，请勿填写 /ignis 等路径前缀'); }
    return url;
  }
  private static validate(op: RemoteCaptureOperation): void {
    if (op === undefined || op.version !== 1 || typeof op.id !== 'string' ||
      !/^[a-zA-Z0-9-]+$/.test(op.id) || typeof op.text !== 'string' ||
      typeof op.serverURL !== 'string' || typeof op.stage !== 'string' ||
      typeof op.capturedAt !== 'number' || !Number.isFinite(op.capturedAt) ||
      typeof op.isTask !== 'boolean' || typeof op.addTime !== 'boolean' ||
      typeof op.kind !== 'string' || typeof op.premium !== 'boolean' ||
      op.templates === undefined || typeof op.templates.quickNotePath !== 'string' ||
      typeof op.templates.quickNoteHeading !== 'string' || typeof op.templates.clipPath !== 'string' ||
      typeof op.vault !== 'string' || typeof op.quickPath !== 'string' || typeof op.quickHeading !== 'string' ||
      typeof op.clipPath !== 'string' || typeof op.clipBody !== 'string' || typeof op.entry !== 'string' ||
      typeof op.before !== 'string' || typeof op.after !== 'string' || typeof op.existed !== 'boolean') {
      throw new Error('远程捕获记录损坏，未覆盖原记录');
    }
    RemoteCapture.normalizeServer(op.serverURL);
  }
  static load(context: common.UIAbilityContext): RemoteCaptureOperation | undefined {
    const path = context.filesDir + '/remote-capture-pending.json';
    if (!fs.accessSync(path)) { return undefined; }
    const op = JSON.parse(fs.readTextSync(path)) as RemoteCaptureOperation;
    RemoteCapture.validate(op);
    return op;
  }
  static persist(context: common.UIAbilityContext, op: RemoteCaptureOperation): void {
    const path = context.filesDir + '/remote-capture-pending.json';
    const file = fs.openSync(path + '.tmp', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, JSON.stringify(op)); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
  }
  static archive(context: common.UIAbilityContext, op: RemoteCaptureOperation): void {
    const path = context.filesDir + '/remote-capture-archive-' + op.id + '.json';
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, JSON.stringify(op)); } finally { fs.closeSync(file); }
    op.stage = 'archived';
    RemoteCapture.persist(context, op);
  }
  static marker(op: RemoteCaptureOperation): string { return '<!-- vitreus-capture:' + op.id + ' -->'; }
}

export class RemoteCaptureEngine {
  private static activeOperations: Set<string> = new Set<string>();
  private context: common.UIAbilityContext;
  private request: RemoteRequester;
  constructor(context: common.UIAbilityContext, request: RemoteRequester) {
    this.context = context; this.request = request;
  }
  // ArkTS only allows throwing Error subclasses; normalize whatever catch received.
  static asError(e: Object): Error {
    return e instanceof Error ? e : new Error(String(e));
  }
  private checkpoint(op: RemoteCaptureOperation, stage: string): void {
    op.stage = stage; RemoteCapture.persist(this.context, op);
  }
  private async call(method: string, route: string, body: string = ''): Promise<RemoteResponse> {
    let r: RemoteResponse;
    try { r = await this.request(method, route, body); }
    catch (err) { throw new RemoteCaptureFailure('unknown', '连不上服务器或请求超时。请检查服务器地址、网络与账号密码，然后点「重试连接」。'); }
    if (r.error !== '' || r.status === 0) { throw new RemoteCaptureFailure('unknown', '连不上服务器或请求超时。请检查服务器地址、网络与账号密码，然后点「重试连接」。'); }
    if (r.contentType.toLowerCase().indexOf('text/html') >= 0 || /^\s*(<!doctype|<html)/i.test(r.body)) {
      throw new RemoteCaptureFailure('global', '服务器返回登录网页，请先使用网页登录', r.status);
    }
    return r;
  }
  // Only responses proving rejection before a content write may change targets. A generic
  // 4xx/5xx, success-shaped malformed payload, or transport error is never such proof.
  static classifyResponse(r: RemoteResponse, beforeContentWrite: boolean = false): string {
    if (r.error !== '' || r.status === 0) { return 'unknown'; }
    if (r.contentType.toLowerCase().indexOf('text/html') >= 0 || /^\s*(<!doctype|<html)/i.test(r.body)) { return 'global'; }
    if (r.contentType.toLowerCase().indexOf('application/json') < 0) { return 'unknown'; }
    let data: Record<string, Object>;
    try { data = JSON.parse(r.body) as Record<string, Object>; } catch (e) { return 'unknown'; }
    if (r.status === 403 && data['error'] === 'Path traversal rejected') { return 'prewrite-rejected'; }
    if (r.status === 401 || r.status === 403 || r.status === 429 || data['error'] === 'Vault not found') { return 'global'; }
    if (beforeContentWrite && (r.status === 400 || r.status === 404 || r.status === 500) &&
      ['ENOTDIR', 'EISDIR', 'EACCES', 'EPERM', 'ENAMETOOLONG', 'EEXIST'].indexOf(data['code'] as string) >= 0) {
      return 'prewrite-rejected';
    }
    return 'unknown';
  }
  private rejection(r: RemoteResponse, beforeContentWrite: boolean): RemoteCaptureFailure {
    return new RemoteCaptureFailure(RemoteCaptureEngine.classifyResponse(r, beforeContentWrite),
      '服务器 API 返回异常 HTTP ' + r.status, r.status);
  }
  private canFallback(e: Object): boolean {
    if (!(e instanceof RemoteCaptureFailure)) { return false; }
    const failure: RemoteCaptureFailure = e as RemoteCaptureFailure;
    return failure.code === 'prewrite-rejected';
  }
  private json(r: RemoteResponse): Record<string, Object> {
    if (r.status < 200 || r.status >= 300 || r.contentType.indexOf('application/json') < 0) {
      throw new Error('服务器 API 返回异常 HTTP ' + r.status);
    }
    return JSON.parse(r.body) as Record<string, Object>;
  }
  async listVaults(): Promise<RemoteVault[]> {
    const version = this.json(await this.call('GET', '/api/version'));
    if (typeof version['version'] !== 'string') { throw new Error('不是兼容的 ignis 服务器'); }
    const r = await this.call('GET', '/api/vault/list');
    if (r.status !== 200 || r.contentType.indexOf('application/json') < 0) { throw new Error('读取远程库失败'); }
    const list = JSON.parse(r.body) as RemoteVault[];
    if (!Array.isArray(list)) { throw new Error('远程库列表格式不正确'); }
    for (const v of list) {
      if (typeof v.id !== 'string' || v.id === '' || typeof v.name !== 'string') {
        throw new Error('远程库标识格式不正确');
      }
    }
    return list;
  }
  private route(op: RemoteCaptureOperation, action: string, path: string): string {
    return '/api/fs/' + action + '?vault=' + encodeURIComponent(op.vault) + '&path=' +
      encodeURIComponent(path) + '&encoding=utf8';
  }
  private async read(op: RemoteCaptureOperation, path: string): Promise<RemoteResponse> {
    const r = await this.call('GET', this.route(op, 'readFile', path));
    if (r.status === 404 && r.contentType.toLowerCase().indexOf('application/json') >= 0) {
      const error = JSON.parse(r.body) as Record<string, Object>;
      if (error['code'] === 'ENOENT') { return r; }
    }
    if (r.status !== 200 || r.contentType.toLowerCase().indexOf('text/plain') < 0) { throw this.rejection(r, true); }
    return r;
  }
  private async mutate(op: RemoteCaptureOperation, action: string, path: string, content: string = ''): Promise<void> {
    const body: RemoteWriteBody = { vault: op.vault, path: path, content: content, encoding: 'utf8', recursive: true };
    const r = await this.call(action === 'unlink' ? 'DELETE' : 'POST',
      action === 'unlink' ? this.route(op, action, path) : '/api/fs/' + action, JSON.stringify(body));
    if (r.status < 200 || r.status >= 300) { throw this.rejection(r, action === 'mkdir'); }
    if (this.json(r)['ok'] !== true) { throw new RemoteCaptureFailure('unknown', '服务器未确认写入', r.status); }
  }
  private async mkdir(op: RemoteCaptureOperation, path: string): Promise<void> {
    const slash = path.lastIndexOf('/');
    if (slash >= 0) { await this.mutate(op, 'mkdir', path.substring(0, slash)); }
  }
  async prepare(op: RemoteCaptureOperation, vault: RemoteVault): Promise<void> {
    if (op.stage !== 'new') {
      if (op.vault !== vault.id) { throw new Error('已准备的记录不能改库，以免重复保存'); }
      return;
    }
    op.vault = vault.id;
    let title = op.text.replace(/\r/g, '').split('\n').filter((s: string) => s.trim() !== '')[0] ?? '速记';
    let site = '速记';
    let url = '';
    if (op.kind === 'share') { url = WebClip.pickUrl(op.text); }
    let clip = WebClip.skipped();
    if (url !== '') {
      clip = await WebClip.fetch(url);
      if (clip.ok) { title = clip.title.trim() || '网页剪藏'; site = clip.metadata.site || CapturePathTemplate.hostFromUrl(url); }
    }
    const values = CapturePathTemplate.makeValues(op.capturedAt, title, site, vault.name);
    op.quickPath = 'Inbox.md';
    if (op.premium) {
      const quickValues = CapturePathTemplate.makeValues(op.capturedAt, title, '速记', vault.name);
      const quick = CapturePathTemplate.expand(op.templates.quickNotePath, quickValues);
      if (quick.valid) { op.quickPath = quick.path; }
      if (CapturePathTemplate.validateHeading(op.templates.quickNoteHeading).valid) {
        op.quickHeading = op.templates.quickNoteHeading.trim();
      }
    }
    if (clip.ok) {
      let base = 'Clippings/' + values.today + ' ' + values.time + ' ' +
        title.replace(/[\\/:*?"<>|\[\]#^\r\n]/g, ' ').replace(/\s+/g, ' ').trim().substring(0, 40) + '.md';
      if (op.premium) {
        const expanded = CapturePathTemplate.expand(op.templates.clipPath, values);
        if (expanded.valid && expanded.path !== 'Inbox.md' && expanded.path !== op.quickPath) { base = expanded.path; }
      }
      op.clipFallbackPath = 'Clippings/' + values.today + ' ' + values.time + ' ' +
        title.replace(/[\\/:*?"<>|\[\]#^\r\n]/g, ' ').replace(/\s+/g, ' ').trim().substring(0, 40) + '.md';
      op.clipPath = base;
      try { op.clipPath = await this.availableClipPath(op, base); }
      catch (e) {
        if (!this.canFallback(e) || base === op.clipFallbackPath) { throw RemoteCaptureEngine.asError(e); }
        op.clipPath = await this.availableClipPath(op, op.clipFallbackPath);
      }
      if (!CapturePathTemplate.validateRelativePath(op.clipPath).valid) { throw new Error('剪藏路径过长或非法'); }
      const m = clip.metadata;
      let head = '---\ntitle: ' + JSON.stringify(title) + '\nsource: ' + JSON.stringify(url);
      if (m.author !== '') { head += '\nauthor: ' + JSON.stringify(m.author); }
      if (m.published !== '') { head += '\npublished: ' + JSON.stringify(m.published); }
      head += '\ncreated: ' + values.today;
      if (m.description !== '') { head += '\ndescription: ' + JSON.stringify(m.description); }
      head += '\ntags:\n  - "clippings"';
      if (m.site !== '') { head += '\nsite: ' + JSON.stringify(m.site); }
      if (m.canonical !== '') { head += '\ncanonical: ' + JSON.stringify(m.canonical); }
      op.clipBody = head + '\n---\n\n# ' + title + '\n\n> 来源：' + url + '\n\n' + clip.body + '\n';
      const d = new Date(op.capturedAt);
      const hh = ('0' + d.getHours()).slice(-2), mm = ('0' + d.getMinutes()).slice(-2);
      op.entry = '- ' + hh + ':' + mm + ' 📄 [[' + op.clipPath.slice(0, -3) + ']]  <' + url + '>';
    } else {
      op.entry = op.kind === 'share' ? QuickCapture.formatEntryAt(op.text, '', op.capturedAt) :
        QuickCapture.formatEntryAt(op.text, '', op.capturedAt, { isTask: op.isTask, addTime: op.addTime });
      if (op.entry === '') { throw new Error('没有可保存的内容'); }
    }
    this.checkpoint(op, 'prepared');
  }
  private async availableClipPath(op: RemoteCaptureOperation, base: string): Promise<string> {
    for (let suffix = 1; suffix <= 50; suffix += 1) {
      const path = suffix === 1 ? base : base.slice(0, -3) + ' (' + suffix.toString() + ').md';
      if (!CapturePathTemplate.validateRelativePath(path).valid) { throw new Error('剪藏路径过长或非法'); }
      if ((await this.read(op, path)).status === 404) { return path; }
    }
    throw new Error('剪藏文件重名过多，请调整存储模板');
  }
  async save(op: RemoteCaptureOperation): Promise<void> {
    if (RemoteCaptureEngine.activeOperations.has(op.id)) { throw new Error('本次捕获正在处理中'); }
    RemoteCaptureEngine.activeOperations.add(op.id);
    try { await this.saveUnlocked(op); } finally { RemoteCaptureEngine.activeOperations.delete(op.id); }
  }
  // Upgrade only an unwritten legacy payload, never remote notes or recovery snapshots.
  private withoutLegacyMarker(value: string, suffix: string): string {
    return value.endsWith(suffix) ? value.substring(0, value.length - suffix.length) : value;
  }
  private async saveUnlocked(op: RemoteCaptureOperation): Promise<void> {
    if (op.stage === 'done' || op.stage === 'undone') { return; }
    if (op.stage.startsWith('undo')) { throw new Error('撤销尚未确认，请继续撤销而非保存'); }
    if (op.stage === 'new') { throw new Error('请先选择远程库'); }
    if (op.clipPath !== '' && op.stage !== 'clipConfirmed' && op.stage !== 'indexWriting' && op.stage !== 'indexUnknown') {
      try {
      const existing = await this.read(op, op.clipPath);
      if (existing.status === 200) {
        if (existing.body !== op.clipBody) { throw new Error('剪藏目标已存在或被修改，拒绝覆盖'); }
        this.checkpoint(op, 'clipConfirmed');
      } else {
        if (op.stage === 'clipWriting' || op.stage === 'clipUnknown') { throw new Error('剪藏写入结果未知且未读到正文，停止自动重试；请核对服务器'); }
        await this.mkdir(op, op.clipPath);
        // A legacy prepared draft may still contain its generated trailing marker.
        // Strip it only after absence is confirmed and before the first write checkpoint.
        op.clipBody = this.withoutLegacyMarker(op.clipBody, '\n' + RemoteCapture.marker(op) + '\n');
        this.checkpoint(op, 'clipWriting');
        let accepted = false;
        try {
          await this.mutate(op, 'writeFile', op.clipPath, op.clipBody);
          accepted = true;
          if ((await this.read(op, op.clipPath)).body !== op.clipBody) { throw new Error('正文回读不一致'); }
          this.checkpoint(op, 'clipConfirmed');
        } catch (e) {
          if (!accepted && this.canFallback(e)) { this.checkpoint(op, 'prepared'); throw RemoteCaptureEngine.asError(e); }
          this.checkpoint(op, 'clipUnknown');
          throw new RemoteCaptureFailure('unknown', '剪藏写入或回读结果未知，请核对服务器');
        }
      }
      } catch (e) {
        const fallback = op.clipFallbackPath ?? '';
        if (!this.canFallback(e) || fallback === '' || op.clipPath === fallback ||
          op.stage === 'clipWriting' || op.stage === 'clipUnknown') { throw RemoteCaptureEngine.asError(e); }
        const old = op.clipPath;
        op.clipPath = await this.availableClipPath(op, fallback);
        op.clipFallbackPath = '';
        op.entry = op.entry.replace('[[' + old.slice(0, -3) + ']]', '[[' + op.clipPath.slice(0, -3) + ']]');
        this.checkpoint(op, 'prepared');
        return this.saveUnlocked(op);
      }
    }
    try {
    const prev = await this.read(op, op.quickPath);
    if (op.stage === 'indexWriting' || op.stage === 'indexUnknown') {
      // Both new marker-free and legacy marked pending records recover by exact after-image.
      // Even an unchanged before-image cannot prove a timed-out request will not land later.
      if (prev.status === 200 && op.after !== '' && prev.body === op.after) {
        this.checkpoint(op, 'done'); return;
      }
      const unchanged = op.existed ? prev.status === 200 && prev.body === op.before : prev.status === 404;
      throw new Error(unchanged ? '索引仍为保存前状态，但写入结果未知；禁止盲目重试，请核对服务器' :
        '索引写入结果未知，内容与保存快照不一致；禁止盲目重试，请人工核对');
    }
    if (prev.status === 200 && prev.body.indexOf(RemoteCapture.marker(op)) >= 0) {
      // Retain conservative recovery for legacy records carrying this operation's marker.
      if (op.after === '' || prev.body !== op.after) { throw new Error('已发现本次旧标记，但内容已变化，请人工核对'); }
      this.checkpoint(op, 'done'); return;
    }
    op.entry = this.withoutLegacyMarker(op.entry, '\n  ' + RemoteCapture.marker(op));
    op.existed = prev.status === 200;
    op.before = op.existed ? prev.body : '';
    const seed = !op.existed && op.quickPath === 'Inbox.md' ? '# Inbox\n\n' : op.before;
    if (op.quickHeading === '') {
      const eol = seed.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
      const separator = seed !== '' && !seed.endsWith('\n') && !seed.endsWith('\r') ? eol : '';
      op.after = seed + separator + op.entry.replace(/\n/g, eol) + eol;
    } else { op.after = CapturePathTemplate.insertUnderHeading(seed, op.entry, op.quickHeading); }
    await this.mkdir(op, op.quickPath);
    const check = await this.read(op, op.quickPath);
    if (check.status !== prev.status || check.body !== prev.body) { throw new Error('目标笔记刚被修改，请再次保存'); }
    this.checkpoint(op, 'indexWriting');
    let accepted = false;
    try {
      if (op.quickHeading === '' && op.existed) {
        await this.mutate(op, 'appendFile', op.quickPath, op.after.substring(op.before.length));
      } else { await this.mutate(op, 'writeFile', op.quickPath, op.after); }
      accepted = true;
      if ((await this.read(op, op.quickPath)).body !== op.after) { throw new Error('保存后回读不一致，请核对服务器'); }
      this.checkpoint(op, 'done');
    } catch (e) {
      if (!accepted && this.canFallback(e)) {
        this.checkpoint(op, op.clipPath !== '' ? 'clipConfirmed' : 'prepared'); throw RemoteCaptureEngine.asError(e);
      }
      this.checkpoint(op, 'indexUnknown');
      throw new RemoteCaptureFailure('unknown', '索引写入或回读结果未知，请核对服务器');
    }
    } catch (e) {
      if (!this.canFallback(e) || op.quickPath === 'Inbox.md' ||
        op.stage === 'indexWriting' || op.stage === 'indexUnknown') { throw RemoteCaptureEngine.asError(e); }
      // Local appendLine fallback deliberately drops the custom heading.
      op.quickPath = 'Inbox.md'; op.quickHeading = ''; op.before = ''; op.after = ''; op.existed = false;
      this.checkpoint(op, op.clipPath !== '' ? 'clipConfirmed' : 'prepared');
      return this.saveUnlocked(op);
    }
  }
  async undo(op: RemoteCaptureOperation): Promise<void> {
    if (RemoteCaptureEngine.activeOperations.has(op.id)) { throw new Error('本次捕获正在处理中'); }
    RemoteCaptureEngine.activeOperations.add(op.id);
    try { await this.undoUnlocked(op); } finally { RemoteCaptureEngine.activeOperations.delete(op.id); }
  }
  private async undoUnlocked(op: RemoteCaptureOperation): Promise<void> {
    if (op.stage === 'undone') { return; }
    if (op.stage !== 'done' && !op.stage.startsWith('undo')) { throw new Error('只可撤销已确认的保存'); }
    if (op.stage !== 'undoClip' && op.stage !== 'undoClipUnknown') {
      const current = await this.read(op, op.quickPath);
      if (op.stage === 'undoIndex' || op.stage === 'undoIndexUnknown') {
        const already = op.existed ? current.status === 200 && current.body === op.before : current.status === 404;
        if (!already) { throw new Error('撤销索引结果未知，请人工核对；不自动重试'); }
      } else {
        if (current.status !== 200 || current.body !== op.after) { throw new Error('笔记已被修改，拒绝撤销以保护其他内容'); }
        this.checkpoint(op, 'undoIndex');
        try {
          if (op.existed) { await this.mutate(op, 'writeFile', op.quickPath, op.before); }
          else { await this.mutate(op, 'unlink', op.quickPath); }
          const verified = await this.read(op, op.quickPath);
          if (op.existed ? verified.status !== 200 || verified.body !== op.before : verified.status !== 404) {
            throw new Error('撤销索引回读不一致');
          }
        } catch (e) { this.checkpoint(op, 'undoIndexUnknown'); throw RemoteCaptureEngine.asError(e); }
      }
      this.checkpoint(op, 'undoClip');
    }
    if (op.clipPath !== '') {
      const clip = await this.read(op, op.clipPath);
      if (clip.status === 200) {
        if (op.stage === 'undoClipUnknown') { throw new Error('删除剪藏结果未知，不自动重试'); }
        if (clip.body !== op.clipBody) { throw new Error('剪藏正文已被修改，保留正文；索引已撤销'); }
        this.checkpoint(op, 'undoClipUnknown');
        await this.mutate(op, 'unlink', op.clipPath);
        if ((await this.read(op, op.clipPath)).status !== 404) { throw new Error('删除正文未确认'); }
      }
    }
    this.checkpoint(op, 'undone');
  }
}
