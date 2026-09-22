import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClipMetadata } from './QuickCapture';

const DOMAIN = 0x0000;
const TAG = 'WebClip';

// 桌面 Chrome UA：公众号文章对非浏览器 UA 会拒绝/降级（2026-09-16 真机链接实测 200）
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
// 正文安全上限：防异常页面把笔记写成几十 MB
const MAX_BODY = 200000;
const MAX_IMAGES = 24;

const EMPTY_METADATA: ClipMetadata = {
  description: '',
  site: '',
  author: '',
  published: '',
  canonical: ''
};

export interface ClipResult {
  ok: boolean;
  title: string;
  body: string;
  error: string;
  metadata: ClipMetadata;
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
    const m = text.match(/https?:\/\/[^\s<>"'\u4e00-\u9fa5）】]+/);
    if (m !== null && m.length > 0) {
      let url = m[0];
      while (url.length > 0 && '.,!?;:，。！？；：、]}'.indexOf(url.charAt(url.length - 1)) >= 0) {
        url = url.substring(0, url.length - 1);
      }
      while (url.endsWith(')') && WebClip.unmatchedClosingParen(url)) {
        url = url.substring(0, url.length - 1);
      }
      return url.replace(/&amp;/g, '&');
    }
    return '';
  }

  private static unmatchedClosingParen(url: string): boolean {
    let open = 0;
    let close = 0;
    for (let i = 0; i < url.length; i++) {
      if (url.charAt(i) === '(') {
        open++;
      } else if (url.charAt(i) === ')') {
        close++;
      }
    }
    return close > open;
  }

  static async fetch(url: string): Promise<ClipResult> {
    const out: ClipResult = {
      ok: false,
      title: '',
      body: '',
      error: '',
      metadata: WebClip.emptyMetadata()
    };
    const client = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'User-Agent': UA,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9'
        } as Record<string, string>
      };
      const resp = await client.request(url, opts);
      const code = resp.responseCode;
      if (code !== 200) {
        out.error = 'HTTP ' + code;
        return out;
      }
      const contentType = WebClip.headerValue(resp.header, 'content-type');
      if (contentType !== '' && contentType.indexOf('text/html') < 0 &&
        contentType.indexOf('application/xhtml+xml') < 0) {
        out.error = '返回内容不是网页（' + contentType + '）';
        return out;
      }
      const html = String(resp.result !== undefined && resp.result !== null ? resp.result : '');
      if (html.length < 200) {
        out.error = 'empty response';
        return out;
      }
      const parsed = WebClip.parse(html, url);
      out.title = parsed.title;
      out.body = parsed.body;
      out.metadata = parsed.metadata;
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

  private static parse(html: string, baseUrl: string): ClipResult {
    const out: ClipResult = {
      ok: false,
      title: '',
      body: '',
      error: '',
      metadata: WebClip.emptyMetadata()
    };
    // 同一次解析只收集一次 meta 标签，避免每个字段重复扫描整份 HTML。
    const metaTags: string[] = html.match(/<meta[^>]*>/gi) ?? [];
    // 标题
    out.title = WebClip.metaContent(html, 'og:title', metaTags);
    if (out.title === '') {
      const t = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
      if (t !== null && t.length > 1) {
        out.title = WebClip.decode(t[1]).trim();
      }
    }
    out.metadata.description = WebClip.metaContent(html, 'og:description', metaTags);
    if (out.metadata.description === '') {
      out.metadata.description = WebClip.metaNameContent(html, 'description', metaTags);
    }
    out.metadata.site = WebClip.metaContent(html, 'og:site_name', metaTags);
    out.metadata.author = WebClip.metaNameContent(html, 'author', metaTags);
    if (out.metadata.author === '') {
      out.metadata.author = WebClip.metaContent(html, 'article:author', metaTags);
    }
    out.metadata.published = WebClip.metaContent(html, 'article:published_time', metaTags);
    if (out.metadata.published === '') {
      out.metadata.published = WebClip.jsonLdValue(html, 'datePublished');
    }
    const canonicalTags = html.match(/<link\b[^>]*>/gi);
    if (canonicalTags !== null) {
      for (const tag of canonicalTags) {
        if (WebClip.attrValue(tag, 'rel').toLowerCase() === 'canonical') {
          out.metadata.canonical = WebClip.attrValue(tag, 'href');
          break;
        }
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
    out.body = WebClip.toText(seg, baseUrl);
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

  // HTML 片段 → Markdown（保留段落换行与远程图片引用）
  private static toText(h: string, baseUrl: string): string {
    let t = h;
    t = t.replace(/<(script|style|noscript|template|svg)[^>]*>[\s\S]*?<\/\1>/gi, ' ');
    t = t.replace(/<\s*(nav|header|footer|aside)\b[^>]*>[\s\S]*?<\/\s*\1\s*>/gi, ' ');
    const imageTags = t.match(/<img\b[^>]*>/gi);
    if (imageTags !== null) {
      let imageCount = 0;
      for (const tag of imageTags) {
        if (imageCount >= MAX_IMAGES) {
          break;
        }
        let image = WebClip.attrValue(tag, 'data-src');
        if (image === '') {
          image = WebClip.attrValue(tag, 'data-original');
        }
        if (image === '') {
          image = WebClip.attrValue(tag, 'src');
        }
        if (image === '' || image.startsWith('data:')) {
          continue;
        }
        image = WebClip.absoluteUrl(image, baseUrl);
        if (image === '') {
          continue;
        }
        const alt = WebClip.attrValue(tag, 'alt');
        const markdown = '![' + alt + '](' + image + ')';
        const safeReplacement = ('\n' + markdown + '\n').replace(/\$/g, '$$$$');
        t = t.replace(tag, safeReplacement);
        imageCount++;
      }
    }
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

  private static emptyMetadata(): ClipMetadata {
    const out: ClipMetadata = {
      description: EMPTY_METADATA.description,
      site: EMPTY_METADATA.site,
      author: EMPTY_METADATA.author,
      published: EMPTY_METADATA.published,
      canonical: EMPTY_METADATA.canonical
    };
    return out;
  }

  private static headerValue(headers: Object | undefined, name: string): string {
    if (headers === undefined) {
      return '';
    }
    try {
      const record = headers as Record<string, string>;
      const keys = Object.keys(record);
      for (const key of keys) {
        if (key.toLowerCase() === name) {
          return record[key] ?? '';
        }
      }
    } catch (e) {
      return '';
    }
    return '';
  }

  private static attrValue(tag: string, name: string): string {
    const source = tag.toLowerCase();
    const wanted = name.toLowerCase();
    let from = 0;
    while (from < source.length) {
      const at = source.indexOf(wanted, from);
      if (at < 0) {
        return '';
      }
      const before = at > 0 ? source.charAt(at - 1) : '';
      const after = at + wanted.length < source.length ? source.charAt(at + wanted.length) : '';
      if ((before === '' || before === ' ' || before === '\t' || before === '\n' || before === '<') &&
        (after === ' ' || after === '\t' || after === '\n' || after === '=')) {
        let pos = at + wanted.length;
        while (pos < source.length && (source.charAt(pos) === ' ' || source.charAt(pos) === '\t' ||
          source.charAt(pos) === '\n' || source.charAt(pos) === '\r')) {
          pos++;
        }
        if (source.charAt(pos) !== '=') {
          from = at + wanted.length;
          continue;
        }
        pos++;
        while (pos < source.length && (source.charAt(pos) === ' ' || source.charAt(pos) === '\t' ||
          source.charAt(pos) === '\n' || source.charAt(pos) === '\r')) {
          pos++;
        }
        const quote = source.charAt(pos);
        if (quote === '"' || quote === "'") {
          const end = source.indexOf(quote, pos + 1);
          if (end < 0) {
            return '';
          }
          return WebClip.decode(tag.substring(pos + 1, end)).trim();
        }
        let end = pos;
        while (end < source.length && source.charAt(end) !== ' ' && source.charAt(end) !== '\t' &&
          source.charAt(end) !== '\n' && source.charAt(end) !== '\r' && source.charAt(end) !== '>') {
          end++;
        }
        return WebClip.decode(tag.substring(pos, end)).trim();
      }
      from = at + wanted.length;
    }
    return '';
  }

  private static metaContent(html: string, property: string, tags?: string[]): string {
    const metaTags: string[] = tags ?? (html.match(/<meta[^>]*>/gi) ?? []);
    for (const tag of metaTags) {
      const prop = WebClip.attrValue(tag, 'property');
      const name = WebClip.attrValue(tag, 'name');
      if (prop.toLowerCase() === property.toLowerCase() || name.toLowerCase() === property.toLowerCase()) {
        return WebClip.attrValue(tag, 'content');
      }
    }
    return '';
  }

  private static metaNameContent(html: string, name: string, tags: string[]): string {
    return WebClip.metaContent(html, name, tags);
  }

  private static jsonLdValue(html: string, name: string): string {
    const re = new RegExp('"' + name + '"\\s*:\\s*"([^"]+)"', 'i');
    const m = html.match(re);
    return m !== null && m.length > 1 ? m[1].trim() : '';
  }

  static humanError(error: string): string {
    if (error === '') {
      return '网页正文不可用';
    }
    if (error.indexOf('HTTP ') === 0) {
      return '网页返回错误（' + error + '）';
    }
    if (error.indexOf('不是网页') >= 0) {
      return error;
    }
    if (error.indexOf('timeout') >= 0 || error.indexOf('Timeout') >= 0) {
      return '网页响应超时';
    }
    if (error.indexOf('no body') >= 0) {
      return '没有识别到可读正文';
    }
    return '网页抓取失败，已保留链接';
  }

  private static absoluteUrl(value: string, baseUrl: string): string {
    if (value.startsWith('#') || value.startsWith('mailto:')) {
      return '';
    }
    if (value.startsWith('//')) {
      return baseUrl.startsWith('https://') ? 'https:' + value : 'http:' + value;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    const schemeEnd = baseUrl.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    const scheme = baseUrl.substring(0, schemeEnd);
    const hostStart = schemeEnd + 3;
    const slash = baseUrl.indexOf('/', hostStart);
    const origin = slash >= 0 ? baseUrl.substring(0, slash) : baseUrl;
    if (value.startsWith('/')) {
      return origin + value;
    }
    const basePath = slash >= 0 ? baseUrl.substring(slash) : '/';
    const lastSlash = basePath.lastIndexOf('/');
    const directory = lastSlash >= 0 ? basePath.substring(0, lastSlash + 1) : '/';
    const host = slash >= 0 ? baseUrl.substring(hostStart, slash) : baseUrl.substring(hostStart);
    return scheme + '://' + host + directory + value;
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
    let replacements = 0;
    while (i < s.length) {
      replacements++;
      if (replacements > 200000) {
        out += s.substring(i);
        break;
      }
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
      if (!isNaN(code) && code > 0 && code <= 1114111) {
        if (code <= 65535) {
          out += String.fromCharCode(code);
        } else {
          const adjusted = code - 65536;
          const high = 55296 + Math.floor(adjusted / 1024);
          const low = 56320 + (adjusted % 1024);
          out += String.fromCharCode(high) + String.fromCharCode(low);
        }
      }
      i = semi + 1;
    }
    return out;
  }
}
