// asar 归档解包（Electron Archive 格式）—— ArkTS 实现
// 格式：[4B data_size][4B header_size_prefix][4B header_size][4B json_len][JSON 目录][对齐][文件数据]
// 移植自 scripts/pack-obsidian-assets.py 的解析逻辑
import { fileIo as fs } from '@kit.CoreFileKit';

// asar JSON 目录节点：{ files: { 名字: 节点 } } 或 { offset, size, unpacked }
// （ArkTS 严格模式不让随意 object 索引，用 Record 显式声明）
type AsarNode = Record<string, Object | undefined>;

class AsarEntry {
  offset: number = 0;   // 相对数据段起点
  size: number = 0;
  unpacked: boolean = false;
}

export class AsarExtractor {
  private dataView: DataView;
  private basePath: number;   // JSON 目录里文件数据的起始偏移

  private constructor(dv: DataView, basePath: number) {
    this.dataView = dv;
    this.basePath = basePath;
  }

  static open(buf: ArrayBuffer): AsarExtractor {
    const dv = new DataView(buf);
    // pickle header：4B data_size（不用），随后 4B header_size_prefix，4B header_size，4B json_len
    let basePath = 16 + dv.getUint32(12, true);
    basePath = (basePath + 3) & ~3; // 4 字节对齐
    return new AsarExtractor(dv, basePath);
  }

  // 解析 JSON 目录，收集 相对路径 → 条目
  private walk(node: AsarNode, prefix: string, out: Map<string, AsarEntry>): void {
    const files = node['files'] as AsarNode | undefined;
    if (files === undefined) {
      return;
    }
    const keys = Object.keys(files);
    for (let i = 0; i < keys.length; i++) {
      const name = keys[i];
      const meta = files[name] as AsarNode;
      const rel = prefix === '' ? name : prefix + '/' + name;
      if (meta['files'] !== undefined) {
        this.walk(meta, rel, out);
      } else if (meta['offset'] !== undefined) {
        const e = new AsarEntry();
        e.offset = Number(meta['offset']);
        e.size = Number(meta['size']);
        e.unpacked = meta['unpacked'] === true;
        out.set(rel, e);
      }
    }
  }

  // 解包到目标目录。返回解出的文件数（unpacked 的原生模块不搬）
  extractTo(targetDir: string): number {
    const jsonLen = this.dataView.getUint32(12, true);
    const headerJson = this.decodeUtf8(16, jsonLen);
    const header = JSON.parse(headerJson) as AsarNode;

    const entries = new Map<string, AsarEntry>();
    this.walk(header, '', entries);

    let count = 0;
    const keys = entries.keys();
    for (const rel of keys) {
      const e = entries.get(rel);
      if (e === undefined || e.unpacked) {
        continue;
      }
      const target = targetDir + '/' + rel;
      // 建父目录（逐级）
      const parts = rel.split('/');
      let cur = targetDir;
      for (let d = 0; d < parts.length - 1; d++) {
        cur = cur + '/' + parts[d];
        if (!fs.accessSync(cur)) {
          fs.mkdirSync(cur);
        }
      }
      // 写文件（切片 ArrayBuffer）
      const start = this.basePath + e.offset;
      const slice = this.dataView.buffer.slice(start, start + e.size);
      const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, slice);
      fs.closeSync(file);
      count++;
    }
    return count;
  }

  // 简易 UTF-8 解码（header JSON 段）
  private decodeUtf8(offset: number, len: number): string {
    const bytes = new Uint8Array(this.dataView.buffer, offset, len);
    let out = '';
    let i = 0;
    while (i < len) {
      const b = bytes[i];
      if (b < 0x80) {
        out += String.fromCharCode(b);
        i += 1;
      } else if (b < 0xE0) {
        out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else if (b < 0xF0) {
        out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
        i += 3;
      } else {
        // 4 字节 → 代理对
        const cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
        const v = cp - 0x10000;
        out += String.fromCharCode(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
        i += 4;
      }
    }
    return out;
  }
}
