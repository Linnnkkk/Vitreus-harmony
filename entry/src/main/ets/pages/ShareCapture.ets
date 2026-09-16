import { Want } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { QuickCapture, SharePayload } from '../common/QuickCapture';
import { WebClip, ClipResult } from '../common/WebClip';
import { SuccessCheck } from '../components/SuccessCheck';
import { hapticSuccess, hapticLight } from '../common/Haptics';

const RECEIVE_TIMEOUT_MS = 4000;
const WORK_TIMEOUT_MS = 30000;
// 真机调试开关：true 时展示原始分享数据 + vault 定位过程，且不自动关闭
// （本次已定位完 entry/库路径问题，关掉恢复"浮层闪一下就走"的体验）
const DEBUG_RAW = false;
// 成功态停留时长：够看清结果，又不至于赖着
const TOAST_MS = 1500;

// 分享接收页（ShareAbility 宿主）
// 阶段机：receiving（等分享数据）→ working（定位库/抓正文）→ saved | failed
// 落库规则：
//   有链接 → 抓网页正文存 Clippings/<时间 标题>.md，Inbox 留一行 wikilink
//   无链接 → 纯文本追加 Inbox（原速记行为）
@Entry
@Component
struct ShareCapture {
  @State private phase: string = 'receiving';
  @State private hint: string = '正在接收分享内容…';
  @State private payloadText: string = '';
  @State private savedLine: string = '';
  @State private vaultName: string = '';
  @State private clipped: boolean = false;
  @State private noteTitle: string = '';
  @StorageLink('shareReady') @Watch('onReadyChanged') private readyTick: number = 0;
  @StorageLink('shareDebug') private shareDebug: string = '';
  private consumedTick: number = 0;
  private autoCloseTimer: number = -1;
  private receiveTimer: number = -1;
  private workTimer: number = -1;

  aboutToAppear(): void {
    // 分享数据迟迟不来 → 给结论，不留用户干等（仅在 still waiting 时触发）
    this.receiveTimer = setTimeout(() => {
      if (this.phase === 'receiving') {
        this.phase = 'failed';
        this.hint = '';
      }
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
    // 消费即清：页面重建时若 readyTick 还留着旧值，会把上一次分享又存一遍
    // （用户实测"点完成/编辑后又多一条"即此）
    AppStorage.setOrCreate('shareReady', 0);
    const p = AppStorage.get<SharePayload>('sharePayload');
    const t: string = p ? p.text : '';
    if (t === '') {
      this.clearTimers();
      this.phase = 'failed';
      this.hint = '';
      return;
    }
    this.clearTimers();
    this.payloadText = t;
    this.run(t);
  }

  // 主流水线：定位库 → 抓正文/纯文本 → 落盘
  private async run(text: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    this.phase = 'working';
    this.hint = '正在准备笔记库…';
    this.workTimer = setTimeout(() => {
      if (this.phase === 'working') {
        this.phase = 'failed';
        this.hint = '处理超时';
      }
    }, WORK_TIMEOUT_MS);

    const vault = await QuickCapture.resolveVaultAsync(context);
    if (vault === '') {
      this.fail('找不到笔记库');
      return;
    }
    this.vaultName = QuickCapture.vaultName(vault);

    const url = WebClip.pickUrl(text);
    if (url !== '') {
      this.hint = '正在抓取网页正文…';
      const clip: ClipResult = await WebClip.fetch(url);
      if (clip.ok && clip.body !== '') {
        const note = QuickCapture.saveClip(context, clip.title, url, clip.body);
        if (note !== '') {
          const line = QuickCapture.appendClipIndex(context, note, url);
          this.clipped = true;
          this.noteTitle = clip.title !== '' ? clip.title : note;
          this.succeed(line !== '' ? line : note);
          return;
        }
      }
      // 抓取失败：退回只存链接，至少不丢内容
      const fallbackLine = QuickCapture.appendInbox(context, text, '');
      if (fallbackLine !== '') {
        this.clipped = false;
        this.succeed(fallbackLine);
        return;
      }
      this.fail('保存失败');
      return;
    }

    const line = QuickCapture.appendInbox(context, text, '');
    if (line !== '') {
      this.clipped = false;
      this.succeed(line);
      return;
    }
    this.fail('保存失败');
  }

  private succeed(line: string): void {
    if (this.workTimer !== -1) {
      clearTimeout(this.workTimer);
      this.workTimer = -1;
    }
    this.savedLine = line;
    this.phase = 'saved';
    hapticSuccess();
    if (!DEBUG_RAW) {
      this.autoCloseTimer = setTimeout(() => {
        this.exit();
      }, TOAST_MS);
    }
  }

  private fail(reason: string): void {
    this.clearTimers();
    this.phase = 'failed';
    this.hint = reason;
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
  }

  private exit(): void {
    const context = getContext(this) as common.UIAbilityContext;
    context.terminateSelf();
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

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 无全屏底：窗口透明，只呈现一张浮层卡片（分享=瞬时叠加操作，不是"另一个界面"）
      Column({ space: 14 }) {
        if (this.phase === 'receiving' || this.phase === 'working') {
          LoadingProgress()
            .width(46)
            .height(46)
            .color('#8F9BD8')
          Text(this.hint)
            .fontSize(14)
            .fontColor('#9AA3D8')
        } else if (this.phase === 'saved') {
          SuccessCheck()
            .width(72)
            .height(72)
          Text(this.clipped ? '已剪藏正文到笔记库' : '已保存到 Inbox')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          Column({ space: 4 }) {
            if (this.vaultName !== '') {
              Text('库：' + this.vaultName)
                .fontSize(12)
                .fontColor('#9AA3D8')
            }
            if (this.clipped && this.noteTitle !== '') {
              Text(this.noteTitle)
                .fontSize(13)
                .fontColor('#E2E6F8')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
            }
            Text(this.savedLine)
              .fontSize(11)
              .fontColor('#9AA3D8')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
          }
          .width('86%')

        } else {
          Text('未能保存')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          Text(this.hint !== '' ? this.hint :
            '没接到可保存的内容——请从分享面板重新分享一次')
            .fontSize(12)
            .fontColor('#9AA3D8')
            .textAlign(TextAlign.Center)
            .width('80%')
            .lineHeight(19)
          if (this.payloadText !== '') {
            Column({ space: 6 }) {
              Text('收到内容：')
                .fontSize(11)
                .fontColor('#6A74A8')
              Text(this.payloadText)
                .fontSize(12)
                .fontColor('#E2E6F8')
                .maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding(12)
                .backgroundColor('rgba(13,16,39,0.85)')
                .borderRadius(12)
                .width('100%')
            }
            .width('86%')
          }
          Row({ space: 12 }) {
            Button('去初始化')
              .fontSize(14)
              .height(40)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor(Color.White)
              .borderRadius(14)
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                hapticLight();
                this.openMainApp();
              })
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

        if (DEBUG_RAW && this.debugText() !== '') {
          Column({ space: 4 }) {
            Text('调试：原始数据（长按可复制）')
              .fontSize(10)
              .fontColor('#6A74A8')
            Text(this.debugText())
              .fontSize(9)
              .fontColor('#9AA3D8')
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
      .width('78%')
      .padding({ top: 26, bottom: 24, left: 22, right: 22 })
      .backgroundColor('rgba(26,29,70,0.97)')
      .borderRadius(22)
      .border({ width: 1, color: 'rgba(255,255,255,0.20)' })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
