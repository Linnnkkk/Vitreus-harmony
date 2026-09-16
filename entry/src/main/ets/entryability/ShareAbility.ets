import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { QuickCapture, SharePayload } from '../common/QuickCapture';

const DOMAIN = 0x0000;
const TAG = 'ShareAbility';

// T0 分享接收 + 速记入口（v1.2.0）
// 两个进入路径：
//   1) 系统分享面板（ohos.want.action.sendData）→ 确认页 pages/ShareCapture
//   2) 桌面小组件 router 事件（params.mode === 'quicknote'）→ 输入页 pages/QuickNote
// 独立于 EntryAbility（各自 singleton）：分享/速记不打扰 Obsidian 主流程，
// ignis 不在跑也完全可用（直写 fs，见 common/QuickCapture）
//
// 分享数据获取：官方契约是 systemShare.getSharedData(want)（异步，返回 SharedData.records），
// 不是读 want.parameters——后者拿不到 Share Kit 的数据（2026-09-16 查官方示例实锤）
export default class ShareAbility extends UIAbility {
  private pendingMode: string = 'share';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 分享冷启动时 EntryAbility 未运行，这里也要注册持久键（读盘恢复 vault 根）
    PersistentStorage.persistProp('vaultRootPath', '');
    this.handleWant('onCreate', want);
  }

  // singleton 热启路径：App 已在跑时再次分享 / 再次点小组件
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant('onNewWant', want);
  }

  private handleWant(where: string, want: Want): void {
    this.pendingMode = this.wantMode(want);
    this.dumpWant(where, want);
    AppStorage.setOrCreate('launchMode', this.pendingMode);
    AppStorage.setOrCreate('launchTick', Date.now());
    if (this.pendingMode === 'share') {
      this.extractShared(where, want);
    }
  }

  // 官方 API 取分享数据：SharedData.records[]，逐条读 utd/content/uri/title
  // 文本类分享 content 即正文；链接类可能只有 uri/title
  private extractShared(where: string, want: Want): void {
    // 取分享数据即刻进行；vault 定位由页面层负责
    // （picker 需要 UIContext，在 Ability.onCreate 阶段调用不可靠）
    this.fetchShareData(where, want);
  }

  private fetchShareData(where: string, want: Want): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        const records: systemShare.SharedRecord[] = data.getRecords();
        const recLines: string[] = [];
        // 按 utd 分类收集：链接类记录（有 uri）优先于纯文本类
        let linkUri = '';
        let linkTitle = '';
        let plainText = '';
        let anyTitle = '';
        records.forEach((rec: systemShare.SharedRecord, i: number) => {
          const c: string = rec.content ?? '';
          const t: string = rec.title ?? '';
          const u: string = rec.uri ?? '';
          recLines.push('#' + i + ' utd=' + (rec.utd ?? '') +
            ' title=' + ShareAbility.cut(t, 40) +
            ' content=' + ShareAbility.cut(c, 50) +
            ' uri=' + ShareAbility.cut(u, 50));
          if (linkUri === '' && u.length > 0) {
            linkUri = u;
            linkTitle = t;
          }
          if (plainText === '' && c.length > 0) {
            plainText = c;
          }
          if (anyTitle === '' && t.length > 0) {
            anyTitle = t;
          }
        });
        // 组装正文：链接类优先（并带上标题，Obsidian 可直接点）；
        // 无链接才退回纯文本内容——避免把 "entry" 这类附属字段当正文
        let text = '';
        if (linkUri !== '') {
          text = (linkTitle !== '' && linkTitle !== linkUri) ? '[' + linkTitle + '](' + linkUri + ')' : linkUri;
        } else if (plainText !== '') {
          text = plainText;
        } else if (anyTitle !== '') {
          text = anyTitle;
        }
        AppStorage.setOrCreate('shareDebug', ShareAbility.buildDebug(where, want, recLines, ''));
        const payload: SharePayload = { text: text, source: '' };
        AppStorage.setOrCreate('sharePayload', payload);
        AppStorage.setOrCreate('shareReady', Date.now());
      })
      .catch((err: BusinessError) => {
        // 兜底：非 Share Kit 发送方（直发 sendData want）时从 parameters 扫
        const fallback: SharePayload = QuickCapture.parseWantFallback(want);
        const why: string = 'code=' + (err.code ?? -1) + ' msg=' + (err.message ?? '');
        AppStorage.setOrCreate('shareDebug', ShareAbility.buildDebug(where, want, [], why));
        AppStorage.setOrCreate('sharePayload', fallback);
        AppStorage.setOrCreate('shareReady', Date.now());
      });
  }

  // 调试面板数据（真机定位用）：getSharedData 成败 + 每条 record 原始字段 + want 全参数
  private static buildDebug(where: string, want: Want, recLines: string[], failed: string): string {
    const out: string[] = [];
    out.push('[' + where + '] action=' + (want.action ?? '') + ' type=' + (want.type ?? ''));
    out.push('bundle=' + (want.bundleName ?? '') + ' uri=' + ShareAbility.cut(want.uri ?? '', 60));
    if (failed !== '') {
      out.push('getSharedData 失败: ' + ShareAbility.cut(failed, 140));
    } else {
      out.push('records=' + recLines.length);
      recLines.forEach((l: string) => out.push(l));
    }
    out.push('--- want.parameters ---');
    try {
      const p = want.parameters as Record<string, Object> | undefined;
      if (p) {
        const keys: string[] = Object.keys(p);
        out.push('keys(' + keys.length + ')');
        keys.forEach((k: string) => {
          const v = p[k];
          if (typeof v === 'string') {
            out.push(k + ' = ' + ShareAbility.cut(v, 70));
          } else {
            out.push(k + ' = (' + typeof v + ')');
          }
        });
      } else {
        out.push('(none)');
      }
    } catch (e) {
      out.push('(param dump error)');
    }
    let s = out.join('\n');
    return ShareAbility.cut(s, 2200);
  }

  private static cut(s: string, n: number): string {
    return s.length > n ? s.substring(0, n) + '…' : s;
  }

  private wantMode(want: Want): string {
    const m = want.parameters?.['mode'];
    if (m === 'quicknote') {
      return 'quicknote';
    }
    return 'share';
  }

  private dumpWant(where: string, want: Want): void {
    hilog.info(DOMAIN, TAG, '%{public}s: action=%{public}s uri=%{public}s bundle=%{public}s',
      where, want.action ?? '', want.uri ?? '', want.bundleName ?? '');
    try {
      const p = want.parameters as Record<string, Object> | undefined;
      if (p) {
        hilog.info(DOMAIN, TAG, '%{public}s params keys: %{public}s', where, JSON.stringify(Object.keys(p)));
      }
    } catch (e) {
      // ignore
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 透明窗口：分享/速记是瞬时叠加操作，只显示一张浮层卡片，
    // 不再像"另一个应用界面"那样铺满全屏
    const mainWindow = windowStage.getMainWindowSync();
    try {
      mainWindow.setWindowBackgroundColor('#00000000');
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'window style failed: %{public}s', JSON.stringify(err));
    }

    const page = this.pendingMode === 'quicknote' ? 'pages/QuickNote' : 'pages/ShareCapture';
    windowStage.loadContent(page, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
