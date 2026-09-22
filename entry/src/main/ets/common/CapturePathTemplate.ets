// 快捷捕获路径模板纯逻辑层：不依赖 Ability、文件系统或 UI。
// 模板是 vault-relative 的 Markdown 文件路径，例如：剪藏/{{年}}/{{标题}}.md。

export interface CapturePathTemplates {
  version: number;
  quickNotePath: string;
  quickNoteHeading: string;
  clipPath: string;
}

export interface CaptureHeadingInfo {
  valid: boolean;
  level: number;
  text: string;
}

export interface CaptureHeadingValidation {
  valid: boolean;
  empty: boolean;
  error: string;
  level: number;
  text: string;
}

export interface CaptureTemplateValues {
  year: string;
  month: string;
  day: string;
  today: string;
  time: string;
  title: string;
  site: string;
  vault: string;
}

export interface CaptureTemplateValidation {
  valid: boolean;
  empty: boolean;
  error: string;
}

export interface CaptureTemplateExpansion {
  valid: boolean;
  path: string;
  error: string;
}

const MAX_TEMPLATE_LENGTH = 500;
const MAX_PATH_LENGTH = 500;
const MAX_COMPONENT_LENGTH = 120;
const MAX_COMPONENTS = 32;
const STATIC_FORBIDDEN = '\\/:*?"<>|[]#^';

export class CapturePathTemplate {
  static emptyTemplates(): CapturePathTemplates {
    return {
      version: 1,
      quickNotePath: '',
      quickNoteHeading: '',
      clipPath: ''
    };
  }

  static parseHeadingLine(line: string): CaptureHeadingInfo {
    const source = line.trim();
    if (source === '') {
      return { valid: false, level: 0, text: '' };
    }
    let level = 0;
    while (level < source.length && source.charAt(level) === '#') {
      level++;
    }
    if (level < 1 || level > 6 || level >= source.length ||
      (source.charAt(level) !== ' ' && source.charAt(level) !== '\t')) {
      return { valid: false, level: 0, text: '' };
    }
    let text = source.substring(level).trim();
    while (text.endsWith('#')) {
      text = text.substring(0, text.length - 1).trim();
    }
    if (text === '') {
      return { valid: false, level: 0, text: '' };
    }
    return { valid: true, level: level, text: text };
  }

  static validateHeading(heading: string): CaptureHeadingValidation {
    const source = heading.trim();
    if (source === '') {
      return { valid: false, empty: true, error: '', level: 0, text: '' };
    }
    if (source.indexOf('\n') >= 0 || source.indexOf('\r') >= 0) {
      return { valid: false, empty: false, error: '标题只能填写一行 Markdown 标题', level: 0, text: '' };
    }
    const parsed = CapturePathTemplate.parseHeadingLine(source);
    if (!parsed.valid) {
      return { valid: false, empty: false, error: '标题必须写成 # 标题（支持 1～6 级）', level: 0, text: '' };
    }
    for (let i = 0; i < parsed.text.length; i++) {
      const code = parsed.text.charCodeAt(i);
      if (code < 32 || code === 127) {
        return { valid: false, empty: false, error: '标题不能包含控制字符', level: 0, text: '' };
      }
    }
    return {
      valid: true,
      empty: false,
      error: '',
      level: parsed.level,
      text: parsed.text
    };
  }

  // 将一条 Markdown 条目写到指定标题的末尾；纯逻辑实现便于单元测试。
  // 只识别 ATX 标题（# 标题），跳过 YAML frontmatter 和围栏代码块。
  // 标题不存在时在文件末尾创建标题，避免内容悄悄回退到另一个文件。
  static insertUnderHeading(content: string, entry: string, heading: string): string {
    const normalized = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    let eol = '\n';
    if (content.indexOf('\r\n') >= 0) {
      eol = '\r\n';
    } else if (content.indexOf('\r') >= 0 && content.indexOf('\n') < 0) {
      eol = '\r';
    }
    const entryNormalized = entry.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    if (entryNormalized === '') {
      return content;
    }
    const checked = CapturePathTemplate.validateHeading(heading);
    if (checked.empty || !checked.valid) {
      let appended = normalized;
      if (appended !== '' && !appended.endsWith('\n')) {
        appended += '\n';
      }
      appended += entryNormalized;
      if (!appended.endsWith('\n')) {
        appended += '\n';
      }
      return appended.replace(/\n/g, eol);
    }

    const lines: string[] = normalized.split('\n');
    const entryLines: string[] = entryNormalized.split('\n');
    let targetIndex = -1;
    let insertAt = lines.length;
    let inFrontmatter = false;
    let inFence = false;
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (i === 0 && trimmed === '---') {
        inFrontmatter = true;
        continue;
      }
      if (inFrontmatter) {
        if (trimmed === '---' || trimmed === '...') {
          inFrontmatter = false;
        }
        continue;
      }
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        continue;
      }
      const parsed = CapturePathTemplate.parseHeadingLine(lines[i]);
      if (!parsed.valid) {
        continue;
      }
      if (targetIndex < 0 && parsed.level === checked.level && parsed.text === checked.text) {
        targetIndex = i;
        continue;
      }
      if (targetIndex >= 0 && parsed.level <= checked.level) {
        insertAt = i;
        break;
      }
    }

    if (targetIndex < 0) {
      const appendedLines: string[] = normalized === '' ? [] : lines.slice();
      while (appendedLines.length > 1 && appendedLines[appendedLines.length - 1] === '' &&
        appendedLines[appendedLines.length - 2] === '') {
        appendedLines.pop();
      }
      if (appendedLines.length > 0 && appendedLines[appendedLines.length - 1].trim() !== '') {
        appendedLines.push('');
      }
      appendedLines.push(heading.trim());
      appendedLines.push('');
      for (const item of entryLines) {
        appendedLines.push(item);
      }
      let appended = appendedLines.join('\n');
      if (!appended.endsWith('\n')) {
        appended += '\n';
      }
      return appended.replace(/\n/g, eol);
    }

    const before: string[] = lines.slice(0, insertAt);
    const after: string[] = lines.slice(insertAt);
    if (before.length > 0 && before[before.length - 1].trim() !== '') {
      before.push('');
    }
    for (const item of entryLines) {
      before.push(item);
    }
    if (after.length > 0 && after[0].trim() !== '') {
      before.push('');
    }
    const merged = before.concat(after);
    let output = merged.join('\n');
    if (!output.endsWith('\n')) {
      output += '\n';
    }
    return output.replace(/\n/g, eol);
  }

  static makeValues(at: number, title: string, site: string, vault: string): CaptureTemplateValues {
    const d = new Date(at);
    const year = '' + d.getFullYear();
    const month = CapturePathTemplate.pad2(d.getMonth() + 1);
    const day = CapturePathTemplate.pad2(d.getDate());
    return {
      year: year,
      month: month,
      day: day,
      today: year + '-' + month + '-' + day,
      time: CapturePathTemplate.pad2(d.getHours()) + CapturePathTemplate.pad2(d.getMinutes()) +
        CapturePathTemplate.pad2(d.getSeconds()),
      title: title,
      site: site,
      vault: vault
    };
  }

  static validateTemplate(template: string): CaptureTemplateValidation {
    const source = template.trim();
    if (source === '') {
      return { valid: false, empty: true, error: '' };
    }
    if (source.length > MAX_TEMPLATE_LENGTH) {
      return { valid: false, empty: false, error: '模板路径过长' };
    }
    if (!source.endsWith('.md')) {
      return { valid: false, empty: false, error: '模板必须以 .md 结尾' };
    }
    if (source.startsWith('/') || source.startsWith('\\')) {
      return { valid: false, empty: false, error: '只允许填写 vault 内的相对路径' };
    }
    if (/^[A-Za-z]:/.test(source) || source.indexOf('://') >= 0) {
      return { valid: false, empty: false, error: '不允许绝对路径或 URI' };
    }

    const components = source.split('/');
    if (components.length > MAX_COMPONENTS) {
      return { valid: false, empty: false, error: '目录层级过深' };
    }
    for (const component of components) {
      if (component === '' || component === '.' || component === '..') {
        return { valid: false, empty: false, error: '路径不能包含空目录、. 或 ..' };
      }
      if (component.startsWith('.') || component !== component.trim()) {
        return { valid: false, empty: false, error: '路径组件不能以 . 开头或带首尾空格' };
      }
      if (component.length > MAX_COMPONENT_LENGTH) {
        return { valid: false, empty: false, error: '路径组件过长' };
      }
      const scan = CapturePathTemplate.scanComponent(component);
      if (!scan.valid) {
        return { valid: false, empty: false, error: scan.error };
      }
    }
    return { valid: true, empty: false, error: '' };
  }

  static expand(template: string, values: CaptureTemplateValues): CaptureTemplateExpansion {
    const checked = CapturePathTemplate.validateTemplate(template);
    if (!checked.valid) {
      return { valid: false, path: '', error: checked.empty ? '模板为空' : checked.error };
    }
    const source = template.trim();
    let out = '';
    let i = 0;
    while (i < source.length) {
      if (source.startsWith('{{', i)) {
        const end = source.indexOf('}}', i + 2);
        if (end < 0) {
          return { valid: false, path: '', error: '存在未闭合变量' };
        }
        const name = source.substring(i + 2, end);
        const raw = CapturePathTemplate.valueFor(name, values);
        const clean = CapturePathTemplate.cleanDynamic(raw);
        if (clean === '') {
          return { valid: false, path: '', error: '变量 ' + name + ' 没有可用值' };
        }
        out += clean;
        i = end + 2;
      } else {
        out += source.charAt(i);
        i++;
      }
    }
    const finalCheck = CapturePathTemplate.validateRelativePath(out);
    if (!finalCheck.valid) {
      return { valid: false, path: '', error: finalCheck.error };
    }
    return { valid: true, path: out, error: '' };
  }

  // 展开后再次逐组件检查，防止动态值制造新的路径组件。
  static validateRelativePath(path: string): CaptureTemplateValidation {
    if (path === '' || path.length > MAX_PATH_LENGTH) {
      return { valid: false, empty: path === '', error: '展开后的路径为空或过长' };
    }
    if (!path.endsWith('.md') || path.startsWith('/') || path.startsWith('\\') ||
      /^[A-Za-z]:/.test(path) || path.indexOf('://') >= 0) {
      return { valid: false, empty: false, error: '展开后的路径不是安全的相对 Markdown 路径' };
    }
    const components = path.split('/');
    if (components.length > MAX_COMPONENTS) {
      return { valid: false, empty: false, error: '展开后的路径层级过深' };
    }
    for (const component of components) {
      if (component === '' || component === '.' || component === '..') {
        return { valid: false, empty: false, error: '展开后的路径包含非法目录组件' };
      }
      if (component.startsWith('.') || component !== component.trim()) {
        return { valid: false, empty: false, error: '展开后的路径组件不能以 . 开头或带首尾空格' };
      }
      if (component.length > MAX_COMPONENT_LENGTH) {
        return { valid: false, empty: false, error: '展开后的路径组件过长' };
      }
      for (let i = 0; i < component.length; i++) {
        const ch = component.charAt(i);
        const code = component.charCodeAt(i);
        if (code < 32 || code === 127 || STATIC_FORBIDDEN.indexOf(ch) >= 0 || ch === '{' || ch === '}') {
          return { valid: false, empty: false, error: '展开后的路径包含非法字符' };
        }
      }
    }
    return { valid: true, empty: false, error: '' };
  }

  static hostFromUrl(url: string): string {
    const scheme = url.indexOf('://');
    if (scheme < 0) {
      return '';
    }
    const start = scheme + 3;
    let end = url.length;
    const marks: string[] = ['/', '?', '#'];
    for (const mark of marks) {
      const at = url.indexOf(mark, start);
      if (at >= 0 && at < end) {
        end = at;
      }
    }
    let host = url.substring(start, end);
    const auth = host.lastIndexOf('@');
    if (auth >= 0) {
      host = host.substring(auth + 1);
    }
    return host;
  }

  private static scanComponent(component: string): CaptureTemplateValidation {
    let i = 0;
    while (i < component.length) {
      const ch = component.charAt(i);
      if (component.startsWith('{{', i)) {
        const end = component.indexOf('}}', i + 2);
        if (end < 0) {
          return { valid: false, empty: false, error: '存在未闭合变量' };
        }
        const name = component.substring(i + 2, end);
        if (!CapturePathTemplate.isVariable(name)) {
          return { valid: false, empty: false, error: '未知变量：' + name };
        }
        i = end + 2;
        continue;
      }
      if (ch === '{' || ch === '}') {
        return { valid: false, empty: false, error: '变量必须写成 {{变量}}' };
      }
      const code = component.charCodeAt(i);
      if (code < 32 || code === 127 || STATIC_FORBIDDEN.indexOf(ch) >= 0) {
        return { valid: false, empty: false, error: '路径包含非法字符' };
      }
      i++;
    }
    return { valid: true, empty: false, error: '' };
  }

  private static isVariable(name: string): boolean {
    switch (name) {
      case '年':
      case '月':
      case '日':
      case '今天':
      case '时间':
      case '标题':
      case '站点':
      case '库名':
        return true;
      default:
        return false;
    }
  }

  private static valueFor(name: string, values: CaptureTemplateValues): string {
    switch (name) {
      case '年':
        return values.year;
      case '月':
        return values.month;
      case '日':
        return values.day;
      case '今天':
        return values.today;
      case '时间':
        return values.time;
      case '标题':
        return values.title;
      case '站点':
        return values.site;
      case '库名':
        return values.vault;
      default:
        return '';
    }
  }

  private static cleanDynamic(value: string): string {
    let out = '';
    let pendingSpace = false;
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      const code = value.charCodeAt(i);
      const forbidden = code < 32 || code === 127 || STATIC_FORBIDDEN.indexOf(ch) >= 0 ||
        ch === '{' || ch === '}';
      if (forbidden || ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
        pendingSpace = out !== '';
        continue;
      }
      if (pendingSpace) {
        out += ' ';
        pendingSpace = false;
      }
      out += ch;
    }
    out = out.trim();
    if (out === '.' || out === '..') {
      out = '';
    }
    if (out.length > MAX_COMPONENT_LENGTH) {
      out = out.substring(0, MAX_COMPONENT_LENGTH);
      const last = out.charCodeAt(out.length - 1);
      if (last >= 55296 && last <= 56319) {
        out = out.substring(0, out.length - 1);
      }
      out = out.trim();
    }
    return out;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }
}
