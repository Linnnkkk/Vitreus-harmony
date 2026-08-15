import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import common from '@ohos.app.ability.common';
import { fileIo as fs, ReadOptions } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { startNodeServer } from 'libentry.so';

@Entry
@Component
struct NodeTest {
  @State private status: string = '准备启动 Node 运行时…';
  @State private nodeLog: string = '(等待 Node 输出…)';
  @State private webReady: boolean = false; // Node 监听成功后才加载 ArkWeb（避免抢跑 ERR_CONNECTION_REFUSED）
  private webController: WebController = new WebController();
  private pollTimer: number = -1;

  // 把 rawfile 的 test-server.js 释放到沙箱 filesDir
  private async releaseScript(): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const rm: resourceManager.ResourceManager = context.resourceManager;
    const content: Uint8Array = await rm.getRawFileContent('node-runtime/test-server.js');
    const filesDir: string = context.filesDir;
    const target = filesDir + '/test-server.js';
    const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    // 精确写 content 的字节（不用裸 .buffer——byteOffset/长度不对会写入垃圾 → JS SyntaxError）
    const written = fs.writeSync(file.fd, content.buffer, {
      offset: content.byteOffset,
      length: content.byteLength
    });
    fs.closeSync(file);
    console.info(`[NodeTest] released ${written}/${content.byteLength} bytes to ${target}`);
    return target;
  }

  // 轮询 Node 写的状态文件，把内容刷到页面
  // stderr 被 freopen 进同一文件后混入了 ArkWeb 日志洪水 → 只保留关注行
  private startPolling(statusPath: string) {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
    }
    this.pollTimer = setInterval(() => {
      try {
        const stat = fs.accessSync(statusPath);
        if (stat) {
          const st = fs.statSync(statusPath);
          const size = st.size;
          if (size === 0) {
            return;
          }
          const file = fs.openSync(statusPath, fs.OpenMode.READ_ONLY);
          const win = 65536; // 读尾部 64K 窗口（ArkWeb 日志洪水下，Node 输出在文件尾部）
          const len = size > win ? win : size;
          const buf = new ArrayBuffer(win);
          const opts: ReadOptions = {
            offset: size > win ? size - win : 0, // 文件内读取起始位置（读尾部）
            length: len
          };
          const readLen = fs.readSync(file.fd, buf, opts);
          fs.closeSync(file);
          if (readLen > 0) {
            const raw = String.fromCharCode(...new Uint8Array(buf.slice(0, Math.min(readLen, win))));
            // 关键行：[cpp] 前缀 / Node 错误 / JS 日志 / 模块报错；滤掉 ArkWeb 噪音
            const keep = raw.split('\n').filter((line: string) => {
              const t = line.trim();
              return t.length > 0 &&
                (t.includes('[cpp]') || t.includes('[js') || t.startsWith('[') === false ||
                 t.includes('Error') || t.includes('error') || t.includes('node') ||
                 t.includes('throw') || t.includes('at '));
            });
            // 取尾部 40 行（滚动后最新）
            this.nodeLog = keep.slice(-40).join('\n');
            if (raw.includes('已监听') || raw.includes('listening')) {
              this.status = '✅ Node http server 已起';
              if (!this.webReady) {
                this.webReady = true; // 触发 ArkWeb 条件渲染，此时才去连 6790
              }
            }
          }
        }
      } catch (e) {
        // 文件还没创建，继续等
      }
    }, 1000);
  }

  private async startNode(): Promise<void> {
    try {
      this.status = '释放脚本到沙箱…';
      const context = getContext(this) as common.UIAbilityContext;
      const filesDir: string = context.filesDir;
      const statusPath = filesDir + '/node-status.txt';
      // 清掉上次的状态文件
      try { fs.unlinkSync(statusPath); } catch (e) { /* 没有就算了 */ }

      const scriptPath = await this.releaseScript();
      this.status = '启动 Node（libnode.so）…';
      // 第二个参数：状态文件路径，Node 把日志写这里
      startNodeServer(scriptPath, statusPath);

      this.status = '等待 Node 写状态…（页面下方每秒刷新它的输出）';
      this.startPolling(statusPath);
    } catch (e) {
      const err = e as Error;
      this.status = '启动失败: ' + (err.message !== undefined ? err.message : JSON.stringify(e));
    }
  }

  aboutToAppear() {
    this.startNode();
  }

  aboutToDisappear() {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
    }
  }

  build() {
    Column() {
      Text('Node 嵌入测试')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 50, bottom: 8 })

      Text(this.status)
        .fontSize(14)
        .fontColor('#CCFFFFFF')
        .margin({ bottom: 8 })
        .textAlign(TextAlign.Center)
        .padding({ left: 20, right: 20 })

      // Node 的实时输出（状态文件内容）
      Scroll() {
        Text(this.nodeLog)
          .fontSize(11)
          .fontColor('#8FFFB0')
          .fontFamily('monospace')
          .textAlign(TextAlign.Start)
          .width('100%')
          .padding(8)
      }
      .backgroundColor('#000000')
      .borderRadius(8)
      .height('30%')
      .width('92%')
      .margin({ bottom: 8 })

      // Node 监听成功后才渲染 ArkWeb（条件渲染，避免抢跑连接被拒）
      if (this.webReady) {
        Web({ src: 'http://127.0.0.1:6790', controller: this.webController })
          .width('100%')
          .height('30%')
          .backgroundColor(Color.White)
      } else {
        Column() {
          Text('等待 Node http server 监听…')
            .fontSize(14)
            .fontColor('#8888AA')
        }
        .width('100%')
        .height('30%')
        .backgroundColor('#252855')
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
      }

      Row({ space: 16 }) {
        Button('重试')
          .fontSize(16)
          .backgroundColor('#2A2D6E')
          .onClick(() => {
            this.startNode();
          })
        Button('复制日志')
          .fontSize(16)
          .backgroundColor('#3A3D7E')
          .onClick(() => {
            // 整段日志一键进剪贴板（不用手敲）
            const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.nodeLog);
            pasteboard.getSystemPasteboard().setData(pasteData);
            promptAction.showToast({ message: '日志已复制', duration: 1500 });
          })
        Button('回选择页')
          .fontSize(16)
          .backgroundColor('#555A7A')
          .onClick(() => {
            router.replaceUrl({ url: 'pages/ModeSelect' });
          })
      }
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1B1E4A')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
