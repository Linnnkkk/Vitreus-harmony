import { Want } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { QuickCapture, SharePayload, VaultEntry, CaptureContext } from '../common/QuickCapture';
import { WebClip, ClipResult } from '../common/WebClip';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';
import { GlassCard } from '../components/GlassCard';
import { Theme } from '../common/Theme';
import { CapturePathTemplate } from '../common/CapturePathTemplate';
import { RemoteVault, RemoteCaptureOperation } from '../common/RemoteCapture';
import { RemoteCaptureService } from '../common/RemoteCaptureService';
import { CaptureModeSettings } from '../common/CaptureModeSettings';

const RECEIVE_TIMEOUT_MS = 4000;
const WORK_TIMEOUT_MS = 30000;
// 真机调试开关：true 时展示原始分享数据 + vault 定位过程，且不自动关闭
// （本次已定位完 entry/库路径问题，关掉恢复"浮层闪一下就走"的体验）
const DEBUG_RAW = false;
// 成功态停留时长：够看清结果，又不至于赖着
const TOAST_MS = 3000;
// 失败态停留时长：够看清原因，然后必须销毁（否则任务卡留在最近任务里）
const FAIL_MS = 8000;

// 分享接收页（ShareAbility 宿主）
// 阶段机：receiving（等分享数据）→ working（定位库/抓正文）→ saved | failed
// 落库规则：
//   有链接 → 抓网页正文存 Clippings/<时间 标题>.md，Inbox 留一行 wikilink
//   无链接 → 纯文本追加 Inbox（原速记行为）
@Entry
@Component
struct ShareCapture {
  @State private phase: string = 'receiving';
  @State private hint: string = '正在接收分享内容，将保存到本地库…';
  @State private payloadText: string = '';
  @State private savedLine: string = '';
  @State private vaultName: string = '';
  @State private clipped: boolean = false;
  @State private noteTitle: string = '';
  @State private savedDestination: string = '';
  @State private degraded: boolean = false;
  @State private degradedHint: string = '';
  @State private leaving: boolean = false;
  @State private countdownW: number = 100;
  @State private failKind: string = 'none';
  @State private clipChars: number = 0;
  @State private domain: string = '';
  @State private step: number = 0;
  @State private canSkipClip: boolean = false;
  @State private undone: boolean = false;
  @State private undoFailed: boolean = false;
  @StorageLink('shareReady') @Watch('onReadyChanged') private readyTick: number = 0;
  @StorageLink('shareDebug') private shareDebug: string = '';
  // 多库：待选列表与当前选中（有多个库时让用户点一下）
  @State private vaultOptions: string[] = [];
  @State private selectedVault: string = '';
  @State private remoteMode: boolean = false;
  @State private remoteVaults: RemoteVault[] = [];
  @State private remoteVaultId: string = '';
  @State private targetLoading: boolean = false;
  @State private targetError: string = '';
  @State private undoing: boolean = false;
  private targetSeq: number = 0;
  private lastRemote: RemoteCaptureOperation | null = null;
  private pendingText: string = '';
  private consumedTick: number = 0;
  private autoCloseTimer: number = -1;
  private receiveTimer: number = -1;
  private workTimer: number = -1;
  private choiceTimer: number = -1;
  private runSeq: number = 0;
  private finished: boolean = false;
  private skipResolver: (() => void) | null = null;
  private lastCapture: CaptureContext | null = null;
  private lastNote: string = '';
  private lastLine: string = '';

  aboutToAppear(): void {
    this.finished = false;
    this.remoteMode = CaptureModeSettings.isRemote(getContext(this) as common.UIAbilityContext);
    // 分享数据迟迟不来 → 给结论，不留用户干等（仅在 still waiting 时触发）
    this.receiveTimer = setTimeout(() => {
      this.markReceivingFailed();
    }, RECEIVE_TIMEOUT_MS);
    this.consume();
  }

  onReadyChanged(propName: string): void {
    this.consume();
  }

  private consume(): void {
    if (this.readyTick === 0 || this.readyTick === this.consumedTick) {
      return;
    }
    this.consumedTick = this.readyTick;
    this.finished = false;
    this.clipped = false;
    this.degraded = false;
    this.degradedHint = '';
    this.noteTitle = '';
    this.savedDestination = '';
    this.undone = false;
    this.undoFailed = false;
    this.lastCapture = null;
    this.lastRemote = null;
    this.lastNote = '';
    this.lastLine = '';
    // 消费即清：页面重建时若 readyTick 还留着旧值，会把上一次分享又存一遍
    // （用户实测"点完成/编辑后又多一条"即此）
    AppStorage.setOrCreate('shareReady', 0);
    const p = AppStorage.get<SharePayload>('sharePayload');
    const t: string = p ? p.text : '';
    if (t === '') {
      this.runSeq++;
      this.finished = true;
      this.clearTimers();
      this.setPhase('failed');
      this.failKind = 'none';
      this.hint = '没有接到可保存的分享内容';
      this.scheduleFailureClose();
      return;
    }
    this.clearTimers();
    this.payloadText = t;
    this.run(t);
  }

  // 先在当前卡片选目标；保存动作不再跳转到二级页面。
  private async run(text: string): Promise<void> {
    this.runSeq++;
    this.pendingText = text;
    const firstUrl = WebClip.pickUrl(text);
    this.domain = firstUrl !== '' ? CapturePathTemplate.hostFromUrl(firstUrl) : '';
    this.setPhase('choosing');
    this.hint = '选择保存目标';
    await this.loadTargets();
  }

  private switchMode(remote: boolean): void {
    if (this.phase !== 'choosing') { return; }
    if (!CaptureModeSettings.save(getContext(this) as common.UIAbilityContext, remote)) {
      this.targetError = '捕获目标保存失败，请重试';
      return;
    }
    this.remoteMode = remote;
    this.loadTargets();
  }

  private async loadTargets(): Promise<void> {
    const seq = ++this.targetSeq;
    const remote = this.remoteMode;
    this.targetLoading = true;
    this.targetError = '';
    this.remoteVaults = [];
    this.remoteVaultId = '';
    this.vaultOptions = [];
    this.selectedVault = '';
    const context = getContext(this) as common.UIAbilityContext;
    try {
      if (remote) {
        const vaults = await RemoteCaptureService.list(context);
        if (seq !== this.targetSeq || !this.remoteMode) { return; }
        this.remoteVaults = vaults;
        this.remoteVaultId = vaults.length === 1 ? vaults[0].id : '';
        if (vaults.length === 0) { this.targetError = '服务器没有可用的笔记库'; }
      } else {
        const vault = await QuickCapture.resolveVaultAsync(context);
        if (seq !== this.targetSeq || this.remoteMode) { return; }
        const all = QuickCapture.listVaults(context);
        this.vaultOptions = all.map((v: VaultEntry) => v.name);
        const selected = all.filter((v: VaultEntry) => v.path === vault);
        this.selectedVault = selected.length > 0 ? selected[0].name : '';
        if (vault === '' || all.length === 0) { this.targetError = '找不到笔记库，请回主界面完成初始化'; }
      }
    } catch (e) {
      if (seq === this.targetSeq) { this.targetError = (e as Error).message || '读取笔记库失败'; }
    } finally {
      if (seq === this.targetSeq) { this.targetLoading = false; }
    }
  }

  private async saveSelected(): Promise<void> {
    if (this.phase !== 'choosing' || this.targetLoading || this.finished) { return; }
    if (!this.remoteMode) {
      if (this.selectedVault !== '') { this.saveTo(this.selectedVault, this.runSeq); }
      return;
    }
    const matches = this.remoteVaults.filter((v: RemoteVault) => v.id === this.remoteVaultId);
    if (matches.length !== 1) { this.targetError = '请先选择远程笔记库'; return; }
    const seq = this.runSeq;
    this.setPhase('working');
    this.hint = '正在保存到远程库…';
    this.vaultName = matches[0].name;
    try {
      const op = await RemoteCaptureService.capture(getContext(this) as common.UIAbilityContext,
        this.pendingText, false, true, 'share', matches[0]);
      if (seq !== this.runSeq || this.finished) { return; }
      this.lastRemote = op;
      this.clipped = op.clipPath !== '';
      this.savedDestination = this.clipped ? op.clipPath : op.quickPath;
      this.succeed(op.entry);
    } catch (e) {
      if (seq === this.runSeq && !this.finished) {
        this.fail((e as Error).message || '远程保存失败，内容已保留，请重试', 'retry');
      }
    }
  }

  // 落盘：抓正文或纯文本
  private async saveTo(vaultName: string, seq: number): Promise<void> {
    if (seq !== this.runSeq || this.finished) {
      return;
    }
    if (this.workTimer !== -1) {
      clearTimeout(this.workTimer);
      this.workTimer = -1;
    }
    this.workTimer = setTimeout(() => {
      if (seq === this.runSeq && !this.finished && this.phase === 'working') {
        this.finished = true;
        this.setPhase('failed');
        this.failKind = 'retry';
        this.hint = '处理超时';
        this.clearTimers();
        this.scheduleFailureClose();
      }
    }, WORK_TIMEOUT_MS);
    const context = getContext(this) as common.UIAbilityContext;
    const text = this.pendingText !== '' ? this.pendingText : this.payloadText;
    const allForSelection: VaultEntry[] = QuickCapture.listVaults(context);
    let remembered = false;
    for (const v of allForSelection) {
      if (v.name === vaultName) {
        QuickCapture.setActiveVaultPath(v.path);
        remembered = true;
        break;
      }
    }
    if (!remembered) {
      QuickCapture.setActiveVault(vaultName);
    }
    this.vaultName = vaultName;
    this.clipped = false;
    this.degraded = false;
    this.degradedHint = '';
    this.noteTitle = '';
    this.setPhase('working');
    this.hint = '正在保存到本地库…';
    this.step = 1;

    const url = WebClip.pickUrl(text);
    const capturedAt = Date.now();
    if (url !== '') {
      this.hint = '正在抓取网页正文…';
      this.step = 1;
      this.canSkipClip = true;
      const skipPromise: Promise<ClipResult> = new Promise<ClipResult>((resolve: (v: ClipResult) => void) => {
        this.skipResolver = () => {
          resolve(WebClip.skipped());
        };
      });
      const clip: ClipResult = await Promise.race([WebClip.fetch(url), skipPromise]);
      this.canSkipClip = false;
      this.skipResolver = null;
      this.step = 2;
      if (seq !== this.runSeq || this.finished) {
        return;
      }
      if (clip.ok && clip.body !== '') {
        const capture = QuickCapture.createClipCaptureContextAt(
          context, clip.title, url, clip.metadata, capturedAt);
        const note = QuickCapture.saveClipWithContext(capture, clip.title, url, clip.body, clip.metadata);
        if (note !== '') {
          const line = QuickCapture.appendClipIndexWithContext(capture, note, url);
          this.lastCapture = capture;
          this.lastNote = note;
          this.lastLine = line;
          this.clipped = true;
          this.clipChars = clip.body.length;
          this.degraded = line === '';
          this.degradedHint = line === '' ? '正文已保存，但索引写入失败，请到上述路径查找笔记' : '';
          this.noteTitle = clip.title !== '' ? clip.title : note;
          this.savedDestination = note;
          this.succeed(line !== '' ? line : note);
          return;
        }
      }
      // 抓取失败：退回只存链接，至少不丢内容，并明确告诉用户降级原因。
      const fallbackCapture = QuickCapture.createQuickCaptureContextAt(context, text, capturedAt);
      const fallbackLine = QuickCapture.appendInboxWithContext(fallbackCapture, text, '');
      if (fallbackLine !== '') {
        this.lastCapture = fallbackCapture;
        this.lastNote = '';
        this.lastLine = fallbackLine;
        this.clipped = false;
        this.degraded = true;
        this.degradedHint = clip.error === 'skipped' ? '已按你的选择只保存链接' : WebClip.humanError(clip.error);
        this.savedDestination = this.captureDestination();
        this.succeed(fallbackLine);
        return;
      }
      this.fail('保存失败', 'retry');
      return;
    }

    const plainCapture = QuickCapture.createQuickCaptureContextAt(context, text, capturedAt);
    const line = QuickCapture.appendInboxWithContext(plainCapture, text, '');
    if (line !== '') {
      this.lastCapture = plainCapture;
      this.lastNote = '';
      this.lastLine = line;
      this.clipped = false;
      this.degraded = false;
      this.degradedHint = '';
      this.noteTitle = '';
      this.savedDestination = this.captureDestination();
      this.succeed(line);
      return;
    }
    this.fail('保存失败', 'retry');
  }

  private succeed(line: string): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.clearTimers();
    this.savedLine = line;
    this.setPhase('saved');
    if (!DEBUG_RAW) {
      this.autoCloseTimer = setTimeout(() => {
        this.autoCloseTimer = -1;
        this.exit();
      }, TOAST_MS);
    }
  }

  private scheduleFailureClose(): void {
    if (!DEBUG_RAW) {
      this.autoCloseTimer = setTimeout(() => {
        this.autoCloseTimer = -1;
        this.exit();
      }, FAIL_MS);
    }
  }

  // 失败也要收摊：removeMissionAfterTerminate 只在 ability 销毁时移除任务卡
  // （官方原文："标识当前UIAbility组件销毁后，是否从任务列表中移除任务"）
  // 失败态此前不自动关闭 → 窗口一直挂着 → 最近任务里那张卡就一直留着
  private fail(reason: string, kind: string): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.clearTimers();
    this.setPhase('failed');
    this.failKind = kind;
    this.hint = reason;
    if (!this.remoteMode) { this.scheduleFailureClose(); }
  }

  private clearTimers(): void {
    if (this.autoCloseTimer !== -1) {
      clearTimeout(this.autoCloseTimer);
      this.autoCloseTimer = -1;
    }
    if (this.receiveTimer !== -1) {
      clearTimeout(this.receiveTimer);
      this.receiveTimer = -1;
    }
    if (this.workTimer !== -1) {
      clearTimeout(this.workTimer);
      this.workTimer = -1;
    }
    if (this.choiceTimer !== -1) {
      clearTimeout(this.choiceTimer);
      this.choiceTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.targetSeq++;
    this.runSeq++;
    this.finished = true;
    this.clearTimers();
  }

  private markReceivingFailed(): void {
    if (this.finished || this.phase !== 'receiving') {
      return;
    }
    this.runSeq++;
    this.finished = true;
    this.setPhase('failed');
    this.failKind = 'none';
    this.hint = '没有接到可保存的分享内容';
    this.clearTimers();
    this.scheduleFailureClose();
  }

  // 离场：先淡出再销毁，避免卡片"啪"地消失
  private exit(): void {
    if (this.leaving) {
      return;
    }
    this.getUIContext().animateTo({ duration: Theme.MS_LEAVE, curve: Curve.EaseIn }, () => {
      this.leaving = true;
    });
    setTimeout(() => {
      const context = getContext(this) as common.UIAbilityContext;
      context.terminateSelf();
    }, Theme.MS_LEAVE + 20);
  }

  // 阶段切换带过渡：内容交叉淡入淡出，卡片高度平滑变化
  private setPhase(p: string): void {
    if (this.phase === p) {
      return;
    }
    this.getUIContext().animateTo({ duration: Theme.MS_SWAP, curve: Curve.FastOutSlowIn }, () => {
      this.phase = p;
    });
  }

  // 失败后重试：用已收到的内容重新跑一遍流水线
  private retry(): void {
    if (this.payloadText === '') {
      return;
    }
    this.clearTimers();
    this.finished = false;
    this.failKind = 'none';
    this.run(this.payloadText);
  }

  // 保留卡片：用户点了卡片就不再自动关闭
  private holdOpen(): void {
    if (this.autoCloseTimer !== -1) {
      clearTimeout(this.autoCloseTimer);
      this.autoCloseTimer = -1;
    }
  }

  // 撤销本次保存：删剪藏笔记 + 摘掉索引行
  private async undo(): Promise<void> {
    if (this.undoing || this.undone) { return; }
    this.holdOpen();
    if (this.lastRemote !== null) {
      this.undoing = true;
      try {
        await RemoteCaptureService.undo(getContext(this) as common.UIAbilityContext, this.lastRemote);
        this.undone = true;
        this.undoFailed = false;
      } catch (e) {
        // 失败时不能把 undone 置 true：入口守卫是 `undoing || undone`，
        // 置了 true 就再也点不动，只能干看着"撤销失败"。
        this.undoFailed = true;
      } finally {
        this.undoing = false;
      }
      return;
    }
    const capture = this.lastCapture;
    if (capture === null || this.undone) {
      return;
    }
    hapticLight();
    const ok = QuickCapture.undoSave(capture, this.lastNote, this.lastLine);
    this.getUIContext().animateTo({ duration: Theme.MS_SWAP, curve: Curve.FastOutSlowIn }, () => {
      // 失败时保持"未撤销"，让用户能再点一次，而不是卡在失败提示上。
      this.undone = ok;
      this.undoFailed = !ok;
    });
    // 只有成功撤销才自动关窗；失败要留在这里让用户重试。
    if (ok) {
      this.autoCloseTimer = setTimeout(() => {
        this.autoCloseTimer = -1;
        this.exit();
      }, 1100);
    }
  }

  private skipClip(): void {
    if (this.skipResolver !== null) {
      hapticLight();
      this.skipResolver();
    }
  }

  // 失败态「去初始化」：真正拉起主应用 EntryAbility
  private openMainApp(): void {
    const context = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.vitreus.app',
      abilityName: 'EntryAbility'
    };
    context.startAbility(want).then(() => {
      context.terminateSelf();
    }).catch(() => {
      context.terminateSelf();
    });
  }

  private captureDestination(): string {
    if (this.savedDestination !== '') {
      return this.savedDestination;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const target = QuickCapture.previewQuickTarget(context, this.payloadText);
    return target === 'Inbox.md' ? 'Inbox.md' : '自定义规则';
  }

  private debugText(): string {
    const parts: string[] = [];
    if (this.shareDebug !== '') {
      parts.push('[分享数据]\n' + this.shareDebug);
    }
    if (QuickCapture.lastVaultDebug !== '') {
      parts.push('[vault 定位]\n' + QuickCapture.lastVaultDebug);
    }
    return parts.join('\n\n');
  }

  @Builder
  stepRow(index: number, label: string) {
    Row({ space: 8 }) {
      Text(this.step > index ? '✓' : (this.step === index ? '●' : '○'))
        .fontSize(12)
        .fontColor(this.step >= index ? Theme.SUCCESS : Theme.TEXT_TERTIARY)
        .width(14)
      Text(label)
        .fontSize(Theme.FS_CAPTION)
        .fontColor(this.step >= index ? Theme.TEXT_PRIMARY : Theme.TEXT_TERTIARY)
    }
    .width('100%')
  }

  private selectedRemoteName(): string {
    const matches = this.remoteVaults.filter((v: RemoteVault) => v.id === this.remoteVaultId);
    return matches.length > 0 ? matches[0].name : '';
  }

  private savedTitle(): string {
    if (this.clipped) {
      return '已剪藏';
    }
    return this.degraded ? '已保存链接' : '已保存';
  }

  private savedSubtitle(): string {
    if (this.clipped && this.noteTitle !== '') {
      return this.noteTitle;
    }
    return this.savedDestination;
  }

  private savedMeta(): string {
    const parts: string[] = [];
    if (this.domain !== '' && this.clipped) {
      parts.push(this.domain);
    }
    if (this.clipped && this.clipChars > 0) {
      parts.push('约 ' + this.clipChars.toString() + ' 字');
    }
    if (this.vaultName !== '') {
      parts.push((this.remoteMode ? '远程库 · ' : '本地库 · ') + this.vaultName);
    }
    return parts.join(' · ');
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        // 同速记页：背景保持通透，只在卡片后面压一点点暗。
        // 同速记页：不铺整屏遮罩，只留可点击的透明区域。
        .backgroundColor('#00000000')
        // 遮罩显式延伸进状态栏/导航条安全区，否则顶/底两条深浅与中间不一致
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          // 处理中不允许点掉（避免把正在保存的内容取消掉）
          if (this.phase === 'saved' || this.phase === 'failed') {
            this.exit();
          }
        })
      GlassCard({ faded: this.leaving }) {
        Column({ space: 14 }) {
          if (this.phase === 'receiving') {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Theme.ACCENT)
            Text(this.hint)
              .fontSize(Theme.FS_CAPTION)
              .fontColor(Theme.TEXT_SECONDARY)
          } else if (this.phase === 'working') {
            Column({ space: 14 }) {
              if (this.domain !== '' && !this.remoteMode) {
                Row({ space: 10 }) {
                  Text('🔗').fontSize(18)
                  Column({ space: 2 }) {
                    Text(this.domain)
                      .fontSize(Theme.FS_BODY)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.payloadText)
                      .fontSize(Theme.FS_FOOT)
                      .fontColor(Theme.TEXT_TERTIARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.FIELD)
                .borderRadius(14)
                Column({ space: 8 }) {
                  this.stepRow(0, '定位本地笔记库')
                  this.stepRow(1, '抓取网页正文')
                  this.stepRow(2, '写入本地笔记库')
                }
                .width('100%')
                .padding({ left: 4, right: 4 })
                if (this.canSkipClip) {
                  Text('只存链接，不抓正文')
                    .fontSize(Theme.FS_CAPTION)
                    .fontColor(Theme.ACCENT)
                    .padding({ top: 6, bottom: 6, left: 12, right: 12 })
                    .onClick(() => {
                      this.skipClip();
                    })
                }
              } else {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(Theme.ACCENT)
                Text(this.hint)
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.TEXT_SECONDARY)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
          } else if (this.phase === 'choosing') {
            Column({ space: 12 }) {
              Text('保存分享内容').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
              Text(this.payloadText).fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
                .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Row({ space: 8 }) {
                Button('本地库').layoutWeight(1).height(36)
                  .backgroundColor(!this.remoteMode ? Theme.ACCENT_DEEP : Theme.CHIP)
                  .fontColor(!this.remoteMode ? Color.White : Theme.TEXT_SECONDARY)
                  .onClick(() => { this.switchMode(false); })
                Button('远程库').layoutWeight(1).height(36)
                  .backgroundColor(this.remoteMode ? Theme.ACCENT_DEEP : Theme.CHIP)
                  .fontColor(this.remoteMode ? Color.White : Theme.TEXT_SECONDARY)
                  .onClick(() => { this.switchMode(true); })
              }.width('100%')
              if (this.remoteMode) {
                Text(RemoteCaptureService.label(getContext(this) as common.UIAbilityContext) || '未配置远程库')
                  .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                  .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              if (this.targetLoading) {
                Text('正在读取笔记库…').fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
              } else {
                if (this.remoteMode && this.remoteVaults.length > 0) {
                  Select(this.remoteVaults.map((v: RemoteVault): SelectOption => ({ value: v.name })))
                    .fontColor(Color.White)
                    .optionFontColor(Color.White)
                    .selectedOptionFontColor(Color.White)
                    .optionBgColor('#30365B')
                    .selectedOptionBgColor('#505B96')
                    .value(this.selectedRemoteName() || '请选择远程笔记库')
                    .onSelect((index: number) => { this.remoteVaultId = this.remoteVaults[index].id; this.targetError = ''; })
                } else if (!this.remoteMode && this.vaultOptions.length > 0) {
                  Select(this.vaultOptions.map((name: string): SelectOption => ({ value: name })))
                    .fontColor(Color.White)
                    .optionFontColor(Color.White)
                    .selectedOptionFontColor(Color.White)
                    .optionBgColor('#30365B')
                    .selectedOptionBgColor('#505B96')
                    .value(this.selectedVault || '请选择本地笔记库')
                    .onSelect((index: number) => { this.selectedVault = this.vaultOptions[index]; this.targetError = ''; })
                }
                if (this.targetError !== '') {
                  Text(this.targetError).fontSize(Theme.FS_FOOT).fontColor(Theme.DANGER).width('100%')
                  Button('重新读取').height(34).onClick(() => { this.loadTargets(); })
                }
              }
              Row({ space: 8 }) {
                Button('取消').height(40).backgroundColor(Theme.CHIP).fontColor(Theme.TEXT_SECONDARY)
                  .onClick(() => { this.exit(); })
                Button('保存').layoutWeight(1).height(40).backgroundColor(Theme.ACCENT_DEEP).fontColor(Color.White)
                  .enabled(!this.targetLoading && (this.remoteMode ? this.remoteVaultId !== '' : this.selectedVault !== ''))
                  .onClick(() => { hapticLight(); this.saveSelected(); })
              }.width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
          } else if (this.phase === 'saved') {
            Column({ space: 10 }) {
              if (this.undone) {
                Text('已撤销')
                  .fontSize(Theme.FS_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY)
                Text('这条内容没有留在笔记库里')
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.TEXT_TERTIARY)
              } else if (this.undoFailed) {
                // 撤销失败：留在成功页并给出可重试的入口，不能只提示失败把人卡住。
                Text('撤销失败')
                  .fontSize(Theme.FS_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.DANGER)
                Text('内容仍保留在笔记库，可以再试一次')
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.TEXT_TERTIARY)
                Text(this.undoing ? '撤销中…' : '重试撤销')
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.ACCENT)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => { this.undo(); })
              } else {
              SuccessCheck({
                onDone: () => {
                  hapticSuccess();
                }
              })
                .width(72)
                .height(72)
              Text(this.savedTitle())
                .fontSize(Theme.FS_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              if (this.savedSubtitle() !== '') {
                Text(this.savedSubtitle())
                  .fontSize(Theme.FS_BODY)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('90%')
              }
              if (this.savedMeta() !== '') {
                Text(this.savedMeta())
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
              }
              if (this.degraded && this.degradedHint !== '') {
                Text(this.degradedHint)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.WARN)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('90%')
              }
                if (this.lastCapture !== null || this.lastRemote !== null) {
                  Text(this.undoing ? '撤销中…' : '撤销')
                    .fontSize(Theme.FS_CAPTION)
                    .fontColor(Theme.ACCENT)
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .onClick(() => {
                      this.undo();
                    })
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            .onClick(() => {
              this.holdOpen();
            })
          } else {
            Column({ space: 14 }) {
              Text('未能保存')
                .fontSize(Theme.FS_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Text(this.hint !== '' ? this.hint : '没接到可保存的内容——请从分享面板重新分享一次')
                .fontSize(Theme.FS_CAPTION)
                .fontColor(Theme.TEXT_SECONDARY)
                .textAlign(TextAlign.Center)
                .width('90%')
                .lineHeight(19)
              if (this.payloadText !== '') {
                Text(this.payloadText)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding(12)
                  .backgroundColor(Theme.FIELD)
                  .borderRadius(12)
                  .width('100%')
              }
              Row({ space: 12 }) {
                if (this.failKind === 'init') {
                  Button('去初始化')
                    .fontSize(14)
                    .height(40)
                    .linearGradient({ angle: 90, colors: [[Theme.ACCENT, 0], [Theme.ACCENT_DEEP, 1]] })
                    .fontColor(Color.White)
                    .borderRadius(14)
                    .padding({ left: 20, right: 20 })
                    .onClick(() => {
                      hapticLight();
                      this.openMainApp();
                    })
                } else if (this.failKind === 'retry') {
                  Button('重试')
                    .fontSize(14)
                    .height(40)
                    .linearGradient({ angle: 90, colors: [[Theme.ACCENT, 0], [Theme.ACCENT_DEEP, 1]] })
                    .fontColor(Color.White)
                    .borderRadius(14)
                    .padding({ left: 24, right: 24 })
                    .onClick(() => {
                      hapticLight();
                      this.retry();
                    })
                }
                Button('关闭')
                  .fontSize(14)
                  .height(40)
                  .backgroundColor(Theme.CHIP)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .borderRadius(14)
                  .padding({ left: 20, right: 20 })
                  .onClick(() => {
                    this.exit();
                  })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
          }

          if (DEBUG_RAW && this.debugText() !== '') {
            Column({ space: 4 }) {
              Text('调试：原始数据（长按可复制）')
                .fontSize(10)
                .fontColor(Theme.TEXT_TERTIARY)
              Text(this.debugText())
                .fontSize(9)
                .fontColor(Theme.TEXT_SECONDARY)
                .textAlign(TextAlign.Start)
                .width('100%')
                .maxLines(60)
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .padding(10)
            .backgroundColor('rgba(0,0,0,0.35)')
            .borderRadius(10)
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
