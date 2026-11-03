import { promptAction } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { VipPromo } from '../common/VipPromo';

// 更新说明弹窗：主界面(ModeSelect)与 ArkWeb 页(LocalWeb)共用同一份内容与同一个已读 id。
// 两处各写一份、id 不一致时会互相覆盖 notice-state.json 里唯一的 lastSeenNoticeId，
// 造成「每进一个页面都弹」。改 id/内容只在这里改一处。
export const UPDATE_NOTICE_ID: string = 'vitreus-1.4.6';

@Component
export struct UpdateNoticeDialog {
  onClose: () => void = () => {};
  // 由主页传入时才显示「查看会员」：本地网页页（Obsidian 运行中）不跳转，避免打断正在使用的笔记库。
  onOpenVip: (() => void) | undefined = undefined;

  private rateApp(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 先走共用关闭回调，记录已读；从应用市场返回时不再弹出。
    this.onClose();
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://appgallery.huawei.com/app/detail?id=com.vitreus.app&channelId=SHARE&source=appshare'
    };
    try {
      ctx.startAbility(want).catch(() => {
        promptAction.showToast({ message: '暂时无法打开应用市场，请稍后再试' });
      });
    } catch (e) {
      promptAction.showToast({ message: '暂时无法打开应用市场，请稍后再试' });
    }
  }

  build() {
          Column() {
            Column({ space: 14 }) {
              Text('Vitreus 1.4.6 更新')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F3FF')
                .width('100%')
                .textAlign(TextAlign.Start)
              Scroll() {
                Column({ space: 8 }) {
                  Text('【功能】')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#F2F3FF')
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ top: 0 })
                  Text('· 现在可以用 Vitreus 打开 PDF：在文件管理器里点 PDF，「打开方式」里选 Vitreus。目前只能放入本地笔记库。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  if (VipPromo.isActive()) {
                    Text('【限时活动】')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#F2F3FF')
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .margin({ top: 6 })
                    Text('· 11 月 4 日至 11 日，首次订阅包月会员，首月 ' + VipPromo.PRICE_TEXT + '。解锁 WebDAV 远程库，以及用电脑浏览器、AI 访问本设备笔记。')
                      .fontSize(13)
                      .fontColor('#C4C9E8')
                      .lineHeight(21)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                    Text('次月起 ' + VipPromo.ORIGINAL_MONTHLY_TEXT + '/月自动续费，可随时在「设置 → 华为账号 → 付款与购买 → 订阅」中取消。')
                      .fontSize(12)
                      .fontColor('#9AA3CC')
                      .lineHeight(19)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              }
              .constraintSize({ maxHeight: 300 })
              .scrollBar(BarState.Off)
              .width('100%')
              if (VipPromo.isActive() && this.onOpenVip !== undefined) {
                Button('查看会员')
                  .width('100%')
                  .height(42)
                  .fontSize(14)
                  .fontColor('#F2D9A0')
                  .backgroundColor('rgba(232,169,74,0.14)')
                  .border({ width: 1, color: 'rgba(242,198,109,0.38)' })
                  .borderRadius(14)
                  .onClick(() => {
                    // 先走共用关闭回调记录已读，再进会员页。
                    this.onClose();
                    if (this.onOpenVip !== undefined) { this.onOpenVip(); }
                  })
              }
              Button('给 APP 好评')
                .width('100%')
                .height(42)
                .fontSize(14)
                .fontColor('#D8DFFF')
                .backgroundColor('rgba(122,136,232,0.16)')
                .border({ width: 1, color: 'rgba(174,184,255,0.30)' })
                .borderRadius(14)
                .onClick(() => {
                  this.rateApp();
                })
              Button('知道了')
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor(Color.White)
                .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                .borderRadius(14)
                .margin({ top: 4 })
                .onClick(() => {
                  this.onClose();
                })
            }
            .width('82%')
            .padding({ left: 22, right: 22, top: 24, bottom: 22 })
            .backgroundColor('rgba(23,26,61,0.96)')
            .borderRadius(22)
            .border({ width: 1, color: 'rgba(190,199,255,0.28)' })
            .shadow({ radius: 36, color: 'rgba(0,0,0,0.45)', offsetY: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(5,7,24,0.48)')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .zIndex(20)
    }
}
