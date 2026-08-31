// 通用打字机文本：进场逐字浮现
// ── 使用规则（全 app 统一，不得随意增减）──
//   用打字机的：① 每页的副标题/说明行（进场一次性）speed 16~22
//             ② 动态状态流（NodeTest 运行状态）speed 12
//             ③ 落款/签名（About 的 Vitreus）speed 70（仪式感）
//   永不用的：主标题、按钮、输入框标签/placeholder、需逐条阅读的正文
//            （免责声明、credits）——要即时可读的内容不能让用户等字
// 用法：TypeWriter({ text: '...', size: 13, color: '#9AA3D8' })
// 注：不用 @Prop（部分设备初始化时序不稳），普通字段 + 构造传参即可
@Component
export struct TypeWriter {
  text: string = '';
  speed: number = 55; // ms/字
  fontSize: number = 14;
  color: string = '#9AA3D8';
  bold: boolean = false;
  @State private shown: string = '';
  private timer: number = -1;
  private delayT: number = -1; // 转场后开打的延迟句柄

  aboutToAppear() {
    // 转场期(约200ms)不逐字重绘（省主线程）——落定后开打，标题浮现更有仪式感
    this.delayT = setTimeout(() => {
      let i = 0;
      this.timer = setInterval(() => {
        i += 1;
        this.shown = this.text.substring(0, i);
        if (i >= this.text.length && this.timer !== -1) {
          clearInterval(this.timer);
          this.timer = -1;
        }
      }, this.speed);
    }, 280);
  }

  aboutToDisappear() {
    if (this.delayT !== -1) {
      clearTimeout(this.delayT);
      this.delayT = -1;
    }
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    // 占位法：完整文本透明渲染恒定占住布局（宽高由全文决定），打字文本左对齐叠加
    // ——逐字打出不再撑高/推挤下方内容（远程页/关于页框框下挪的根除方案）
    Stack({ alignContent: Alignment.Start }) {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontColor(Color.Transparent)
        .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Normal)
        .hitTestBehavior(HitTestMode.None)
      Text(this.shown)
        .fontSize(this.fontSize)
        .fontColor(this.color)
        .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Normal)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}
