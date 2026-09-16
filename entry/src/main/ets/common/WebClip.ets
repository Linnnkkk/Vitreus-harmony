import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'WebClip';

// 桌面 Chrome UA：公众号文章对非浏览器 UA 会拒绝/降级（2026-09-16 真机链接实测 200）
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
// 正文安全上限：防异常页面把笔记写成几十 MB
const MAX_BODY = 200000;

export interface ClipResult {
  ok: boolean;
  title: string;
  body: string;
  error: string;
}

// 网页正文抓取（分享链接 → 笔记内容，而不是只存一条 URL）
// 算法（先用 Python 原型在真链接上验证过：3.5MB HTML → 972 字正文）：
//   1. 标题：og:title 优先，退回 <title>
//   2. 正文：id="js_content"（公众号）→ <article> → <body> 逐级退回
//   3. div 嵌套配对扫描定位正文区间（不用贪婪正则，避免回溯爆炸）
//   4. 清洗：去 script/style → 块级标签转换行 → 去标签 → 实体解码 → 压空行
export class WebClip {
  // 从分享文本里抠出第一个 http(s) 链接（分享内容可能是"标题+链接"混合）
  static pickUrl(text: string): string {
    const m = text.match(/https?:\/\/[^\s<>"'\u4e00-\u9fa5）)】]+/);
    if (m !== null && m.length > 0) {
      return m[0];
    }
    return '';
  }

  static async fetch(url: string): Promise<ClipResult> {
    const out: ClipResult = { ok: false, title: '', body: '', error: '' };
    const client = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'User-Agent': UA,
          'Accept-Language': 'zh-CN,zh;q=0.9'
        } as Record<string, string>
      };
      const resp = await client.request(url, opts);
      const code = resp.responseCode;
      if (code !== 200) {
        out.error = 'HTTP ' + code;
        return out;
      }
      const html = String(resp.result !== undefined && resp.result !== null ? resp.result : '');
      if (html.length < 200) {
        out.error = 'empty response';
        return out;
      }
      const parsed = WebClip.parse(html);
      out.title = parsed.title;
      out.body = parsed.body;
      out.ok = out.body !== '';
      if (!out.ok) {
        out.error = 'no body found';
      }
      return out;
    } catch (e) {
      out.error = JSON.stringify(e);
      hilog.error(DOMAIN, TAG, 'fetch failed: %{public}s', out.error);
      return out;
    } finally {
      client.destroy();
    }
  }

  private static parse(html: string): ClipResult {
    const out: ClipResult = { ok: false, title: '', body: '', error: '' };
    // 标题
    const og = html.match(/og:title"\s+content="([^"]*)"/);
    if (og !== null && og.length > 1) {
      out.title = WebClip.decode(og[1]).trim();
    }
    if (out.title === '') {
      const t = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
      if (t !== null && t.length > 1) {
        out.title = WebClip.decode(t[1]).trim();
      }
    }
    // 正文区间
    let seg = '';
    const key = 'id="js_content"';
    const idx = html.indexOf(key);
    if (idx > 0) {
      const start = html.lastIndexOf('<div', idx);
      if (start > 0) {
        const end = WebClip.matchDivEnd(html, start);
        if (end > start) {
          seg = html.substring(start, end);
        }
      }
    }
    if (seg === '') {
      const a = html.indexOf('<article');
      if (a > 0) {
        const ae = html.indexOf('</article>', a);
        if (ae > a) {
          seg = html.substring(a, ae);
        }
      }
    }
    if (seg === '') {
      const b = html.indexOf('<body');
      const be = html.indexOf('</body>', b >= 0 ? b : 0);
      if (b >= 0 && be > b) {
        seg = html.substring(b, be);
      }
    }
    out.body = WebClip.toText(seg);
    if (out.body.length > MAX_BODY) {
      out.body = out.body.substring(0, MAX_BODY) + '\n…（正文过长已截断）';
    }
    return out;
  }

  // div 嵌套配对：从 start 处的 '<div' 出发，数 <div / </div> 直到配平
  private static matchDivEnd(src: string, start: number): number {
    let depth = 0;
    let pos = start;
    let guard = 0;
    while (guard < 20000) {
      guard++;
      const nd = src.indexOf('<div', pos);
      const nc = src.indexOf('</div>', pos);
      if (nc < 0) {
        return -1;
      }
      if (nd >= 0 && nd < nc) {
        depth++;
        pos = nd + 4;
      } else {
        depth--;
        pos = nc + 6;
        if (depth <= 0) {
          return pos;
        }
      }
    }
    return -1;
  }

  // HTML 片段 → 纯文本（保留段落换行）
  private static toText(h: string): string {
    let t = h;
    t = t.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ');
    t = t.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ');
    t = t.replace(/<br\s*\/?>/gi, '\n');
    t = t.replace(/<\/(p|div|section|li|h[1-6]|blockquote|tr|td)>/gi, '\n');
    t = t.replace(/<[^>]*>/g, '');
    t = WebClip.decode(t);
    t = t.replace(/\u00a0/g, ' ');
    t = t.replace(/[\u200b\u200c\u200d\ufeff]/g, '');
    const lines: string[] = t.split('\n');
    const keep: string[] = [];
    for (const ln of lines) {
      const s = ln.trim();
      if (s !== '') {
        keep.push(s);
      }
    }
    return keep.join('\n');
  }

  // 实体解码：常见命名实体 + 数字实体（手写扫描，避开 replace 回调的 ArkTS 类型限制）
  private static decode(s: string): string {
    let t = s.replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/&ldquo;/g, '“')
      .replace(/&rdquo;/g, '”')
      .replace(/&hellip;/g, '…')
      .replace(/&mdash;/g, '—')
      .replace(/&amp;/g, '&');
    return WebClip.decodeNumeric(t);
  }

  private static decodeNumeric(s: string): string {
    if (s.indexOf('&#') < 0) {
      return s;
    }
    let out = '';
    let i = 0;
    let guard = 0;
    while (i < s.length && guard < 50000) {
      guard++;
      const a = s.indexOf('&#', i);
      if (a < 0) {
        out += s.substring(i);
        break;
      }
      const semi = s.indexOf(';', a);
      if (semi < 0 || semi - a > 10) {
        out += s.substring(i, a + 2);
        i = a + 2;
        continue;
      }
      const numStr = s.substring(a + 2, semi);
      let code = -1;
      if (numStr.startsWith('x') || numStr.startsWith('X')) {
        code = parseInt(numStr.substring(1), 16);
      } else {
        code = parseInt(numStr, 10);
      }
      out += s.substring(i, a);
      if (!isNaN(code) && code > 0 && code <= 65535) {
        out += String.fromCharCode(code);
      }
      i = semi + 1;
    }
    return out;
  }
}
