import common from '@ohos.app.ability.common';
import { QuickCapture, QuickCaptureFormattingOptions, VaultEntry } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';
import { GlassCard } from '../components/GlassCard';
import { Theme } from '../common/Theme';
import { fileIo as fs } from '@kit.CoreFileKit';
import { RemoteVault } from '../common/RemoteCapture';
import { RemoteCaptureService } from '../common/RemoteCaptureService';

interface QuickNoteDraft {
  version: number;
  text: string;
  isTask: boolean;
  addTime: boolean;
}

// 速记输入页（ShareAbility 宿主）：桌面小组件直达
// 输入 → 保存追加 Inbox.md → 对勾动效 1.2s 自动退出；多库时可点选目标库
@Entry
@Component
struct QuickNote {
  @State private text: string = '';
  @State private isTask: boolean = false;
  @State private addTime: boolean = true;
  @State private vaultName: string = '';
  @State private vaultOptions: string[] = [];
  @State private saved: boolean = false;
  @State private saveFailed: boolean = false;
  @State private saving: boolean = false;
  @State private emptyHint: boolean = false;
  @State private leaving: boolean = false;
  @State private scrimOn: boolean = false;
  @State private showVaults: boolean = false;
  @State private restored: boolean = false;
  private closeTimer: number = -1;
  @State private choosingVault: boolean = false;
  @State private destination: string = 'Inbox.md';
  @State private remoteMode: boolean = false;
  @State private remoteVaults: RemoteVault[] = [];
  @State private remoteVaultId: string = '';
  @State private remoteLoading: boolean = false;
  @State private remoteError: string = '';
  @State private saveError: string = '';
  private remoteSeq: number = 0;
  private abandoning: boolean = false;
  private destinationRefreshTimer: number = -1;
  // 页面会话内复用同一份 vault 列表，避免预览/保存重复扫描文件系统。
  private vaultEntries: VaultEntry[] = [];

  aboutToAppear(): void {
    const ctx0 = getContext(this) as common.UIAbilityContext;
    const draft = this.loadDraft(ctx0);
    if (draft !== '') {
      this.text = draft;
      this.restored = true;
    }
    this.getUIContext().animateTo({ duration: Theme.MS_ENTER, curve: Curve.EaseOut }, () => {
      this.scrimOn = true;
    });
    this.remoteMode = AppStorage.get<string>('appMode') === 'remote';
    if (this.remoteMode) {
      this.loadRemoteVaults();
    } else {
      this.refreshVaults(ctx0);
      this.destination = QuickCapture.destinationLabel(ctx0, this.text);
    }
    // 聚焦由 TextArea 的 defaultFocus(true) 承担（controller.requestFocus 在本 SDK 不存在）
  }

  onPageShow(): void {
    const savedText = AppStorage.get<string>('remoteCaptureQuickSavedText') ?? '';
    if (savedText !== '' && savedText === this.text.trim()) {
      this.text = '';
      this.restored = false;
      this.saveDraft(getContext(this) as common.UIAbilityContext, '');
      AppStorage.setOrCreate('remoteCaptureQuickSavedText', '');
    }
  }

  // 草稿落盘到 filesDir：进程被杀也不丢（此前存在 AppStorage 内存里）
  private draftFile(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/quick_note_draft.txt';
  }

  private formatOptions(): QuickCaptureFormattingOptions {
    return { isTask: this.isTask, addTime: this.addTime };
  }

  private previewEntry(): string {
    return QuickCapture.formatEntry(this.text, '', this.formatOptions());
  }

  private loadDraft(ctx: common.UIAbilityContext): string {
    try {
      const f = this.draftFile(ctx);
      if (!fs.accessSync(f)) {
        return '';
      }
      const raw = fs.readTextSync(f);
      // 新草稿正文与选项同文件保存；旧纯文本草稿仍可直接恢复。
      try {
        const draft = JSON.parse(raw) as QuickNoteDraft;
        if (draft.version === 1 && typeof draft.text === 'string' &&
          typeof draft.isTask === 'boolean' && typeof draft.addTime === 'boolean') {
          this.isTask = draft.isTask;
          this.addTime = draft.addTime;
          return draft.text;
        }
      } catch (e) {
        // 旧草稿不是 JSON，不影响恢复正文。
      }
      // 只迁移明确的首行任务标记，不把“09:30 开会”这样的正文当元数据删掉。
      const task = raw.match(/^(?:[-*+]\s+)?\[ \]\s*/);
      if (task !== null) {
        this.isTask = true;
        return raw.substring(task[0].length);
      }
      return raw;
    } catch (e) {
      return '';
    }
  }

  private saveDraft(ctx: common.UIAbilityContext, value: string): void {
    try {
      const draft: QuickNoteDraft = {
        version: 1, text: value, isTask: this.isTask, addTime: this.addTime
      };
      const h = fs.openSync(this.draftFile(ctx), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(h.fd, JSON.stringify(draft));
      fs.closeSync(h);
    } catch (e) {
      // 草稿是尽力而为，不影响主流程。
    }
  }

  private refreshVaults(context: common.UIAbilityContext): void {
    // 有库时一次扫描即可；只有无库时才调用 resolveVault 触发默认库创建，再重新读取。
    let latest: VaultEntry[] = QuickCapture.listVaults(context);
    if (latest.length === 0) {
      QuickCapture.resolveVault(context);
      latest = QuickCapture.listVaults(context);
    }
    this.vaultEntries = latest;
    this.vaultOptions = latest.map((v: VaultEntry) => v.name);
    const wantedPath: string = AppStorage.get<string>('activeVaultPath') ?? '';
    const wantedName: string = AppStorage.get<string>('activeVault') ?? '';
    let current: VaultEntry[] = latest.filter((v: VaultEntry) => v.path === wantedPath);
    if (current.length === 0 && wantedName !== '') {
      current = latest.filter((v: VaultEntry) => v.name === wantedName);
    }
    this.vaultName = current.length > 0 ? current[0].name :
      (this.vaultOptions.length > 0 ? this.vaultOptions[0] : '');
  }

  private rememberVault(name: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    const all: VaultEntry[] = this.vaultEntries.length > 0 ? this.vaultEntries : QuickCapture.listVaults(context);
    for (const v of all) {
      if (v.name === name) {
        QuickCapture.setActiveVaultPath(v.path);
        return;
      }
    }
    QuickCapture.setActiveVault(name);
  }

  private switchMode(remote: boolean): void {
    if (this.saving || this.remoteMode === remote) { return; }
    this.remoteMode = remote;
    this.remoteSeq++;
    this.remoteLoading = false;
    this.saveFailed = false;
    this.showVaults = false;
    if (remote) {
      this.loadRemoteVaults();
    } else {
      const ctx = getContext(this) as common.UIAbilityContext;
      this.refreshVaults(ctx);
      this.destination = QuickCapture.destinationLabel(ctx, this.text);
    }
  }

  private async loadRemoteVaults(): Promise<void> {
    const seq = ++this.remoteSeq;
    this.remoteError = '';
    this.remoteLoading = false;
    this.remoteVaults = [];
    this.remoteVaultId = '';
    RemoteCaptureService.restore(getContext(this) as common.UIAbilityContext);
    if (RemoteCaptureService.server() === '') {
      this.remoteError = '尚未配置远程服务器，请在「捕获设置」里填写服务器地址和账号';
      return;
    }
    this.remoteLoading = true;
    try {
      const vaults = await RemoteCaptureService.list(getContext(this) as common.UIAbilityContext);
      if (seq !== this.remoteSeq || !this.remoteMode) { return; }
      this.remoteVaults = vaults;
      this.remoteVaultId = vaults.length === 1 ? vaults[0].id : '';
      if (vaults.length === 0) { this.remoteError = '服务器没有可用的笔记库'; }
    } catch (e) {
      if (seq === this.remoteSeq && this.remoteMode) { this.remoteError = (e as Error).message || '连接远程服务器失败'; }
    } finally {
      if (seq === this.remoteSeq) { this.remoteLoading = false; }
    }
  }

  private remoteName(): string {
    const matches = this.remoteVaults.filter((v: RemoteVault) => v.id === this.remoteVaultId);
    return matches.length > 0 ? matches[0].name : '';
  }

  private showSaved(): void {
    if (this.destinationRefreshTimer !== -1) {
      clearTimeout(this.destinationRefreshTimer);
      this.destinationRefreshTimer = -1;
    }
    this.saveDraft(getContext(this) as common.UIAbilityContext, '');
    this.getUIContext().animateTo({ duration: Theme.MS_SWAP, curve: Curve.FastOutSlowIn }, () => {
      this.saved = true;
    });
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1;
      this.leave();
    }, 480);
  }

  private async doSave(): Promise<void> {
    if (this.saving || this.saved) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const content = this.text.trim();
    if (content === '') {
      this.emptyHint = true;
      return;
    }
    if (this.remoteMode) {
      const matches = this.remoteVaults.filter((v: RemoteVault) => v.id === this.remoteVaultId);
      if (matches.length !== 1) {
        this.saveError = this.remoteError || '请先选择远程笔记库';
        this.saveFailed = true;
        return;
      }
      this.saveDraft(context, this.text);
      this.saving = true;
      this.saveFailed = false;
      this.emptyHint = false;
      try {
        const op = await RemoteCaptureService.capture(context, content, this.isTask, this.addTime, 'quick', matches[0]);
        this.destination = op.quickPath;
        this.showSaved();
      } catch (e) {
        this.saveError = (e as Error).message || '远程保存失败，内容已保留，请重试';
        this.saveFailed = true;
      } finally {
        this.saving = false;
      }
      return;
    }
    this.saveError = '';
    this.destination = QuickCapture.destinationLabel(context, content);
    this.saving = true;
    this.emptyHint = false;
    this.saveFailed = false;
    // 记住目标库（多库时用户可能刚点选过）
    if (this.vaultName !== '') {
      this.rememberVault(this.vaultName);
    }
    const capturedAt = Date.now();
    const options = this.formatOptions();
    let line = QuickCapture.appendInboxAt(context, content, '', capturedAt, options);
    if (line === '') {
      // 冷启动兜底：仅在用户按下保存后唤起 picker，仍失败才报错
      const v = await QuickCapture.resolveVaultAsync(context);
      if (v !== '') {
        this.vaultName = QuickCapture.vaultName(v);
        line = QuickCapture.appendInboxAt(context, content, '', capturedAt, options);
      }
    }
    this.saving = false;
    if (line === '') {
      this.saveFailed = true;
      return;
    }
    this.showSaved();
  }

  // 取消/点空白/返回：有内容就静默存草稿再退出（下次打开自动恢复），不再弹"要放弃吗"
  private requestDismiss(): void {
    if (this.saved || this.saving) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    this.saveDraft(ctx, this.text);
    hapticLight();
    this.leave();
  }

  // 离场：先淡出再销毁
  private leave(): void {
    if (this.leaving) {
      return;
    }
    this.getUIContext().animateTo({ duration: Theme.MS_LEAVE, curve: Curve.EaseIn }, () => {
      this.leaving = true;
    });
    setTimeout(() => {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    }, Theme.MS_LEAVE + 20);
  }

  private discardDraft(): void {
    this.text = '';
    this.isTask = false;
    this.addTime = true;
    this.restored = false;
    const ctx = getContext(this) as common.UIAbilityContext;
    this.saveDraft(ctx, '');
    hapticLight();
  }

  private async chooseVault(): Promise<void> {
    if (this.saving || this.saved || this.choosingVault) {
      return;
    }
    this.choosingVault = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const v = await QuickCapture.resolveVaultAsync(context);
      if (v !== '') {
        this.saveFailed = false;
        this.refreshVaults(context);
      } else {
        this.saveFailed = true;
      }
    } catch (e) {
      this.saveFailed = true;
    } finally {
      this.choosingVault = false;
    }
  }

  onBackPress(): boolean {
    this.requestDismiss();
    return true;
  }

  aboutToDisappear(): void {
    this.remoteSeq++;
    if (this.closeTimer !== -1) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
    if (this.destinationRefreshTimer !== -1) {
      clearTimeout(this.destinationRefreshTimer);
      this.destinationRefreshTimer = -1;
    }
    if (!this.saved && !this.abandoning) {
      const ctx = getContext(this) as common.UIAbilityContext;
      this.saveDraft(ctx, this.text);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(6,8,18,0.12)')
        .opacity(this.scrimOn && !this.leaving ? 1 : 0)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.requestDismiss();
        })

      GlassCard({ faded: this.leaving, translucent: true }) {
        if (this.saved) {
          Column({ space: 10 }) {
            SuccessCheck({
              speed: 3,
              onDone: () => {
                hapticSuccess();
              }
            })
              .width(72)
              .height(72)
            Text('已记下')
              .fontSize(Theme.FS_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
            Text((this.remoteMode ? '远程库 · ' + this.remoteName() : '本地库 · ' + this.vaultName) + ' · ' + this.destination)
              .fontSize(Theme.FS_CAPTION)
              .fontColor(Theme.TEXT_TERTIARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
        } else {
          Scroll() {
          Column({ space: 12 }) {
            // 标题行：左标题，右库胶囊（多库时点开切换）
            Row() {
              Column({ space: 2 }) {
                Text('速记')
                  .fontSize(Theme.FS_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY)
                Text(this.remoteMode ? '远程库 · ' + (this.remoteName() || '请选择笔记库') : '本地库 · ' + this.destination)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (!this.remoteMode && this.vaultName !== '') {
                Row({ space: 4 }) {
                  Text(this.vaultName)
                    .fontSize(Theme.FS_CAPTION)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 120 })
                  if (this.vaultOptions.length > 1) {
                    Text(this.showVaults ? '▴' : '▾')
                      .fontSize(Theme.FS_FOOT)
                      .fontColor(Theme.TEXT_SECONDARY)
                  }
                }
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(Theme.CHIP)
                .borderRadius(Theme.R_PILL)
                .stateStyles({
                  pressed: { .scale({ x: 0.96, y: 0.96 }) }
                })
                .enabled(!this.saving)
                .onClick(() => {
                  if (this.vaultOptions.length > 1) {
                    hapticLight();
                    this.getUIContext().animateTo({ duration: Theme.MS_SWAP, curve: Curve.FastOutSlowIn }, () => {
                      this.showVaults = !this.showVaults;
                    });
                  }
                })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            Row({ space: 8 }) {
              Button('本地库')
                .layoutWeight(1).height(36)
                .backgroundColor(!this.remoteMode ? Theme.ACCENT_DEEP : Theme.CHIP)
                .fontColor(!this.remoteMode ? Color.White : Theme.TEXT_SECONDARY)
                .enabled(!this.saving)
                .onClick(() => { this.switchMode(false); })
              Button('远程库')
                .layoutWeight(1).height(36)
                .backgroundColor(this.remoteMode ? Theme.ACCENT_DEEP : Theme.CHIP)
                .fontColor(this.remoteMode ? Color.White : Theme.TEXT_SECONDARY)
                .enabled(!this.saving)
                .onClick(() => { this.switchMode(true); })
            }.width('100%')
            if (this.remoteMode) {
              Text(RemoteCaptureService.server() || '未配置远程服务器')
                .fontSize(Theme.FS_FOOT).fontColor(Theme.TEXT_TERTIARY)
                .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.remoteLoading) {
                Text('正在读取远程笔记库…').fontSize(Theme.FS_CAPTION).fontColor(Theme.TEXT_SECONDARY)
              } else if (this.remoteError !== '') {
                Text(this.remoteError).fontSize(Theme.FS_FOOT).fontColor(Theme.DANGER).width('100%')
                Button('重新连接').height(34).enabled(!this.saving)
                  .onClick(() => { this.loadRemoteVaults(); })
              } else {
                Select(this.remoteVaults.map((v: RemoteVault): SelectOption => ({ value: v.name })))
                  .fontColor(Color.White)
                  .optionFontColor(Color.White)
                  .selectedOptionFontColor(Color.White)
                  .optionBgColor('#30365B')
                  .selectedOptionBgColor('#505B96')
                  .backgroundColor('rgba(255,255,255,0.10)')
                  .value(this.remoteName() || '请选择远程笔记库')
                  .enabled(!this.saving)
                  .onSelect((index: number) => {
                    this.remoteVaultId = this.remoteVaults[index].id;
                    this.saveFailed = false;
                  })
              }
            }

            if (!this.remoteMode && this.showVaults && this.vaultOptions.length > 1) {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.vaultOptions, (name: string) => {
                  Text(name)
                    .fontSize(Theme.FS_CAPTION)
                    .fontColor(name === this.vaultName ? Color.White : Theme.TEXT_SECONDARY)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(name === this.vaultName ? Theme.ACCENT_DEEP : Theme.CHIP)
                    .borderRadius(Theme.R_PILL)
                    .margin({ right: 6, bottom: 6 })
                    .enabled(!this.saving)
                    .onClick(() => {
                      hapticLight();
                      this.vaultName = name;
                      this.saveFailed = false;
                      this.rememberVault(name);
                      this.getUIContext().animateTo({ duration: Theme.MS_SWAP }, () => {
                        this.showVaults = false;
                      });
                    })
                }, (name: string) => name)
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            }

            Column({ space: 8 }) {
              Text('记录类型')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.TEXT_TERTIARY)
              Row({ space: 6 }) {
                Text('事项')
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(!this.isTask ? Color.White : Theme.TEXT_SECONDARY)
                  .padding({ top: 10, bottom: 10 })
                  .backgroundColor(!this.isTask ? Theme.ACCENT_DEEP : Theme.CHIP)
                  .borderRadius(Theme.R_CONTROL)
                  .enabled(!this.saving)
                  .onClick(() => { hapticLight(); this.isTask = false; this.saveDraft(getContext(this) as common.UIAbilityContext, this.text); })
                Text('待办')
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(this.isTask ? Color.White : Theme.TEXT_SECONDARY)
                  .padding({ top: 10, bottom: 10 })
                  .backgroundColor(this.isTask ? Theme.ACCENT_DEEP : Theme.CHIP)
                  .borderRadius(Theme.R_CONTROL)
                  .enabled(!this.saving)
                  .onClick(() => { hapticLight(); this.isTask = true; this.saveDraft(getContext(this) as common.UIAbilityContext, this.text); })
              }
              .width('100%')
            }
            .width('100%')

            TextArea({ text: this.text, placeholder: '写下此刻想记住的内容' })
              .defaultFocus(true)
              .fontSize(Theme.FS_BODY)
              .enabled(!this.saving)
              .fontColor(Theme.TEXT_PRIMARY)
              .placeholderColor(Theme.TEXT_TERTIARY)
              .placeholderFont({ size: Theme.FS_BODY })
              .backgroundColor(Theme.FIELD)
              .borderRadius(14)
              .border({ width: 1, color: this.emptyHint ? Theme.WARN : Theme.HAIRLINE })
              .constraintSize({ minHeight: 96, maxHeight: 220 })
              .onChange((v: string) => {
                this.text = v;
                this.emptyHint = false;
                if (this.destinationRefreshTimer !== -1) {
                  clearTimeout(this.destinationRefreshTimer);
                }
                this.destinationRefreshTimer = setTimeout(() => {
                  this.destinationRefreshTimer = -1;
                  const ctx = getContext(this) as common.UIAbilityContext;
                  if (!this.remoteMode) { this.destination = QuickCapture.destinationLabel(ctx, this.text); }
                  this.saveDraft(ctx, this.text);
                }, 120);
                if (v.trim() !== '') {
                  this.saveFailed = false;
                }
              })

            if (this.restored && this.text !== '') {
              Row({ space: 8 }) {
                Text('已恢复上次未保存的草稿')
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
                  .layoutWeight(1)
                Text('清空')
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.ACCENT)
                  .padding({ left: 8, right: 4, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.discardDraft();
                  })
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            }

            if (this.vaultName === '' && !this.remoteMode) {
              Text('尚未找到笔记库（先在应用内完成初始化）')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.DANGER)
                .width('100%')
              Button(this.choosingVault ? '选择中…' : '选择存储位置')
                .width('100%')
                .height(38)
                .fontSize(13)
                .backgroundColor('rgba(122,136,232,0.18)')
                .fontColor(Theme.TEXT_SECONDARY)
                .borderRadius(13)
                .enabled(!this.saving && !this.choosingVault)
                .onClick(() => {
                  hapticLight();
                  this.chooseVault();
                })
            }

            if (this.emptyHint) {
              Text('先写一点内容，再保存')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.WARN)
                .width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            }
            if (this.saveFailed) {
              Text(this.saveError || '保存失败，请重试或先选择存储位置')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.DANGER)
                .width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            }

            if (this.text.trim() !== '') {
              Column({ space: 4 }) {
                Text('保存格式 · 时间以保存时为准')
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
                Text(this.previewEntry())
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .width('100%')
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .backgroundColor(Theme.FIELD)
              .borderRadius(12)
            }

            Row({ space: 8 }) {
              Text('添加时间')
                .fontSize(Theme.FS_CAPTION)
                .fontColor(Theme.TEXT_SECONDARY)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.addTime })
                .selectedColor(Theme.ACCENT)
                .enabled(!this.saving)
                .onChange((value: boolean) => {
                  this.addTime = value;
                  this.saveDraft(getContext(this) as common.UIAbilityContext, this.text);
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              Button(this.saving ? '保存中…' : '保存')
                .height(44)
                .width('100%')
                .fontSize(Theme.FS_BODY)
                .fontWeight(FontWeight.Medium)
                .linearGradient({ angle: 90, colors: [[Theme.ACCENT, 0], [Theme.ACCENT_DEEP, 1]] })
                .fontColor(Color.White)
                .borderRadius(Theme.R_CONTROL)
                .padding({ left: 22, right: 22 })
                .enabled(!this.saving)
                .stateStyles({
                  pressed: { .scale({ x: 0.96, y: 0.96 }) }
                })
                .onClick(() => {
                  hapticLight();
                  this.doSave();
                })
            }
            .width('100%')
            .margin({ top: 4 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
          }
          .width('100%')
          .constraintSize({ maxHeight: '65%' })
          .scrollBar(BarState.Off)
        }
      }
    }
    .width('100%')
    .height('100%')
  }

}
