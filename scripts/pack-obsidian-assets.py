#!/usr/bin/env python3
"""
Vitreus 辅助工具：把用户自己电脑上的 Obsidian 前端资源打包成 obsidian-assets.zip

用途：Vitreus 本地模式（设备内嵌 ignis server）需要 Obsidian 的前端资源。
出于版权考虑，Vitreus 不分发这些文件——由用户从自己的 Obsidian 安装中提取。

用法：
  python3 pack-obsidian-assets.py [Obsidian资源目录]

资源目录的常见位置：
  Windows: C:\\Users\\<你>\\AppData\\Local\\Programs\\Obsidian\\resources\\obsidian.asar 所在目录
           （或已解包的 obsidian.asar.unpacked / 直接解包后的目录，含 index.html 和 package.json）
  macOS:   /Applications/Obsidian.app/Contents/Resources/ （obsidian.asar 在此）
  Linux:   /usr/lib/obsidian/ 或 ~/apps/obsidian/

脚本行为：
  1. 找到 obsidian.asar（如给的是目录）并解包（纯 Python 实现 asar 格式解析）
  2. 校验关键文件（index.html、package.json、app.css）存在
  3. 打包为 obsidian-assets.zip（只含资源文件，不含 electron 原生模块）

产出：obsidian-assets.zip → 放到手机 Vitreus 的导入入口（或 adb 推入沙箱）
"""
import json
import os
import struct
import sys
import zipfile

def die(msg):
    print(f"✗ {msg}")
    sys.exit(1)

def extract_asar(asar_path, out_dir):
    """解包 asar（Electron 归档格式）。Header: 4B size-pickle + pickle(json header)"""
    with open(asar_path, "rb") as f:
        data_size_prefix = struct.unpack("<I", f.read(4))[0]      # = 4 + header_size + padding 相关
        header_size_prefix = struct.unpack("<I", f.read(4))[0]
        header_size = struct.unpack("<I", f.read(4))[0]
        json_len = struct.unpack("<I", f.read(4))[0]
        header_json = f.read(header_size - 4 - 4 - 4)[:json_len].decode("utf-8", "replace")
        base = 16 + json_len
        # 对齐：base 向上取整到 4 的倍数（asar 的 pickle 布局）
        base = (base + 3) & ~3
        header = json.loads(header_json)

    def walk(node, prefix):
        files = node.get("files", {})
        for name, meta in files.items():
            rel = f"{prefix}/{name}" if prefix else name
            if "files" in meta:
                yield from walk(meta, rel)
            elif "offset" in meta:
                yield rel, int(meta["offset"]), int(meta["size"]), meta.get("unpacked", False)

    os.makedirs(out_dir, exist_ok=True)
    with open(asar_path, "rb") as f:
        count = 0
        for rel, off, size, unpacked in walk(header, ""):
            target = os.path.join(out_dir, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if unpacked:
                continue  # unpacked 文件在 .unpacked 目录，通常为原生模块，不搬
            f.seek(base + off)
            payload = f.read(size)
            with open(target, "wb") as out:
                out.write(payload)
            count += 1
    return count

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    src = os.path.abspath(src)

    # 情况1：直接给了 asar 文件
    asar = None
    if src.endswith(".asar") and os.path.isfile(src):
        asar = src
    else:
        # 情况2：目录里找 asar
        cand = os.path.join(src, "obsidian.asar")
        if os.path.isfile(cand):
            asar = cand

    work = "obsidian-assets"
    if asar:
        print(f"→ 解包 {asar}")
        n = extract_asar(asar, work)
        print(f"  {n} 个文件")
    elif os.path.isfile(os.path.join(src, "index.html")):
        # 情况3：已解包目录
        print(f"→ 使用已解包目录 {src}")
        os.makedirs(work, exist_ok=True)
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if d not in (".git",)]
            for fn in files:
                rel = os.path.relpath(os.path.join(root, fn), src)
                dst = os.path.join(work, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(os.path.join(root, fn), "rb") as i, open(dst, "wb") as o:
                    o.write(i.read())
    else:
        die(f"{src} 里没找到 obsidian.asar 或 index.html。请确认路径。")

    # 校验关键文件
    for key in ("index.html", "package.json", "app.css"):
        if not os.path.isfile(os.path.join(work, key)):
            die(f"缺少关键文件 {key}——资源不完整")

    ver = "?"
    try:
        with open(os.path.join(work, "package.json")) as f:
            ver = json.load(f).get("version", "?")
    except Exception:
        pass

    # 打 zip
    out = "obsidian-assets.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(work):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, work))
    size = os.path.getsize(out)
    print(f"✓ obsidian-assets.zip 打包完成（Obsidian {ver}，{size/1024/1024:.1f} MB）")
    print("  → 传到手机后通过 Vitreus 的'导入 Obsidian 资源'入口注入")

if __name__ == "__main__":
    main()
