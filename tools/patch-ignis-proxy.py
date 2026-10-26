#!/usr/bin/env python3
"""Patch only the embedded production relay (no external ignis checkout writes).

Usage: python3 tools/patch-ignis-proxy.py [--check] [archive.zip]
After changing the bundle, its ArkTS IGNIS_BUNDLE_VER must be bumped separately.
Upstream build-info is deliberately retained: this is a local bundle patch.
"""
import argparse
import copy
import io
from pathlib import Path
import zipfile

MEMBER = 'apps/ignis-server/server/index.js'
START = '// apps/ignis-server/server/routes/proxy/relay.js\n'
END = '// apps/ignis-server/server/routes/proxy/index.js\n'
MARKER = '    // Vitreus: validate every redirect hop without an extra DNS lookup.\n'
EDITS = [
    ('    var MAX_RESPONSE_BYTES = 50 * 1024 * 1024;',
     '''    var settings2 = require_settings();
    // Vitreus: validate every redirect hop without an extra DNS lookup.
    function assertProxyHostAllowed(targetUrl) {
      if (settings2.get("proxyMode") === "allowlist") {
        const host = targetUrl.hostname;
        if (!settings2.get("proxyAllowlist").includes(host)) {
          const error = httpError(403, `Ignis blocked a connection to ${host}: the host is not in the proxy host allowlist (Settings > Ignis > General > Security).`);
          error.block = { code: "allowlist", host };
          throw error;
        }
      }
    }
    function stripCrossOriginHeaders(headers) {
      const out = {};
      for (const [key, val] of Object.entries(headers)) {
        const lower = key.toLowerCase();
        if (lower === "authorization" || lower === "cookie" || lower === "cookie2" || lower === "proxy-authorization" || lower === "host") {
          continue;
        }
        out[key] = val;
      }
      return out;
    }
    var MAX_RESPONSE_BYTES = 50 * 1024 * 1024;'''),
    ('        const res = await requestOnce(',
     '        assertProxyHostAllowed(current);\n        const res = await requestOnce('),
    ('        const next = new URL(res.headers.location, current);',
     '''        const next = new URL(res.headers.location, current);
        if (next.origin !== current.origin) {
          currentHeaders = stripCrossOriginHeaders(currentHeaders);
        }'''),
]


def patch(source):
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError('Production relay boundaries changed; review before patching')
    start, end = source.index(START), source.index(END)
    section = source[start:end]
    if MARKER in section:
        if any(section.count(new) != 1 for _, new in EDITS):
            raise ValueError('Incomplete/unexpected existing proxy patch')
        return source
    for old, new in EDITS:
        if section.count(old) != 1:
            raise ValueError('Production relay changed; expected unique anchor: ' + old)
        section = section.replace(old, new, 1)
    return source[:start] + section + source[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('archive', nargs='?', type=Path, default=Path(__file__).resolve().parents[1] / 'entry/src/main/resources/rawfile/ignis-server.zip')
    args = parser.parse_args()
    original = args.archive.read_bytes()
    with zipfile.ZipFile(io.BytesIO(original)) as src:
        if src.namelist().count(MEMBER) != 1:
            raise ValueError('Expected exactly one production index.js')
        before = src.read(MEMBER)
        after = patch(before.decode('utf-8')).encode('utf-8')
        if before == after:
            print('PASS: embedded proxy patch present (NOTHING TO DO)')
            return
        if args.check:
            parser.exit(1, 'FAIL: embedded proxy redirect patch missing\n')
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as dst:
            dst.comment = src.comment
            for info in src.infolist():
                dst.writestr(copy.copy(info), after if info.filename == MEMBER else src.read(info))
        updated = output.getvalue()
        with zipfile.ZipFile(io.BytesIO(updated)) as verify:
            assert src.namelist() == verify.namelist()
            assert verify.testzip() is None
            for info in src.infolist():
                if info.filename != MEMBER:
                    assert src.read(info) == verify.read(info.filename), info.filename
        # All validation finishes before replacing the authorized archive file.
        args.archive.write_bytes(updated)
        print('PATCHED: only ' + MEMBER + '; all other members preserved')
        print('ACTION: separately bump NodeTest IGNIS_BUNDLE_VER before deployment')


if __name__ == '__main__':
    main()
