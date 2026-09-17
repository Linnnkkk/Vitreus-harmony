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

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.refreshVaults(context);
    // 冷启动（组件直接拉起、app 没开）时库根可能缺失 → 异步兜底解析，
    // 等用户输完点保存时通常已就绪
    if (this.vaultName === '') {
      QuickCapture.resolveVaultAsync(context).then((v: string) => {
        if (v !== '') {
          this.refreshVaults(context);
        }
      });
    }
    // 聚焦由 TextArea 的 defaultFocus(true) 承担（controller.requestFocus 在本 SDK 不存在）
  }

  private refreshVaults(context: common.UIAbilityContext): void {
    const all: VaultEntry[] = QuickCapture.listVaults(context);
    this.vaultOptions = all.map((v: VaultEntry) => v.name);
    const cur = QuickCapture.vaultName(QuickCapture.resolveVault(context));
    this.vaultName = cur !== '' ? cur : (this.vaultOptions.length > 0 ? this.vaultOptions[0] : '');
  }

  private async doSave(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    if (this.text.trim() === '') {
      return;
    }
    // 记住目标库（多库时用户可能刚点选过）
    if (this.vaultName !== '') {
      QuickCapture.setActiveVault(this.vaultName);
    }
    let line = QuickCapture.appendInbox(context, this.text.trim(), '');
    if (line === '') {
      // 冷启动兜底：再解析一次库根（picker），仍失败才报错
      const v = await QuickCapture.resolveVaultAsync(context);
      if (v !== '') {
        this.vaultName = QuickCapture.vaultName(v);
        line = QuickCapture.appendInbox(context, this.text.trim(), '');
      }
    }
    if (line === '') {
      this.saveFailed = true;
      return;
    }
    this.saved = true;
    hapticSuccess();
    setTimeout(() => {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    }, 1200);
  }

  // 点空白遮罩 = 关闭（对话框手感）
  private dismiss(): void {
    hapticLight();
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
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
          this.dismiss();
        })

      // 透明浮层：卡片入口是瞬时操作，不做成"一整个界面"
      if (this.saved) {
        Column({ space: 16 }) {
          SuccessCheck()
            .width(72)
            .height(72)
          Text('已保存到 Inbox')
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
              Text('保存到 ' + this.vaultName + ' / Inbox.md')
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
            .fontColor('#E2E6F8')
            .placeholderColor('#6A74A8')
            .placeholderFont({ size: 15 })
            .backgroundColor('rgba(13,16,39,0.85)')
            .borderRadius(14)
            .border({ width: 1, color: 'rgba(255,255,255,0.18)' })
            .height(180)
            .onChange((v: string) => {
              this.text = v;
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
                      QuickCapture.setActiveVault(name);
                    })
                }, (name: string) => name)
              }
              .width('100%')
            }
            .width('100%')
          }

          if (this.saveFailed) {
            Text('保存失败：未找到笔记库')
              .fontSize(12)
              .fontColor('#FF6B6B')
              .width('100%')
              .textAlign(TextAlign.Start)
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
                this.dismiss();
              })
            Button('保存')
              .layoutWeight(2)
              .height(46)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor(Color.White)
              .borderRadius(16)
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
