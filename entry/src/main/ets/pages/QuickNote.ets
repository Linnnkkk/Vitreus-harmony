import common from '@ohos.app.ability.common';
import { QuickCapture, VaultEntry } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';

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
  @State private confirmDismiss: boolean = false;
  private closeTimer: number = -1;
  @State private choosingVault: boolean = false;
  @State private destination: string = 'Inbox.md';
  private abandoning: boolean = false;
  private destinationRefreshTimer: number = -1;
  // 页面会话内复用同一份 vault 列表，避免预览/保存重复扫描文件系统。
  private vaultEntries: VaultEntry[] = [];

  aboutToAppear(): void {
    const draft = AppStorage.get<string>('quickNoteDraft') ?? '';
    if (draft !== '') {
      this.text = draft;
      AppStorage.setOrCreate('quickNoteDraft', '');
    }
    const context = getContext(this) as common.UIAbilityContext;
    this.refreshVaults(context);
    this.destination = QuickCapture.destinationLabel(context, this.text);
    // 不在打开浮层时自动弹 picker；只有用户主动保存或选择位置时才询问存储位置。
    // 聚焦由 TextArea 的 defaultFocus(true) 承担（controller.requestFocus 在本 SDK 不存在）
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
    this.confirmDismiss = false;
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
    this.saved = true;
    hapticSuccess();
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1;
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    }, 1200);
  }

  private requestDismiss(): void {
    if (this.saved || this.saving || this.confirmDismiss) {
      return;
    }
    if (this.text.trim() !== '') {
      this.confirmDismiss = true;
      return;
    }
    this.dismissNow();
  }

  private dismissNow(): void {
    this.abandoning = true;
    AppStorage.setOrCreate('quickNoteDraft', '');
    hapticLight();
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
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
    if (!this.saved && !this.abandoning && this.text.trim() !== '') {
      AppStorage.setOrCreate('quickNoteDraft', this.text);
    }
  }

  build() {
    // 居中对话框：窗口透明后系统会给背后加毛玻璃，遮罩只轻压一层；
    // 点空白关闭
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(6,8,18,0.35)')
        // 关键：遮罩显式延伸进状态栏/导航条安全区，否则顶/底两条不在遮罩内，
        // 深浅与中间不一致（真机实锤的"横条"根因）
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.requestDismiss();
        })

      // 透明浮层：卡片入口是瞬时操作，不做成"一整个界面"
      if (this.saved) {
        Column({ space: 16 }) {
          SuccessCheck()
            .width(72)
            .height(72)
          Text('已保存到 ' + this.destination)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          if (this.vaultName !== '') {
            Text('库：' + this.vaultName)
              .fontSize(12)
              .fontColor('#9AA3D8')
          }
        }
        .width('86%')
        .padding({ top: 32, bottom: 36, left: 22, right: 22 })
        .backgroundColor('#171A33')
        .borderRadius(28)
        .shadow({ radius: 40, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 12 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 14 }) {
          Column({ space: 4 }) {
            Text('速记')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            if (this.vaultName !== '') {
              Text('保存到 ' + this.vaultName + ' / ' + this.destination)
                .fontSize(12)
                .fontColor('#9AA3D8')
            } else {
              Text('尚未找到笔记库（先在应用内完成初始化）')
                .fontSize(12)
                .fontColor('#FF6B6B')
            }
          }

          TextArea({ text: this.text, placeholder: '记点什么…' })
            .defaultFocus(true)
            .fontSize(15)
            .enabled(!this.saving)
            .fontColor('#E2E6F8')
            .placeholderColor('#6A74A8')
            .placeholderFont({ size: 15 })
            .backgroundColor('rgba(13,16,39,0.85)')
            .borderRadius(14)
            .border({ width: 1, color: 'rgba(255,255,255,0.18)' })
            .height(180)
            .onChange((v: string) => {
              this.text = v;
              this.emptyHint = false;
              // 目标标签只用于提示；延迟刷新，避免每个字符都同步扫描 vault 和读取配置。
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

          // 记到哪个库：始终显示（单库也让用户看得见落点；多库可点选切换，选择被记住）
          if (this.vaultOptions.length > 0) {
            Column({ space: 6 }) {
              Text('存到哪个库')
                .fontSize(11)
                .fontColor('#6A74A8')
                .width('100%')
                .textAlign(TextAlign.Start)
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.vaultOptions, (name: string) => {
                  Text(name)
                    .fontSize(12)
                    .fontColor(name === this.vaultName ? Color.White : '#C7CDF0')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(name === this.vaultName ? '#5F6BD8' : 'rgba(255,255,255,0.10)')
                    .borderRadius(14)
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => {
                      hapticLight();
                      this.vaultName = name;
                      this.saveFailed = false;
                      this.rememberVault(name);
                    })
                }, (name: string) => name)
              }
              .width('100%')
            }
            .width('100%')
          }

          if (this.vaultName === '') {
            Button(this.choosingVault ? '选择中…' : '选择存储位置')
              .width('100%')
              .height(38)
              .fontSize(13)
              .backgroundColor('rgba(122,136,232,0.18)')
              .fontColor('#C7CDF0')
              .borderRadius(13)
              .enabled(!this.saving && !this.choosingVault)
              .onClick(() => {
                hapticLight();
                this.chooseVault();
              })
          }

          if (this.emptyHint) {
            Text('先写一点内容，再保存')
              .fontSize(12)
              .fontColor('#F2C66D')
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          if (this.saveFailed) {
            Text('保存失败，请重试或先选择存储位置')
              .fontSize(12)
              .fontColor('#FF6B6B')
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          if (this.confirmDismiss) {
            Column({ space: 8 }) {
              Text('这条速记还没有保存，要放弃吗？')
                .fontSize(13)
                .fontColor('#F2C66D')
                .width('100%')
                .textAlign(TextAlign.Start)
              Row({ space: 10 }) {
                Button('继续编辑')
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .backgroundColor('rgba(255,255,255,0.10)')
                  .fontColor('#C7CDF0')
                  .borderRadius(13)
                  .onClick(() => {
                    this.confirmDismiss = false;
                  })
                Button('放弃')
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .backgroundColor('rgba(255,107,107,0.18)')
                  .fontColor('#FFB0B0')
                  .borderRadius(13)
                  .onClick(() => {
                    this.dismissNow();
                  })
              }
              .width('100%')
            }
            .width('100%')
          }

          Row({ space: 10 }) {
            Button('取消')
              .layoutWeight(1)
              .height(46)
              .fontSize(15)
              .backgroundColor('rgba(255,255,255,0.10)')
              .fontColor('#C7CDF0')
              .borderRadius(16)
              .onClick(() => {
                this.requestDismiss();
              })
            Button(this.saving ? '保存中…' : '保存')
              .layoutWeight(2)
              .height(46)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor(Color.White)
              .borderRadius(16)
              .enabled(!this.saving)
              .onClick(() => {
                hapticLight();
                this.doSave();
              })
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('86%')
        .padding({ top: 26, bottom: 28, left: 22, right: 22 })
        .backgroundColor('#171A33')
        .borderRadius(28)
        .shadow({ radius: 40, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 12 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
