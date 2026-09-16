import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'QuickCapture';

// T0 快捷捕获共用层（v1.2.0）：分享速记 + 小组件速记共用的 vault 定位与 Inbox 追加
// 设计约束：不依赖 ignis 是否在跑（冷启分享场景 ignis 未启动）→ 一律直写 fs
// VIP 钩子预留：v1 全免费引流，转收费时仅需改 isPremiumFeature 一处
export class QuickCapture {
  // VIP 预留位（v1 恒 false；将来高级功能在此挂门禁）
  static isPremiumFeature(): boolean {
    return false;
  }

  // vault 定位：filesDir/vaults 下字典序第一个子目录（node_embed.cpp 设 VAULT_ROOT，
  // ignis config.refreshVaults 同规则扫描——单库用户 100% 命中；多库用户 v1.1 加选择器）
  // 返回 vault 目录绝对路径；无库返回 ''
  static resolveVault(context: common.UIAbilityContext): string {
    try {
      const root = context.filesDir + '/vaults';
      if (!fs.accessSync(root)) {
        return '';
      }
      const names = fs.listFileSync(root)
        .map((n: string) => n)
        .filter((n: string) => !n.startsWith('.'))
        .sort();
      for (const n of names) {
        const p = root + '/' + n;
        const st = fs.statSync(p);
        if (st.isDirectory()) {
          return p;
        }
      }
      return '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'resolveVault failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  // vault 显示名（路径尾段）
  static vaultName(vaultPath: string): string {
    if (vaultPath === '') {
      return '';
    }
    const i = vaultPath.lastIndexOf('/');
    return i >= 0 ? vaultPath.substring(i + 1) : vaultPath;
  }

  // 追加一条速记到 Inbox.md（不存在则创建）。返回写入的完整行（含时间戳），失败返回 ''
  // 追加格式：- HH:mm 内容（来源可得时附 (来自 xxx)）
  static appendInbox(context: common.UIAbilityContext, text: string, source: string): string {
    const vault = QuickCapture.resolveVault(context);
    if (vault === '') {
      hilog.warn(DOMAIN, TAG, 'no vault found, skip append');
      return '';
    }
    const line = QuickCapture.formatEntry(text, source);
    try {
      const inbox = vault + '/Inbox.md';
      let prev = '';
      if (fs.accessSync(inbox)) {
        prev = fs.readTextSync(inbox);
        // 无结尾换行则补（防两条速记挤在一行）
        if (prev.length > 0 && !prev.endsWith('\n')) {
          prev += '\n';
        }
      } else {
        prev = '# Inbox\n\n';
      }
      const f = fs.openSync(inbox, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, prev + line + '\n');
      fs.closeSync(f);
      hilog.info(DOMAIN, TAG, 'appended to %{public}s', inbox);
      return line;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'appendInbox failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  // 组装条目行：时间戳 + 内容（清洗换行→空格）+ 来源
  static formatEntry(text: string, source: string): string {
    const d = new Date();
    const hh = QuickCapture.pad2(d.getHours());
    const mm = QuickCapture.pad2(d.getMinutes());
    const flat = text.replace(/[\r\n]+/g, ' ').trim();
    const src = source !== '' ? ' (来自 ' + source + ')' : '';
    return '- ' + hh + ':' + mm + ' ' + flat + src;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  // ── 分享 want 解析（P1 探针：字段名不靠猜，全量 dump + 防御性多 key 匹配）──
  // 已知生态里出现过的 key（按优先级）：
  //   ohos.extra.param.key.shareContent / shareContent / contentText / text / plainText
  // 兜底：取第一个非空字符串值。uri 字段（文本分享有时塞 uri）单独考虑。
  // 返回 { text, source }；解析不到返回 { text: '', source: '' }
  static parseShareWant(want: Want): SharePayload {
    const out: SharePayload = { text: '', source: '' };
    try {
      const params = want.parameters as Record<string, Object>;
      // 探针：全量 dump（真机收网后可收敛为 warn 级或裁剪）
      hilog.info(DOMAIN, TAG, 'share want dump: action=%{public}s uri=%{public}s type=%{public}s',
        want.action ?? '', want.uri ?? '', want.type ?? '');
      if (params) {
        const keys = Object.keys(params);
        hilog.info(DOMAIN, TAG, 'want.parameters keys=%{public}s', JSON.stringify(keys));
        for (const k of keys) {
          const v = params[k];
          if (typeof v === 'string') {
            const shown = v.length > 120 ? v.substring(0, 120) + '…' : v;
            hilog.info(DOMAIN, TAG, '  [%{public}s] = %{public}s', k, shown);
          } else {
            hilog.info(DOMAIN, TAG, '  [%{public}s] = (%{public}s)', k, typeof v);
          }
        }
      }
      // 优先 key 名单
      const prefer = ['ohos.extra.param.key.shareContent', 'shareContent', 'contentText',
        'text', 'plainText', 'content', 'ohos.extra.param.key.contentText'];
      if (params) {
        for (const k of prefer) {
          const v = params[k];
          if (typeof v === 'string' && v.trim() !== '') {
            out.text = v.trim();
            break;
          }
        }
      }
      // 兜底：第一个非空 string
      if (out.text === '' && params) {
        for (const k of Object.keys(params)) {
          const v = params[k];
          if (typeof v === 'string' && v.trim() !== '' && k !== 'ability.want.params.uri' &&
            k !== 'ohos.extra.param.key.formIdentity') {
            out.text = v.trim();
            break;
          }
        }
      }
      // uri 直接内容（部分分享路径把文本塞 uri）
      if (out.text === '' && want.uri && want.uri.startsWith('text:') === false &&
        want.uri !== 'undefined') {
        out.text = want.uri;
      }
      // 来源 App（bundleName，拿不到留空）
      out.source = want.bundleName ?? '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parseShareWant failed: %{public}s', JSON.stringify(e));
    }
    return out;
  }
}

export interface SharePayload {
  text: string;
  source: string;
}
