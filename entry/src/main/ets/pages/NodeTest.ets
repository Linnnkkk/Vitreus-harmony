import { router } from '@kit.ArkUI';
import { MatrixRainBackground } from '../components/AmbientBackground';
import { BackButton } from '../components/BackButton';
import { resourceManager } from '@kit.LocalizationKit';
import common from '@ohos.app.ability.common';
import { fileIo as fs, ReadOptions, picker, fileUri } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { startNodeServer } from 'libentry.so';
import { hapticSuccess } from '../common/Haptics';
import { SuccessCheck } from '../components/SuccessCheck';

const IGNIS_PORT = 6791;
const IGNIS_URL = `http://127.0.0.1:${IGNIS_PORT}`;
// ignis bundle 构建号：每次重打 ignis-server.zip 必须同步改这里
// v3=server app:// 代理修复；v4=shim 层 app:// 同源改写（双保险）
const IGNIS_BUNDLE_VER = 'v11-localhost-img';

@Entry
@Component
struct NodeTest {
  @State private pressedPick: boolean = false;
  @State private pressedReimport: boolean = false;
  @State private pressedRetry: boolean = false;
  @State private status: string = '准备启动本地运行时…';
  @State private nodeLog: string = '(等待 ignis 输出…)';
  @State private webReady: boolean = false; // ignis 监听成功后才加载 ArkWeb
  @State private diagOpen: boolean = false;
  // 导入成功：弹框前先播大时刻动效
  @State private showCheck: boolean = false; // 诊断面板默认收起（普通用户不该看到黑框）
  @State private forcedImport: boolean = false; // 强制导入模式（从 ModeSelect 重导入口进来）
  private pollTimer: number = -1;

  // 释放 rawfile 到沙箱文件（通用版；getRawFileContent 是异步的，整体 async）
  private async releaseRawFile(name: string, target: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const rm: resourceManager.ResourceManager = context.resourceManager;
    const content: Uint8Array = await rm.getRawFileContent(name);
    const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const written = fs.writeSync(file.fd, content.buffer, {
      offset: content.byteOffset,
      length: content.byteLength
    });
    fs.closeSync(file);
    console.info(`[NodeTest] released ${written}B → ${target}`);
  }

  // 递归删目录（这版 SDK 的 rmdirSync 只收 1 个参数，手动遍历删）
  private rmDirRecursive(path: string): void {
    try {
      const names: Array<string> = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        const child = path + '/' + names[i];
        let isDir = false;
        try {
          const stat = fs.statSync(child);
          isDir = stat.isDirectory();
        } catch (e) { /* stat 不到当文件删 */ }
        if (isDir) {
          this.rmDirRecursive(child);
        } else {
          try { fs.unlinkSync(child); } catch (e) { /* 忽略 */ }
        }
      }
      fs.rmdirSync(path);
    } catch (e) { /* 目录不存在，直接过 */ }
  }

  // 递归建目录（这版 SDK 的 mkdirSync 第二参数是 boolean）
  private ensureDir(path: string): void {
    const parts = path.split('/');
    let cur = '';
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] === '') { cur = '/'; continue; }
      cur = cur === '/' ? '/' + parts[i] : cur + '/' + parts[i];
      if (!fs.accessSync(cur)) {
        fs.mkdirSync(cur);
      }
    }
  }

  // ignis 部署：解压 ignis-server.zip 到 filesDir/ignis/（异步，返回 Promise）
  // ★ 版本校验：rawfile 里 zip 的构建号 vs 沙箱里已部署的 build-info.json。
  //   之前"index.js 存在就跳过"导致 app 升级后沙箱仍是旧 server
  //   （app:// 修复等修复不生效的元凶）。现在版本变了就清掉重解。
  private deployIgnis(): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const filesDir: string = context.filesDir;
    const ignisDir = filesDir + '/ignis';
    const entryScript = ignisDir + '/apps/ignis-server/server/index.js';
    const stampedVer = filesDir + '/ignis-bundle-ver.txt';
    const BUNDLE_VER = IGNIS_BUNDLE_VER;

    return new Promise<string>((resolve, reject) => {
      const needDeploy = (): boolean => {
        // 进程冷启动：无条件重部署（代价 ~2s 解压，换取 bundle 与 app 严格一致）
        if (AppStorage.get<boolean>('ignisReady') !== true) {
          return true;
        }
        if (!fs.accessSync(entryScript)) {
          return true;
        }
        // 已部署但版本戳缺失或不匹配 → 重部署
        try {
          if (!fs.accessSync(stampedVer)) {
            return true;
          }
          const f = fs.openSync(stampedVer, fs.OpenMode.READ_ONLY);
          const st = fs.statSync(stampedVer);
          const buf = new ArrayBuffer(st.size);
          const n = fs.readSync(f.fd, buf);
          fs.closeSync(f);
          const deployed = String.fromCharCode(...new Uint8Array(buf.slice(0, n))).trim();
          if (deployed !== BUNDLE_VER) {
            console.info('[NodeTest] bundle stale: ' + deployed + ' != ' + BUNDLE_VER + ', redeploy');
            return true;
          }
          return false;
        } catch (e) {
          return true;
        }
      };

      if (!needDeploy()) {
        resolve(entryScript);
        return;
      }
      this.typeStatus('部署 ignis bundle ' + BUNDLE_VER + '（解压中）…');
      // 清旧目录（升级路径），再解新
      this.rmDirRecursive(ignisDir);
      const zipPath = filesDir + '/ignis-server.zip';
      this.releaseRawFile('ignis-server.zip', zipPath).then(() => {
        this.ensureDir(ignisDir);
        zlib.decompressFile(zipPath, ignisDir, (err: BusinessError) => {
          if (err !== null) {
            this.typeStatus('ignis 解压失败: ' + JSON.stringify(err));
            reject(err);
            return;
          }
          // 写版本戳
          try {
            const vf = fs.openSync(stampedVer, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            fs.writeSync(vf.fd, BUNDLE_VER);
            fs.closeSync(vf);
          } catch (e) { /* 戳失败下次会重部署，无碍 */ }
          console.info('[NodeTest] ignis deployed (' + BUNDLE_VER + ') to ' + ignisDir);
          resolve(entryScript);
        });
      }).catch((e: BusinessError) => {
        this.typeStatus('释放 ignis 包失败: ' + JSON.stringify(e));
        reject(e);
      });
    });
  }

  // 用户导入 Obsidian 资源：官方 releases 的两种自备格式（合规红线：app 不分发内容）
  //   ① obsidian-<ver>.asar.gz（GitHub releases 默认格式）
  //   ② obsidian.asar
  // 都是整文件拷进沙箱，server 启动时 Node 侧解包（对齐官方 Docker entrypoint 流程）。
  // 推荐用户用 1.12.7（官方 Docker pin 的兼容版本；1.13+ 的 i18n 是 unpacked，
  // 单 asar 文件内无数据，解包必然缺失）。
  private importObsidianAssets(): void {
    try {
      const docSelect = new picker.DocumentViewPicker();
      docSelect.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['gz', 'asar']
      }).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        const uri = uris[0];
        const context = getContext(this) as common.UIAbilityContext;
        const filesDir: string = context.filesDir;
        const targetDir = filesDir + '/obsidian-assets';
        // 清旧再解（支持升级重导）
        this.rmDirRecursive(targetDir);
        this.ensureDir(targetDir);

        // 目标名统一：.asar.gz → obsidian.asar.gz；.asar → obsidian.asar
        let dstName = 'obsidian.asar';
        if (uri.endsWith('.gz')) {
          dstName = 'obsidian.asar.gz';
        }

        this.typeStatus('拷贝 ' + dstName + '…');
        try {
          const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const stat = fs.statSync(uri);
          const dst = targetDir + '/' + dstName;
          const out = fs.openSync(dst, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          const buf = new ArrayBuffer(4 * 1024 * 1024);
          let copied = 0;
          let remaining = stat.size;
          while (remaining > 0) {
            const chunk = Math.min(remaining, buf.byteLength);
            const rd = fs.readSync(srcFile.fd, buf, { length: chunk });
            if (rd <= 0) { break; }
            fs.writeSync(out.fd, buf, { length: rd });
            copied += rd;
            remaining -= rd;
          }
          fs.closeSync(out);
          fs.closeSync(srcFile);
          this.typeStatus('导入完成');
          // 大时刻：先播对勾动效 1.2s，再弹重启提示——完成感要有仪式
          this.showCheck = true;
          setTimeout(() => {
            this.showImportDialog();
          }, 1200);
        } catch (e) {
          const err = e as Error;
          this.typeStatus('拷贝失败: ' + (err.message !== undefined ? err.message : JSON.stringify(e)));
        }
      }).catch((e: BusinessError) => {
        this.typeStatus('未选择文件');
      });
    } catch (e) {
      this.typeStatus('导入异常: ' + JSON.stringify(e));
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
            // 合并而非覆盖：保留网页钩子写的 [web:...] 行（否则每秒轮询会把它们冲掉）
            const webLines = this.nodeLog.split('\n').filter((l: string) => l.startsWith('[web'));
            this.nodeLog = keep.slice(-40).concat(webLines).join('\n');
            if (raw.includes('Server running') || raw.includes('listening')) {
              if (!this.webReady) {
                this.webReady = true;
                // 标记 server 就绪（重进本页时直接跳全屏，不再傻等状态文件）
                AppStorage.setOrCreate('ignisReady', true);
                // 没导资源：留在引导页（首页会 500，等用户导入后自动重启）
                if (!this.hasObsidianAssets()) {
                  return;
                }
                this.typeStatus('启动完成');
                setTimeout(() => {
                  router.replaceUrl({ url: 'pages/LocalWeb' });
                }, 500);
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

      // Node 进程已活 + bundle 过期 → 自动重启 app 加载新版本（免手动杀）
      if (this.serverAlive() && this.bundleStale()) {
        this.typeStatus('正在更新到新版本…');
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.terminateSelf();
        return;
      }
      // 重导入场景：ignisReady 刚被导入流程清掉（false），但 Node 进程其实还活——
      // C++ 防重入会拒二次 init，必须重启进程才能让 server 重新解包新 asar
      if (!this.serverAlive() && AppStorage.get<boolean>('ignisReady') === false
        && this.hasObsidianAssets() && this.webReady === false && this.reimportPending()) {
        this.typeStatus('新资源将在重启后生效…');
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.terminateSelf();
        return;
      }

      // 1. 部署 ignis（首次解压异步等待完成，之后直接用）
      const entryScript = await this.deployIgnis();
      this.typeStatus('正在启动本地服务…');

      // 2. C++ 侧起 Node 跑 ignis 入口
      //    vaultRoot：官方 DOWNLOAD 模式自动建 Download/包名/（持久权限）；
      //    失败返回空串 → C++ 退回应用沙箱 filesDir/vaults
      const vaultRoot = await this.ensureVaultRootAsync();
      startNodeServer(entryScript, statusPath, vaultRoot);

      this.typeStatus('正在启动，可展开下方日志查看进度');
      this.startPolling(statusPath);
    } catch (e) {
      const err = e as Error;
      this.typeStatus('启动失败: ' + (err.message !== undefined ? err.message : JSON.stringify(e)));
    }
  }

  // 重试：server 已起（本页无预览区了，重试=直接进全屏）；没起过则启动
  private retry(): void {
    if (this.webReady) {
      router.replaceUrl({ url: 'pages/LocalWeb' });
      return;
    }
    this.startNode();
  }

  // server 是否已在本次进程生命周期内就绪（AppStorage 跨页面共享：
  // 从 LocalWeb 返回再重进 NodeTest 时，Node 进程还活着但状态文件不会再来，
  // 直接认标记跳全屏，避免傻等 + "Node already started" 刷屏）
  private serverAlive(): boolean {
    return AppStorage.get<boolean>('ignisReady') === true;
  }

  // 重导入是否待生效：导入流程写入 pending 标记，重启后由冷启动链消化
  private reimportPending(): boolean {
    return AppStorage.get<boolean>('reimportPending') === true;
  }

  // vault 根：官方 DOWNLOAD 模式（自动建 Download/包名/，带持久化权限，无弹窗）。
  // 文档：developer.huawei.com save-user-file → DOWNLOAD模式保存文件。
  // save() 返回目录 URI → fileUri.FileUri 转真实路径 → 给 C++ 当 VAULT_ROOT；失败退回沙箱。
  private async ensureVaultRootAsync(): Promise<string> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const docPicker = new picker.DocumentViewPicker(context);
      const opt = new picker.DocumentSaveOptions();
      opt.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris: Array<string> = await docPicker.save(opt);
      if (uris.length === 0) {
        console.info('[NodeTest] DOWNLOAD mode returned empty, fallback to sandbox');
        return '';
      }
      // 官方姿势：fileUri.FileUri(uri).path 拿沙箱内可用的真实路径
      const realPath = new fileUri.FileUri(uris[0]).path;
      console.info('[NodeTest] vault root -> ' + realPath + ' (DOWNLOAD mode, persisted)');
      return realPath;
    } catch (e) {
      console.info('[NodeTest] DOWNLOAD mode failed, fallback to sandbox: ' + JSON.stringify(e));
      return '';
    }
  }

  aboutToAppear() {
    // 用户从 ModeSelect 点"重新导入"进来：强制留本页出导入按钮，不跳 LocalWeb
    // （否则热活+已导入会立刻跳走，重导入口永远够不着）；诊断区同步展开
    // （重导入场景用户就是来找导入按钮的，不该再手动点一次"显示诊断"）
    const forced = AppStorage.get<boolean>('forceImportPage') === true;
    if (forced) {
      AppStorage.setOrCreate('forceImportPage', false);
      this.diagOpen = true;
      this.forcedImport = true;
    }
    // 冷启动（进程刚建）：无条件走部署链——彻底保证 bundle 与 app 一致，
    // 不再依赖版本戳对不对得上（之前戳恰好相等+进程热活把旧 bundle 骗过关）。
    // 进程内热活（从 LocalWeb 返回）：跳过部署直接回全屏（Node 单次防重入，动了也白动）
    const coldStart = AppStorage.get<boolean>('ignisReady') !== true;
    if (!forced && !coldStart && this.hasObsidianAssets()) {
      router.replaceUrl({ url: 'pages/LocalWeb' });
      return;
    }
    if (forced) {
      // 服务已活时页面直接出导入按钮（不跑 startNode，防重复初始化）
      if (this.serverAlive()) {
        this.typeStatus('选择新的 Obsidian 安装包导入');
        return;
      }
    }
    this.startNode();
  }

  // 沙箱 bundle 版本是否落后于 app 内置版本（落后 → 需重部署+重启 Node）
  private bundleStale(): boolean {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const stampedVer = context.filesDir + '/ignis-bundle-ver.txt';
      if (!fs.accessSync(stampedVer)) {
        return true;
      }
      const f = fs.openSync(stampedVer, fs.OpenMode.READ_ONLY);
      const st = fs.statSync(stampedVer);
      const buf = new ArrayBuffer(st.size);
      const n = fs.readSync(f.fd, buf);
      fs.closeSync(f);
      const deployed = String.fromCharCode(...new Uint8Array(buf.slice(0, n))).trim();
      return deployed !== IGNIS_BUNDLE_VER;
    } catch (e) {
      return true;
    }
  }

  aboutToDisappear() {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
    }
  }


  // 导入成功后的重启提示（server 需重启才能解包新资源，C++ 单次防重入。
  // 确认后再退——静默退出太突兀）
  private showImportDialog(): void {
    AlertDialog.show({
      title: '导入成功',
      message: '新资源将在应用重启后生效，应用即将退出，请重新打开。',
      autoCancel: false,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '确定',
        action: () => {
          AppStorage.setOrCreate('ignisReady', false);
          AppStorage.setOrCreate('reimportPending', true);
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          ctx.terminateSelf();
        }
      }
    });
  }

  // 状态文案打字机：逐字浮现（18ms/字），工程质感；"完成"类文案收尾给双脉冲触觉
  private typeTimer: number = -1;
  private typeStatus(full: string): void {
    this.status = '';
    if (this.typeTimer !== -1) {
      clearInterval(this.typeTimer);
    }
    let i = 0;
    this.typeTimer = setInterval(() => {
      i += 1;
      this.status = full.substring(0, i);
      if (i >= full.length) {
        clearInterval(this.typeTimer);
        this.typeTimer = -1;
        if (full.indexOf('完成') >= 0) {
          hapticSuccess();
        }
      }
    }, 12);
  }

  // 左滑/系统返回：与左上角 BackButton 同目标。
  // 全 app 用 replaceUrl 导航，路由栈只有 1 层，系统默认返回无处可 pop——必须显式指路
  onBackPress(): boolean {
    if (router.getLength() > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/ModeSelect' });
    }
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底层：深靛蓝纵向渐变（设计语言同 ModeSelect/Login）
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
      })

      // 子页环境动效（与主页面波浪不同款）
      MatrixRainBackground()

      Column() {
        Text('本地运行')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 110, bottom: 40 })

        // ── 状态卡片（普通用户视角，无技术术语）──
        Column({ space: 14 }) {
          if (this.showCheck) {
            SuccessCheck()
          }
          if (!this.hasObsidianAssets()) {
            // 首次使用：引导导入（不指向下载渠道——应用不分发也不引导获取受版权内容，
            // 只声明支持的格式，组件由用户自行准备）
            Text('首次使用，导入 Obsidian 组件包')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
            Text() {
              Span('导入一次，之后全部离线可用\n数据只保存在你的设备上\n\n')
                .fontColor('#9AA3D8')
              Span('格式 .asar / .asar.gz · 推荐 1.12.7')
                .fontColor('#FF6B6B')
                .fontWeight(FontWeight.Bold)
            }
            .fontSize(12)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            Button('选择文件')
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor('#4F5AC8')
              .fontColor(Color.White)
              .borderRadius(14)
              .margin({ top: 10 })
              .scale(this.pressedPick ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
              .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.pressedPick = true;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.pressedPick = false;
                }
              })
              .onClick(() => {
                this.importObsidianAssets();
              })
          } else if (!this.webReady && !this.forcedImport) {
            // 启动中
            LoadingProgress()
              .width(44)
              .height(44)
              .color('#8F9BD8')
            Text(this.status)
              .fontSize(13)
              .fontColor('#9AA3D8')
              .textAlign(TextAlign.Center)
          } else {
            // 失败停留态 / 强制重导入口
            Text(this.status)
              .fontSize(13)
              .fontColor('#9AA3D8')
              .textAlign(TextAlign.Center)
            if (this.hasObsidianAssets()) {
              // 已导入过：出重新导入主按钮（升级 obsidian.asar 版本用）
              Button('更换组件包')
                .width('100%')
                .height(48)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .backgroundColor('#4F5AC8')
                .fontColor(Color.White)
                .borderRadius(14)
                .margin({ top: 6 })
                .scale(this.pressedReimport ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
                .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
                .onTouch((e: TouchEvent) => {
                  if (e.type === TouchType.Down) {
                    this.pressedReimport = true;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedReimport = false;
                  }
                })
                .onClick(() => {
                  this.importObsidianAssets();
                })
            }
            Button('重试')
              .width('100%')
              .height(48)
              .fontSize(15)
              .backgroundColor('#1A1E4A')
              .fontColor('#9AA3D8')
              .borderRadius(14)
              .border({ width: 1, color: '#3A4078' })
              .margin({ top: 6 })
              .scale(this.pressedRetry ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
              .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.pressedRetry = true;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.pressedRetry = false;
                }
              })
              .onClick(() => {
                this.retry();
              })
          }
        }
        .width('86%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24, top: 30, bottom: 26 })
        .backgroundColor('rgba(26,30,74,0.78)')
        .borderRadius(18)
        .border({ width: 1, color: '#3A4078' })

        // ── 诊断折叠区（开发者/排障用，默认收起；强制导入时默认展开）──
        if (this.diagOpen) {
          Column({ space: 12 }) {
            // 标题行：当前状态一句话 + 说明，替代裸日志开场
            Column({ space: 4 }) {
              Text('运行状态')
                .fontSize(12)
                .fontColor('#6A74A8')
              Text(this.status)
                .fontSize(12)
                .fontColor('#9AA3D8')
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)

            Scroll() {
              Text(this.nodeLog)
                .fontSize(11)
                .fontColor('#9BE8B4')
                .fontFamily('monospace')
                .textAlign(TextAlign.Start)
                .lineHeight(17)
                .width('100%')
                .padding(14)
            }
            .backgroundColor('#0D1027')
            .borderRadius(12)
            .border({ width: 1, color: '#232750' })
            .height(200)
            .width('100%')
            .align(Alignment.Top)

            Row({ space: 12 }) {
              Button('复制日志')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .backgroundColor('#232750')
                .fontColor('#9AA3D8')
                .borderRadius(12)
                .border({ width: 1, color: '#3A4078' })
                .onClick(() => {
                  const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.nodeLog);
                  pasteboard.getSystemPasteboard().setData(pasteData);
                  promptAction.showToast({ message: '日志已复制', duration: 1500 });
                })
              Button(this.hasObsidianAssets() ? '重新导入' : '导入')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .backgroundColor('#4F5AC8')
                .fontColor(Color.White)
                .borderRadius(12)
                .onClick(() => {
                  this.importObsidianAssets();
                })
            }
            .width('100%')
          }
          .width('86%')
          .padding({ left: 18, right: 18, top: 16, bottom: 16 })
          .backgroundColor('#161A3E')
          .borderRadius(14)
          .border({ width: 1, color: '#2A2E5E' })
          .margin({ top: 14, bottom: 4 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 14 }))
            .animation({ duration: 220, curve: Curve.EaseOut }))
        }

        Text(this.diagOpen ? '收起诊断' : '显示诊断')
          .fontSize(12)
          .fontColor('#5A649E')
          .padding({ top: 10, bottom: 14 })
          .onClick(() => {
            this.diagOpen = !this.diagOpen;
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      // 左上角返回（回模式选择；全屏 LocalWeb 里没有返回键——悬浮球承担）
      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  // 页面转场：进入=淡入+上浮，退出=淡出（全 app 统一节奏）
  // 方向感转场：前进从右滑入（旧页左移淡出）；返回从左回位（旧页向右滑走）
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 360, curve: Curve.EaseOut })
      .translate({ x: 320 })
      .opacity(0.3)
      .translate({ x: 320 })
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 360, curve: Curve.EaseOut })
      .translate({ x: -36 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 300, curve: Curve.EaseIn })
      .translate({ x: -110 })
      .opacity(0)
      .translate({ x: -110 })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 300, curve: Curve.EaseIn })
      .translate({ x: 320 })
      .opacity(0)
  }
}
