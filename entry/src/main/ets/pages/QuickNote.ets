import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { QuickCapture } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';

// 速记输入页（ShareAbility 宿主）：桌面小组件直达 / 分享后「编辑」跳入
// 输入（或带初文）→ 保存追加 Inbox.md → 对勾动效 1.2s 自动退出
@Entry
@Component
struct QuickNote {
  @State private text: string = '';
  @State private vaultName: string = '';
  @State private saved: boolean = false;
  @State private saveFailed: boolean = false;
  @State private editingSavedLine: string = '';
  // 编辑模式：初文已在分享时保存过一条——保存时提示会追加新条目（v1 不做撤回，见计划文档）

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.vaultName = QuickCapture.vaultName(QuickCapture.resolveVault(context));
    // 冷启动（组件直接拉起、app 没开）时库根可能缺失 → 异步兜底解析，
    // 等用户输完点保存时通常已就绪
    if (this.vaultName === '') {
      QuickCapture.resolveVaultAsync(context).then((v: string) => {
        if (v !== '') {
          this.vaultName = QuickCapture.vaultName(v);
        }
      });
    }
    // 分享「编辑」跳入：带初文（router params）
    const p = router.getParams() as Record<string, string>;
    if (p && typeof p.initialText === 'string' && p.initialText !== '') {
      this.text = p.initialText;
      this.editingSavedLine = typeof p.editingSavedLine === 'string' ? p.editingSavedLine : '';
    }
    // 聚焦由 TextArea 的 defaultFocus(true) 承担（controller.requestFocus 在本 SDK 不存在）
  }

  private async doSave(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    if (this.text.trim() === '') {
      return;
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

  build() {
    Stack({ alignContent: Alignment.Center }) {
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
        .width('74%')
        .padding({ top: 26, bottom: 24, left: 22, right: 22 })
        .backgroundColor('rgba(26,29,70,0.97)')
        .borderRadius(22)
        .border({ width: 1, color: 'rgba(255,255,255,0.20)' })
        .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 8 })
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

          if (this.editingSavedLine !== '') {
            Text('注：分享时已存一条，保存将追加新条目')
              .fontSize(11)
              .fontColor('#6A74A8')
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          if (this.saveFailed) {
            Text('保存失败：未找到笔记库')
              .fontSize(12)
              .fontColor('#FF6B6B')
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          Button('保存')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
            .fontColor(Color.White)
            .borderRadius(16)
            .margin({ top: 6 })
            .onClick(() => {
              hapticLight();
              this.doSave();
            })
        }
        .width('86%')
        .padding({ top: 24, bottom: 22, left: 22, right: 22 })
        .backgroundColor('rgba(26,29,70,0.97)')
        .borderRadius(22)
        .border({ width: 1, color: 'rgba(255,255,255,0.20)' })
        .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 8 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
