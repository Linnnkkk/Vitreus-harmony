import { router } from '@kit.ArkUI';
import { BackButton } from '../components/BackButton';
import { resourceManager } from '@kit.LocalizationKit';
import common from '@ohos.app.ability.common';
import { fileIo as fs, ReadOptions, picker } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { startNodeServer } from 'libentry.so';

const IGNIS_PORT = 6791;
const IGNIS_URL = `http://127.0.0.1:${IGNIS_PORT}`;

@Entry
@Component
struct NodeTest {
  @State private status: string = '准备启动本地运行时…';
  @State private nodeLog: string = '(等待 ignis 输出…)';
  @State private webReady: boolean = false; // ignis 监听成功后才加载 ArkWeb
  private webController: WebController = new WebController();
  private pollTimer: number = -1;

  // 释放 rawfile 到沙箱文件（通用版）
  private releaseRawFile(name: string, target: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    const rm: resourceManager.ResourceManager = context.resourceManager;
    const content: Uint8Array = rm.getRawFileContent(name);
    const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const written = fs.writeSync(file.fd, content.buffer, {
      offset: content.byteOffset,
      length: content.byteLength
    });
    fs.closeSync(file);
    console.info(`[NodeTest] released ${written}B → ${target}`);
  }

  // ignis 首次部署：解压 ignis-server.zip 到 filesDir/ignis/（异步，返回 Promise）
  // 已部署（index.js 存在）则跳过
  private deployIgnis(): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const filesDir: string = context.filesDir;
    const ignisDir = filesDir + '/ignis';
    const entryScript = ignisDir + '/apps/ignis-server/server/index.js';

    return new Promise<string>((resolve, reject) => {
      const exists = fs.accessSync(entryScript);
      if (exists) {
        resolve(entryScript);
        return;
      }
      this.status = '首次部署 ignis（解压中）…';
      const zipPath = filesDir + '/ignis-server.zip';
      this.releaseRawFile('ignis-server.zip', zipPath);
      fs.mkdirSync(ignisDir, { recursive: true });
      zlib.decompressFile(zipPath, ignisDir, (err: BusinessError) => {
        if (err !== null) {
          this.status = 'ignis 解压失败: ' + JSON.stringify(err);
          reject(err);
          return;
        }
        console.info('[NodeTest] ignis deployed to ' + ignisDir);
        resolve(entryScript);
      });
    });
  }

  // 用户导入 Obsidian 资源：选 zip → 解压到 filesDir/obsidian-assets/
  // （app 不分发受版权保护的 Obsidian 前端，用户自备；PC 端用 scripts/pack-obsidian-assets.py 打包）
  private importObsidianAssets(): void {
    try {
      const docSelect = new picker.DocumentViewPicker();
      docSelect.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['zip']
      }).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        const context = getContext(this) as common.UIAbilityContext;
        const filesDir: string = context.filesDir;
        const targetDir = filesDir + '/obsidian-assets';
        // 清旧再解（支持升级重导）
        try {
          fs.rmdirSync(targetDir, { recursive: true });
        } catch (e) { /* 没有就算了 */ }
        fs.mkdirSync(targetDir, { recursive: true });
        zlib.decompressFile(uris[0], targetDir, (err: BusinessError) => {
          if (err !== null) {
            this.status = 'Obsidian 资源解压失败: ' + JSON.stringify(err);
            return;
          }
          // 校验关键文件
          const ok = fs.accessSync(targetDir + '/index.html');
          if (!ok) {
            this.status = '资源包缺 index.html（zip 结构需为根目录直接含文件）';
            return;
          }
          this.status = '✓ Obsidian 资源已导入，重启生效（点重试）';
          this.getUIContext().getPromptAction().showToast({ message: '导入成功' });
        });
      }).catch((e: BusinessError) => {
        this.status = '选择文件取消/失败';
      });
    } catch (e) {
      this.status = '导入异常: ' + JSON.stringify(e);
    }
  }

  // Obsidian 资源是否已导入（决定提示文案）
  private hasObsidianAssets(): boolean {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      return fs.accessSync(context.filesDir + '/obsidian-assets/index.html');
    } catch (e) {
      return false;
    }
  }

  // 轮询 ignis 写的状态文件，把内容刷到页面
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
          const win = 65536; // 读尾部 64K 窗口
          const len = size > win ? win : size;
          const buf = new ArrayBuffer(win);
          const opts: ReadOptions = {
            offset: size > win ? size - win : 0,
            length: len
          };
          const readLen = fs.readSync(file.fd, buf, opts);
          fs.closeSync(file);
          if (readLen > 0) {
            const raw = String.fromCharCode(...new Uint8Array(buf.slice(0, Math.min(readLen, win))));
            const keep = raw.split('\n').filter((line: string) => {
              const t = line.trim();
              return t.length > 0 &&
                (t.includes('[cpp]') || t.includes('[js') || t.includes('[ignis]') ||
                 t.includes('Error') || t.includes('error') || t.includes('node') ||
                 t.includes('throw') || t.includes('at '));
            });
            this.nodeLog = keep.slice(-40).join('\n');
            if (raw.includes('Server running') || raw.includes('listening')) {
              this.status = '✅ ignis 已启动';
              if (!this.webReady) {
                this.webReady = true;
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
      const context = getContext(this) as common.UIAbilityContext;
      const filesDir: string = context.filesDir;
      const statusPath = filesDir + '/node-status.txt';
      try { fs.unlinkSync(statusPath); } catch (e) { /* 没有就算了 */ }

      // 1. 部署 ignis（首次解压异步等待完成，之后直接用）
      const entryScript = await this.deployIgnis();
      this.status = '启动 ignis（libnode.so）…';

      // 2. C++ 侧起 Node 跑 ignis 入口
      startNodeServer(entryScript, statusPath);

      this.status = '等待 ignis 启动…（下方实时日志）';
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
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Text('本地模式')
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

        // ignis 实时输出
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

        // ignis 起来后才渲染 ArkWeb
        if (this.webReady) {
          Web({ src: IGNIS_URL, controller: this.webController })
            .width('100%')
            .height('30%')
            .backgroundColor(Color.White)
        } else {
          Column() {
            Text('等待 ignis server 监听 ' + IGNIS_PORT + ' …')
              .fontSize(14)
              .fontColor('#8888AA')
          }
          .width('100%')
          .height('30%')
          .backgroundColor('#252855')
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }

        Row({ space: 12 }) {
          Button('重试')
            .fontSize(14)
            .backgroundColor('#2A2D6E')
            .onClick(() => {
              this.startNode();
            })
          Button('复制日志')
            .fontSize(14)
            .backgroundColor('#3A3D7E')
            .onClick(() => {
              const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.nodeLog);
              pasteboard.getSystemPasteboard().setData(pasteData);
              promptAction.showToast({ message: '日志已复制', duration: 1500 });
            })
          Button(this.hasObsidianAssets() ? '已导入资源' : '导入 Obsidian 资源')
            .fontSize(14)
            .backgroundColor('#3A3D5E')
            .onClick(() => {
              this.importObsidianAssets();
            })
        }
        .margin({ top: 10 })
      }
      .width('100%')
      .height('100%')

      // 左上角常驻返回（回模式选择）
      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1B1E4A')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
