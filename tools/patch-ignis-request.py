#!/usr/bin/env python3
"""Request body shim patch. Default: read-only READY; --apply requires approval.
Always read the current repository ZIP; never use a captured/rebuilt server bundle.
"""
import argparse
import hashlib
import io
import os
from pathlib import Path
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'entry/src/main/resources/rawfile/ignis-server.zip'
MEMBER = 'packages/shim/dist/shim-loader.js'
OLD = '''      let body = null;
      if ((init == null ? void 0 : init.body) && method !== "GET" && method !== "HEAD") {
        if (typeof init.body === "string") {
          body = init.body;
        } else if (init.body instanceof ArrayBuffer || init.body instanceof Uint8Array) {
          body = init.body;
        } else if (typeof init.body === "object") {
          body = JSON.stringify(init.body);
        } else {
          body = String(init.body);
        }
      }
'''
NEW = '''      let body = null;
      // Vitreus Request body v1: clone preserves the caller's stream; failures must reject.
      if (method !== "GET" && method !== "HEAD") {
        if ((init == null ? void 0 : init.body) != null) {
          if (typeof init.body === "string") {
            body = init.body;
          } else if (init.body instanceof ArrayBuffer || init.body instanceof Uint8Array) {
            body = init.body;
          } else if (typeof init.body === "object") {
            body = JSON.stringify(init.body);
          } else {
            body = String(init.body);
          }
        } else if (input instanceof Request && input.body !== null) {
          body = await input.clone().arrayBuffer();
        }
      }
'''
START = '  // packages/shim/src/globals/fetch.js\n'
END = '  // packages/shim/src/globals/window.js\n'


def patch_shim(data):
    source = data.decode('utf-8')
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError('fetch section anchors changed or duplicated')
    start, end = source.index(START), source.index(END)
    if start >= end:
        raise ValueError('fetch section anchors reordered')
    section = source[start:end]
    old_count, new_count = source.count(OLD), source.count(NEW)
    if old_count == 0 and new_count == 1 and NEW in section:
        return data, False
    if old_count != 1 or new_count != 0 or OLD not in section:
        raise ValueError('body patch anchor changed, partial, or ambiguous')
    return source.replace(OLD, NEW, 1).encode('utf-8'), True


def prepare(raw):
    """Build in memory, verifying all non-shim contents and ZIP metadata survive."""
    with zipfile.ZipFile(io.BytesIO(raw)) as before:
        infos = before.infolist()
        names = [info.filename for info in infos]
        if len(set(names)) != len(names) or names.count(MEMBER) != 1:
            raise ValueError('duplicate ZIP members or missing exact shim member')
        shim, changed = patch_shim(before.read(MEMBER))
        if not changed:
            return raw, shim, False
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w') as after:
            after.comment = before.comment
            for info in infos:
                after.writestr(info, shim if info.filename == MEMBER else before.read(info.filename))
        result = out.getvalue()
    with zipfile.ZipFile(io.BytesIO(raw)) as before, zipfile.ZipFile(io.BytesIO(result)) as after:
        if before.namelist() != after.namelist() or before.comment != after.comment:
            raise ValueError('ZIP member order or comment changed')
        for name in before.namelist():
            expected = shim if name == MEMBER else before.read(name)
            if after.read(name) != expected:
                raise ValueError('ZIP verification failed: ' + name)
    return result, shim, True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--apply', action='store_true', help='explicitly replace the repository ZIP atomically')
    modes.add_argument('--stdout-shim', action='store_true', help='print patched production shim without writing ZIP')
    args = parser.parse_args()
    raw = ARCHIVE.read_bytes()
    result, shim, changed = prepare(raw)
    if args.stdout_shim:
        sys.stdout.buffer.write(shim)
        return
    digest = hashlib.sha256(raw).hexdigest()
    if not args.apply:
        print(('READY (not applied)' if changed else 'ALREADY PATCHED') + ' sha256=' + digest)
        return
    if not changed:
        print('ALREADY PATCHED; unchanged')
        return
    # Use latest bytes from this invocation, retaining concurrent relay changes.
    # Refuse replacement if another process changes the ZIP while preparing it.
    fd, temporary = tempfile.mkstemp(prefix='.ignis-request-', suffix='.zip', dir=ARCHIVE.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(result)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, ARCHIVE.stat().st_mode & 0o777)
        if ARCHIVE.read_bytes() != raw:
            raise ValueError('ZIP changed concurrently; refusing stale replacement; retry after writers finish')
        os.replace(temporary, ARCHIVE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('APPLIED shim-only Request body patch; previous sha256=' + digest)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, zipfile.BadZipFile, UnicodeError) as exc:
        sys.exit('FAIL-CLOSED: ' + str(exc))
