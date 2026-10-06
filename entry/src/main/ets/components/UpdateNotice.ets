// 更新说明弹窗：主界面(ModeSelect)与 ArkWeb 页(LocalWeb)共用同一份内容与同一个已读 id。
// 两处各写一份、id 不一致时会互相覆盖 notice-state.json 里唯一的 lastSeenNoticeId，
// 造成「每进一个页面都弹」。改 id/内容只在这里改一处。
export const UPDATE_NOTICE_ID: string = 'vitreus-1.3.3';

@Component
export struct UpdateNoticeDialog {
  onClose: () => void = () => {};

  build() {
          Column() {
            Column({ space: 14 }) {
              Text('Vitreus 1.3.3 更新')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F3FF')
                .width('100%')
                .textAlign(TextAlign.Start)
              Text('伺服器加密连接 · 内嵌服务升级')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#AEB8FF')
                .width('100%')
                .textAlign(TextAlign.Start)
              Scroll() {
                Column({ space: 8 }) {
                  Text('· 伺服器模式新增「加密连接（HTTPS）」：开启后传输全程加密，同一 Wi-Fi 下的其他人无法偷看笔记；默认关闭，首次用浏览器访问需手动放行证书。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 内嵌服务升级到 ignis 0.8.16：服务器暂时连不上时的编辑不再被回滚，保存后立刻删除的文件不会“复活”，文件创建时间与时间戳更准确。')
                    .fontSize(13)
                    .fontColor('#C4C9E8')
                    .lineHeight(21)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  Text('· 新开窗口的笔记会在标签页里打开；忽略规则编辑时自动保存。')
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
