import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 「用 Vitreus 打开」Markdown：系统「选择打开方式」把 .md 交给 ShareAbility，
// 用户选库后把文件复制/上传到该库根目录，再切到该库并打开这篇笔记。
// 本文件只放与界面无关的部分：读取传入文件、重名处理、本地落盘、打开请求的编码与投递脚本。

// 一篇 Markdown 通常很小；上限只为挡住误选的超大文件把应用撑住。
export const MAX_MARKDOWN_BYTES = 10 * 1024 * 1024;
const READ_CHUNK = 64 * 1024;
// 同名不同内容时最多尝试的编号数量
export const MAX_NAME_TRIES = 50;
// 打开请求超过这个时间没被消费就作废，避免日后无关启动时误跳转
export const OPEN_REQUEST_TTL_MS = 2 * 60 * 1000;

export interface IncomingFile {
  name: string;
  bytes: Uint8Array;
}

// kind: 'local' 本地库（vault=库目录名）| 'webdav' WebDAV 远程库（挂载 id 由启动流程解析）|
// 'server' Ignis 服务器上的库（vault=服务器上的库 id）
export interface OpenRequest {
  kind: string;
  vault: string;
  file: string;
  at: number;
}

export class OpenMarkdown {
  static readonly ACTION_VIEW: string = 'ohos.want.action.viewData';
  static readonly PARAM: string = 'openRequest';

  // 取文件名：URI 的最后一段（百分号解码）；剔除各系统禁用的文件名字符，不是 .md/.markdown 的补 .md。
  static fileNameFromUri(uri: string): string {
    const clean = uri.split('?')[0].split('#')[0];
    const last = clean.substring(clean.lastIndexOf('/') + 1);
    let decoded = last;
    try { decoded = decodeURIComponent(last); } catch (e) { decoded = last; }
    return OpenMarkdown.sanitizeName(decoded);
  }

  static sanitizeName(raw: string): string {
    let name = raw.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').replace(/^\.+/, '').trim();
    if (name === '') { name = '未命名.md'; }
    const lower = name.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) { name = name + '.md'; }
    // 文件名过长时保留扩展名
    if (name.length > 120) {
      const dot = name.lastIndexOf('.');
      name = name.substring(0, 120 - (name.length - dot)) + name.substring(dot);
    }
    return name;
  }

  // 第 n 次尝试用的名字：1 → 原名，2 → 「名字 (2).md」
  static candidateName(name: string, attempt: number): string {
    if (attempt <= 1) { return name; }
    const dot = name.lastIndexOf('.');
    return name.substring(0, dot) + ' (' + attempt.toString() + ')' + name.substring(dot);
  }

  static readBytes(source: string, limit: number = MAX_MARKDOWN_BYTES): Uint8Array {
    const file = fs.openSync(source, fs.OpenMode.READ_ONLY);
    try {
      const chunks: Uint8Array[] = [];
      let total = 0;
      for (;;) {
        const buffer = new ArrayBuffer(READ_CHUNK);
        const n = fs.readSync(file.fd, buffer, { offset: total, length: READ_CHUNK });
        if (n <= 0) { break; }
        total += n;
        if (total > limit) { throw new Error('文件过大（超过 10 MB），不像是笔记'); }
        chunks.push(new Uint8Array(buffer, 0, n));
      }
      const out = new Uint8Array(total);
      let at = 0;
      for (const chunk of chunks) { out.set(chunk, at); at += chunk.length; }
      return out;
    } finally {
      fs.closeSync(file);
    }
  }

  static readIncoming(uri: string): IncomingFile {
    if (uri === '') { throw new Error('没有收到要打开的文件'); }
    const incoming: IncomingFile = { name: OpenMarkdown.fileNameFromUri(uri), bytes: OpenMarkdown.readBytes(uri) };
    return incoming;
  }

  static sameBytes(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) { return false; }
    for (let i = 0; i < a.length; i++) { if (a[i] !== b[i]) { return false; } }
    return true;
  }

  static decodeText(bytes: Uint8Array): string {
    // 上传到远程库按 UTF-8 文本发送；不是合法 UTF-8 就如实报错，不乱码上传。
    try {
      return new util.TextDecoder('utf-8', { fatal: true }).decodeToString(bytes);
    } catch (e) {
      throw new Error('文件不是 UTF-8 文本，无法上传到远程库');
    }
  }

  // 写入本地库根目录。同名且内容相同直接复用已有文件；同名不同内容改名，绝不覆盖。
  static saveToLocalVault(vaultPath: string, incoming: IncomingFile): string {
    for (let attempt = 1; attempt <= MAX_NAME_TRIES; attempt++) {
      const name = OpenMarkdown.candidateName(incoming.name, attempt);
      const target = vaultPath + '/' + name;
      if (fs.accessSync(target)) {
        let existing: Uint8Array | undefined = undefined;
        try { existing = OpenMarkdown.readBytes(target); } catch (e) { existing = undefined; }
        if (existing !== undefined && OpenMarkdown.sameBytes(existing, incoming.bytes)) { return name; }
        continue;
      }
      const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      let written = false;
      try {
        fs.writeSync(file.fd, incoming.bytes.buffer.slice(incoming.bytes.byteOffset,
          incoming.bytes.byteOffset + incoming.bytes.length));
        written = true;
      } finally {
        fs.closeSync(file);
        // 写到一半失败不留残缺文件，下次重试从头来
        if (!written) { try { fs.unlinkSync(target); } catch (e) { /* 已不存在 */ } }
      }
      const check = OpenMarkdown.readBytes(target);
      if (!OpenMarkdown.sameBytes(check, incoming.bytes)) {
        try { fs.unlinkSync(target); } catch (e) { /* 忽略 */ }
        throw new Error('写入后校验失败，请重试');
      }
      return name;
    }
    throw new Error('同名文件太多，请先整理库根目录');
  }

  static encodeRequest(request: OpenRequest): string {
    return JSON.stringify(request);
  }

  // 解析并校验：格式不对、过期、字段缺失都当作没有请求。
  static parseRequest(raw: Object | string | undefined, now: number = Date.now()): OpenRequest | undefined {
    if (raw === undefined || raw === '') { return undefined; }
    let data: Record<string, Object>;
    try {
      data = (typeof raw === 'string' ? JSON.parse(raw) : raw) as Record<string, Object>;
    } catch (e) {
      return undefined;
    }
    const kind = data['kind'];
    const vault = data['vault'];
    const file = data['file'];
    const at = data['at'];
    if (kind !== 'local' && kind !== 'webdav' && kind !== 'server') { return undefined; }
    if (typeof vault !== 'string' || typeof file !== 'string' || typeof at !== 'number') { return undefined; }
    if (file === '' || (kind !== 'webdav' && vault === '')) { return undefined; }
    if (now - at > OPEN_REQUEST_TTL_MS || at - now > OPEN_REQUEST_TTL_MS) { return undefined; }
    const request: OpenRequest = { kind: kind as string, vault: vault as string, file: file as string, at: at as number };
    return request;
  }

  // 等 Obsidian 布局就绪后让它打开这篇笔记（与 ObsidianUri 的投递同一机制，不带 vault 参数＝当前库）。
  static openScript(file: string): string {
    const arg: string = JSON.stringify(file);
    return "(function(f){var n=0;(function go(){n++;" +
      "var ready=typeof window.OBS_ACT==='function'&&window.app&&window.app.workspace&&window.app.workspace.layoutReady;" +
      "if(ready){try{window.OBS_ACT({action:'open',file:f});}catch(e){console.log('[vt] open-file fail '+e);}return;}" +
      "if(n<200){setTimeout(go,300);}else{console.log('[vt] open-file timeout');}})();})(" + arg + ");";
  }
}
