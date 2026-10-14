// 更新说明弹窗：主界面(ModeSelect)与 ArkWeb 页(LocalWeb)共用同一份内容与同一个已读 id。
// 两处各写一份、id 不一致时会互相覆盖 notice-state.json 里唯一的 lastSeenNoticeId，
// 造成「每进一个页面都弹」。改 id/内容只在这里改一处。
export const UPDATE_NOTICE_ID: string = 'vitreus-1.3.6';

@Component
export struct UpdateNoticeDialog {
  onClose: () => void = () => {};

  build() {
          Column() {
            Column({ space: 14 }) {
              Text('Vitreus 1.3.6 更新')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F3FF')
                .width('100%')
                .textAlign(TextAlign.Start)
              Text('支持 Obsidian 1.14.4 · 网页登录更顺手')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#AEB8FF')
                .width('100%')
                .textAlign(TextAlign.Start)
              Scroll() {
                Column({ space: 8 }) {
                  Text('· 支持 Obsidian 1.14.4，可导入最新版资源包使用。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 插件打开网页（如登录账号）时，改为从底部弹出的半屏窗口，不再盖住笔记；点右上角 ✕、下拉或按返回键即可关闭。登录完成后能自动回到插件。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 修复开启伺服器后，用电脑浏览器访问时频繁弹出登录框的问题。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 修复同步类插件（如 Fast Note Sync）连接家里或 Tailscale 内网地址时被拦截的问题。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 改进手机使用体验：底部导航不再被截断，编辑器工具栏保持在键盘上方，长按文字可使用复制粘贴菜单。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              }
              .constraintSize({ maxHeight: 300 })
              .scrollBar(BarState.Off)
              .width('100%')
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
