import { Want } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { QuickCapture, VaultEntry } from '../common/QuickCapture';
import { OpenMarkdown, IncomingFile, OpenRequest } from '../common/OpenMarkdown';
import { RemoteVault } from '../common/RemoteCapture';
import { RemoteCaptureService } from '../common/RemoteCaptureService';
import { GlassCard } from '../components/GlassCard';
import { Theme } from '../common/Theme';
import { hapticLight } from '../common/Haptics';

// 系统「选择打开方式」选了 Vitreus 时的落地页（ShareAbility 宿主，透明浮层）。
// 流程：读文件 → 让用户选库 → 复制/上传到该库根目录 → 交给主界面切库并打开。
// 本地库与远程库（WebDAV / Ignis 服务器）放在同一个列表里。
class VaultTarget {
  key: string = '';
  label: string = '';
  tag: string = '';
  kind: string = 'local';
  vault: string = '';
  path: string = '';
  remote: RemoteVault | undefined = undefined;
}

@Entry
@Component
struct OpenMarkdownPage {
  @State private phase: string = 'loading';
  @State private fileName: string = '';
  @State private targets: VaultTarget[] = [];
  @State private selectedKey: string = '';
  @State private message: string = '';
  @State private warning: string = '';
  @State private emptyText: string = '请先打开 Vitreus 新建一个笔记库，再用它打开文件。';
  @State private hint: string = '正在读取文件…';
  @StorageLink('openIncomingTick') @Watch('onIncoming') private tick: number = 0;
  private consumedTick: number = 0;
  private incoming: IncomingFile | undefined = undefined;
  private runSeq: number = 0;
  private busy: boolean = false;

  aboutToAppear(): void {
    this.onIncoming('');
  }

  onIncoming(propName: string): void {
    if (this.tick === 0 || this.tick === this.consumedTick) { return; }
    this.consumedTick = this.tick;
    this.start(AppStorage.get<string>('openIncomingUri') ?? '');
  }

  private async start(uri: string): Promise<void> {
    const seq = ++this.runSeq;
    this.busy = false;
    this.phase = 'loading';
    this.hint = '正在读取文件…';
    this.message = '';
    this.warning = '';
    this.targets = [];
    this.selectedKey = '';
    this.incoming = undefined;
    try {
      const file = OpenMarkdown.readIncoming(uri);
      if (seq !== this.runSeq) { return; }
      this.incoming = file;
      this.fileName = file.name;
      this.emptyText = '请先打开 Vitreus 新建一个笔记库，再用它打开文件。';
    } catch (e) {
      if (seq === this.runSeq) { this.fail((e as Error).message || '读取文件失败'); }
      return;
    }
    this.hint = '正在读取笔记库…';
    const context = getContext(this) as common.UIAbilityContext;
    const found: VaultTarget[] = [];
    try {
      await QuickCapture.resolveVaultAsync(context);
      const root = QuickCapture.currentRoot(context);
      for (const v of QuickCapture.listVaults(context)) {
        // 主界面只能打开 Vitreus 库根目录下的库
        if (root !== '' && !v.path.startsWith(root + '/')) { continue; }
        const item = new VaultTarget();
        item.key = 'local:' + v.path;
        item.label = v.name;
        item.tag = '本地';
        item.kind = 'local';
        item.vault = v.path.substring(v.path.lastIndexOf('/') + 1);
        item.path = v.path;
        found.push(item);
      }
    } catch (e) {
      // 本地库读取失败不影响远程库；两边都没有时再统一提示
    }
    let remoteError = '';
    // PDF 是二进制文件，远程库的上传接口只收文本，所以目前只能放进本地库。
    const pdfOnlyLocal = this.incoming !== undefined && this.incoming.pdf;
    if (pdfOnlyLocal) { this.hint = '正在读取本地笔记库…'; }
    try {
      for (const v of pdfOnlyLocal ? [] : await RemoteCaptureService.list(context)) {
        const item = new VaultTarget();
        item.key = 'remote:' + v.id;
        item.label = v.name;
        const isDav = v.id.startsWith('webdav:');
        item.tag = isDav ? 'WebDAV' : '服务器';
        item.kind = isDav ? 'webdav' : 'server';
        item.vault = isDav ? '' : v.id;
        item.remote = v;
        found.push(item);
      }
    } catch (e) {
      remoteError = (e as Error).message || '';
    }
    if (seq !== this.runSeq) { return; }
    this.targets = found;
    if (found.length === 0) {
      // 没配置远程库属于正常情况，不当作错误展示
      if (pdfOnlyLocal) { this.emptyText = 'PDF 目前只能放入本地笔记库。请先在 Vitreus 里新建一个本地库，再用它打开 PDF。'; }
      this.phase = 'empty';
      return;
    }
    if (remoteError !== '' && remoteError.indexOf('请先在主页配置') < 0) { this.warning = '远程库暂时读取失败：' + remoteError; }
    if (found.length === 1) { this.selectedKey = found[0].key; }
    this.phase = 'choosing';
  }

  private selected(): VaultTarget | undefined {
    const matches = this.targets.filter((t: VaultTarget) => t.key === this.selectedKey);
    return matches.length === 1 ? matches[0] : undefined;
  }

  private fail(text: string): void {
    this.message = text;
    this.phase = 'failed';
  }

  private async confirm(): Promise<void> {
    const target = this.selected();
    const file = this.incoming;
    if (this.phase !== 'choosing' || this.busy || target === undefined || file === undefined) { return; }
    this.busy = true;
    const seq = this.runSeq;
    this.phase = 'working';
    this.hint = (target.kind === 'local' ? '正在复制到「' : '正在上传到「') + target.label + '」…';
    const context = getContext(this) as common.UIAbilityContext;
    try {
      let name = '';
      if (target.kind === 'local') {
        name = file.pdf ? OpenMarkdown.copyPdfToLocalVault(target.path, file) : OpenMarkdown.saveToLocalVault(target.path, file);
      } else if (target.remote !== undefined) {
        name = await RemoteCaptureService.uploadMarkdown(context, target.remote, file.name, file.bytes);
      }
      if (seq !== this.runSeq) { return; }
      const request: OpenRequest = { kind: target.kind, vault: target.vault, file: name, at: Date.now() };
      this.hint = '正在打开…';
      await this.openInApp(context, request);
    } catch (e) {
      if (seq === this.runSeq) { this.fail((e as Error).message || '保存失败，请重试'); }
    } finally {
      this.busy = false;
    }
  }

  private async openInApp(context: common.UIAbilityContext, request: OpenRequest): Promise<void> {
    const want: Want = {
      bundleName: 'com.vitreus.app',
      abilityName: 'EntryAbility',
      parameters: { openRequest: OpenMarkdown.encodeRequest(request) }
    };
    await context.startAbility(want);
    context.terminateSelf();
  }

  private openMainApp(): void {
    const context = getContext(this) as common.UIAbilityContext;
    const want: Want = { bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' };
    context.startAbility(want).then(() => { context.terminateSelf(); }).catch(() => { context.terminateSelf(); });
  }

  private exit(): void {
    (getContext(this) as common.UIAbilityContext).terminateSelf();
  }

  @Builder
  targetRow(target: VaultTarget) {
    Row({ space: 10 }) {
      Text(this.selectedKey === target.key ? '●' : '○')
        .fontSize(16)
        .fontColor(this.selectedKey === target.key ? Theme.ACCENT : Theme.TEXT_TERTIARY)
      Text(target.label)
        .fontSize(Theme.FS_BODY)
        .fontColor(Theme.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(target.tag)
        .fontSize(Theme.FS_FOOT)
        .fontColor(Theme.TEXT_SECONDARY)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor(Theme.CHIP)
        .borderRadius(8)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.selectedKey === target.key ? Theme.FIELD : '#00000000')
    .borderRadius(12)
    .onClick(() => { hapticLight(); this.selectedKey = target.key; })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          if (this.phase === 'failed' || this.phase === 'empty') { this.exit(); }
        })
      GlassCard({ faded: false }) {
        Column({ space: 14 }) {
          if (this.phase === 'loading' || this.phase === 'working') {
            LoadingProgress().width(40).height(40).color(Theme.ACCENT)
            Text(this.hint).fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
          } else if (this.phase === 'choosing') {
            Column({ space: 12 }) {
              Text('用 Vitreus 打开').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
              Text(this.fileName).fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(this.incoming !== undefined && this.incoming.pdf ? '选择要放入的本地笔记库（复制到该库根目录后打开）' : '选择要放入的笔记库（复制到该库根目录后打开）')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY).width('100%')
              Scroll() {
                Column({ space: 4 }) {
                  ForEach(this.targets, (target: VaultTarget) => { this.targetRow(target); }, (target: VaultTarget) => target.key)
                }
                .width('100%')
              }
              .constraintSize({ maxHeight: 280 })
              .width('100%')
              if (this.warning !== '') {
                Text(this.warning).fontSize(Theme.FS_FOOT).fontColor(Theme.WARN).width('100%')
              }
              Row({ space: 8 }) {
                Button('取消').height(40).backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_SECONDARY)
                  .onClick(() => { this.exit(); })
                Button('复制并打开').layoutWeight(1).height(40).backgroundColor(Theme.ACCENT_DEEP).fontColor(Color.White)
                  .enabled(this.selected() !== undefined)
                  .onClick(() => { hapticLight(); this.confirm(); })
              }.width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          } else if (this.phase === 'empty') {
            Text('还没有笔记库').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
            Text(this.emptyText)
              .fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY).textAlign(TextAlign.Center).width('90%')
            Row({ space: 12 }) {
              Button('打开 Vitreus').height(40).backgroundColor(Theme.ACCENT_DEEP).fontColor(Color.White)
                .onClick(() => { hapticLight(); this.openMainApp(); })
              Button('关闭').height(40).backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => { this.exit(); })
            }
          } else {
            Text('未能打开').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
            Text(this.message).fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center).width('90%')
            Row({ space: 12 }) {
              if (this.targets.length > 0 && this.incoming !== undefined) {
                Button('重新选择').height(40).backgroundColor(Theme.ACCENT_DEEP).fontColor(Color.White)
                  .onClick(() => { hapticLight(); this.phase = 'choosing'; this.message = ''; })
              }
              Button('关闭').height(40).backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => { this.exit(); })
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
