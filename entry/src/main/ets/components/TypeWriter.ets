// 通用打字机文本：进场逐字浮现
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

  aboutToAppear() {
    let i = 0;
    this.timer = setInterval(() => {
      i += 1;
      this.shown = this.text.substring(0, i);
      if (i >= this.text.length && this.timer !== -1) {
        clearInterval(this.timer);
        this.timer = -1;
      }
    }, this.speed);
  }

  aboutToDisappear() {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Text(this.shown)
      .fontSize(this.fontSize)
      .fontColor(this.color)
      .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Normal)
  }
}
