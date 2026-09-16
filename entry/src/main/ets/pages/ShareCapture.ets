import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { QuickCapture, SharePayload } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';

// 编辑跳转参数（arkts 严格模式：字面量需对应显式 interface，Record 不合规）
interface QuickNoteJumpParams {
  initialText: string;
  editingSavedLine: string;
}

// 分享接收确认页（ShareAbility 宿主）：进入即自动保存 → 对勾动效 → 2.2s 自动退出
// 期间可点「编辑」跳 QuickNote 续写；无 vault（未初始化）给去主应用引导
@Entry
@Component
struct ShareCapture {
  @State private payloadText: string = '';
  @State private source: string = '';
  @State private savedLine: string = '';
  @State private saveFailed: boolean = false;
  @State private vaultName: string = '';
  @State private autoCloseTimer: number = -1;
  @State private lastArrive: number = 0;
  @StorageLink('shareNewArrive') private arriveWatch: number = 0;

  aboutToAppear(): void {
    // want payload 由 ShareAbility 解析后放入（主路径）
    const p = AppStorage.get<SharePayload>('sharePayload');
    if (p && p.text !== '') {
      this.payloadText = p.text;
      this.source = p.source;
    }
    // 兜底：onNewWant 热启通知（AppStorage 键）——冷启主路径拿不到时再试
    const fresh = AppStorage.get<string>('shareNewText');
    if (this.payloadText === '' && fresh && fresh !== '') {
      this.payloadText = fresh;
    }
    this.lastArrive = this.arriveWatch;
    this.doSave();
  }

  onPageShow(): void {
    // 热启再次分享：arrive 时间戳变化 → 重取 payload 重存
    if (this.lastArrive !== 0 && this.arriveWatch !== this.lastArrive) {
      this.lastArrive = this.arriveWatch;
      const fresh = AppStorage.get<string>('shareNewText') ?? '';
      if (fresh !== '') {
        if (this.autoCloseTimer !== -1) {
          clearTimeout(this.autoCloseTimer);
          this.autoCloseTimer = -1;
        }
        this.payloadText = fresh;
        this.saveFailed = false;
        this.doSave();
      }
    }
  }

  aboutToDisappear(): void {
    if (this.autoCloseTimer !== -1) {
      clearTimeout(this.autoCloseTimer);
    }
  }

  private doSave(): void {
    const context = getContext(this) as common.UIAbilityContext;
    if (this.payloadText === '') {
      this.saveFailed = true;
      return;
    }
    const line = QuickCapture.appendInbox(context, this.payloadText, this.source);
    if (line === '') {
      this.saveFailed = true;
      return;
    }
    this.savedLine = line;
    this.vaultName = QuickCapture.vaultName(QuickCapture.resolveVault(context));
    hapticSuccess();
    this.autoCloseTimer = setTimeout(() => {
      this.exit();
    }, 2200);
  }

  private exit(): void {
    const context = getContext(this) as common.UIAbilityContext;
    context.terminateSelf();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 品牌深蓝渐变背景（不透明，避免透明窗闪烁）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
        })

      Column({ space: 16 }) {
        if (!this.saveFailed) {
          SuccessCheck()
            .width(72)
            .height(72)
          Text('已保存到 Inbox')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          Column({ space: 4 }) {
            if (this.vaultName !== '') {
              Text('库：' + this.vaultName)
                .fontSize(12)
                .fontColor('#9AA3D8')
            }
            Text(this.savedLine)
              .fontSize(12)
              .fontColor('#9AA3D8')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
          }
          .width('86%')

          Row({ space: 12 }) {
            Button('编辑')
              .fontSize(14)
              .height(40)
              .backgroundColor('rgba(255,255,255,0.10)')
              .fontColor('#E2E6F8')
              .borderRadius(14)
              .padding({ left: 22, right: 22 })
              .onClick(() => {
                hapticLight();
                if (this.autoCloseTimer !== -1) {
                  clearTimeout(this.autoCloseTimer);
                  this.autoCloseTimer = -1;
                }
                const jumpParams: QuickNoteJumpParams = {
                  initialText: this.payloadText,
                  editingSavedLine: this.savedLine
                };
                router.replaceUrl({
                  url: 'pages/QuickNote',
                  params: jumpParams
                });
              })
            Button('完成')
              .fontSize(14)
              .height(40)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor(Color.White)
              .borderRadius(14)
              .padding({ left: 22, right: 22 })
              .onClick(() => {
                hapticLight();
                this.exit();
              })
          }
        } else {
          // 失败态：无文本或无 vault
          Text('未能保存')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          Text(this.payloadText === '' ? '没有接收到可保存的文本内容' :
            '尚未找到笔记库——请先打开 Vitreus 完成首次初始化（导入组件包并建库），再使用分享速记')
            .fontSize(12)
            .fontColor('#9AA3D8')
            .textAlign(TextAlign.Center)
            .width('80%')
            .lineHeight(19)
          if (this.payloadText !== '') {
            // 有内容但无库：先展示收到什么（用户可复制，不丢内容）
            Column({ space: 6 }) {
              Text('收到内容：')
                .fontSize(11)
                .fontColor('#6A74A8')
              Text(this.payloadText)
                .fontSize(12)
                .fontColor('#E2E6F8')
                .maxLines(5)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding(12)
                .backgroundColor('rgba(13,16,39,0.85)')
                .borderRadius(12)
                .width('100%')
            }
            .width('86%')
          }
          Row({ space: 12 }) {
            if (this.payloadText !== '') {
              Button('去初始化')
                .fontSize(14)
                .height(40)
                .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                .fontColor(Color.White)
                .borderRadius(14)
                .padding({ left: 20, right: 20 })
                .onClick(() => {
                  hapticLight();
                  const ctx = getContext(this) as common.UIAbilityContext;
                  ctx.terminateSelf(); // 先关分享窗，再拉主应用
                })
            }
            Button('关闭')
              .fontSize(14)
              .height(40)
              .backgroundColor('rgba(255,255,255,0.10)')
              .fontColor('#E2E6F8')
              .borderRadius(14)
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.exit();
              })
          }
        }
      }
      .width('82%')
      .padding({ top: 34, bottom: 30, left: 20, right: 20 })
      .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
      .borderRadius(20)
      .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
