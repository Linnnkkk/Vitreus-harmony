import common from '@ohos.app.ability.common';
import { QuickCapture, VaultEntry } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';
import { GlassCard } from '../components/GlassCard';
import { Theme } from '../common/Theme';
import { fileIo as fs } from '@kit.CoreFileKit';

// 速记输入页（ShareAbility 宿主）：桌面小组件直达
// 输入 → 保存追加 Inbox.md → 对勾动效 1.2s 自动退出；多库时可点选目标库
@Entry
@Component
struct QuickNote {
  @State private text: string = '';
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
    this.refreshVaults(ctx0);
    this.destination = QuickCapture.destinationLabel(ctx0, this.text);
    // 聚焦由 TextArea 的 defaultFocus(true) 承担（controller.requestFocus 在本 SDK 不存在）
  }

  // 草稿落盘到 filesDir：进程被杀也不丢（此前存在 AppStorage 内存里）
  private draftFile(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/quick_note_draft.txt';
  }

  private loadDraft(ctx: common.UIAbilityContext): string {
    try {
      const f = this.draftFile(ctx);
      if (fs.accessSync(f)) {
        return fs.readTextSync(f);
      }
    } catch (e) {
      // 读失败按无草稿处理
    }
    return '';
  }

  private saveDraft(ctx: common.UIAbilityContext, value: string): void {
    try {
      const f = this.draftFile(ctx);
      if (value.trim() === '') {
        if (fs.accessSync(f)) {
          fs.unlinkSync(f);
        }
        return;
      }
      const h = fs.openSync(f, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(h.fd, value);
      fs.closeSync(h);
    } catch (e) {
      // 草稿是尽力而为，不影响主流程
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
    this.destination = QuickCapture.destinationLabel(context, content);
    this.saving = true;
    this.emptyHint = false;
    this.saveFailed = false;
    // 记住目标库（多库时用户可能刚点选过）
    if (this.vaultName !== '') {
      this.rememberVault(this.vaultName);
    }
    let line = QuickCapture.appendInbox(context, content, '');
    if (line === '') {
      // 冷启动兜底：仅在用户按下保存后唤起 picker，仍失败才报错
      const v = await QuickCapture.resolveVaultAsync(context);
      if (v !== '') {
        this.vaultName = QuickCapture.vaultName(v);
        line = QuickCapture.appendInbox(context, content, '');
      }
    }
    this.saving = false;
    if (line === '') {
      this.saveFailed = true;
      return;
    }
    this.saveDraft(context, '');
    this.getUIContext().animateTo({ duration: Theme.MS_SWAP, curve: Curve.FastOutSlowIn }, () => {
      this.saved = true;
    });
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1;
      this.leave();
    }, 1400);
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
    this.restored = false;
    const ctx = getContext(this) as common.UIAbilityContext;
    this.saveDraft(ctx, '');
    hapticLight();
  }

  // 工具栏插入：追加到文本末尾（TextArea 无光标 API），确保换行位置合理
  private insertText(snippet: string): void {
    hapticLight();
    this.text = this.text + snippet;
    this.emptyHint = false;
  }

  private nowStamp(): string {
    const d = new Date();
    const hh = d.getHours() < 10 ? '0' + d.getHours() : '' + d.getHours();
    const mm = d.getMinutes() < 10 ? '0' + d.getMinutes() : '' + d.getMinutes();
    return hh + ':' + mm + ' ';
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
        .backgroundColor(Theme.SCRIM)
        .opacity(this.scrimOn && !this.leaving ? 1 : 0)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.requestDismiss();
        })

      GlassCard({ faded: this.leaving }) {
        if (this.saved) {
          Column({ space: 10 }) {
            SuccessCheck({
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
            Text((this.vaultName !== '' ? this.vaultName + ' · ' : '') + this.destination)
              .fontSize(Theme.FS_CAPTION)
              .fontColor(Theme.TEXT_TERTIARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
        } else {
          Column({ space: 12 }) {
            // 标题行：左标题，右库胶囊（多库时点开切换）
            Row() {
              Column({ space: 2 }) {
                Text('速记')
                  .fontSize(Theme.FS_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY)
                Text(this.destination)
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.vaultName !== '') {
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

            if (this.showVaults && this.vaultOptions.length > 1) {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.vaultOptions, (name: string) => {
                  Text(name)
                    .fontSize(Theme.FS_CAPTION)
                    .fontColor(name === this.vaultName ? Color.White : Theme.TEXT_SECONDARY)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(name === this.vaultName ? Theme.ACCENT_DEEP : Theme.CHIP)
                    .borderRadius(Theme.R_PILL)
                    .margin({ right: 6, bottom: 6 })
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

            TextArea({ text: this.text, placeholder: '记点什么…' })
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
                  this.destination = QuickCapture.destinationLabel(ctx, this.text);
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

            if (this.vaultName === '') {
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
              Text('保存失败，请重试或先选择存储位置')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.DANGER)
                .width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: Theme.MS_SWAP }))
            }

            // 工具栏 + 发送：常用插入一点即得
            Row({ space: 8 }) {
              this.toolChip('🕒 时间', () => { this.insertText(this.nowStamp()); })
              this.toolChip('# 标签', () => { this.insertText(' #'); })
              this.toolChip('☐ 待办', () => { this.insertText(this.text === '' ? '[ ] ' : '\n[ ] '); })
              Blank()
              Button(this.saving ? '保存中…' : '保存')
                .height(40)
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
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  toolChip(label: string, action: () => void) {
    Text(label)
      .fontSize(Theme.FS_FOOT)
      .fontColor(Theme.TEXT_SECONDARY)
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(Theme.CHIP)
      .borderRadius(Theme.R_PILL)
      .stateStyles({
        pressed: { .scale({ x: 0.95, y: 0.95 }) }
      })
      .onClick(() => {
        action();
      })
  }
}
