import { ServiceRestore } from '../common/ServiceRestore';
import { BundleDeployment } from '../common/BundleDeployment';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { MatrixRainBackground } from '../components/AmbientBackground';
import { BackButton } from '../components/BackButton';
import { resourceManager } from '@kit.LocalizationKit';
import common from '@ohos.app.ability.common';
import { fileIo as fs, ReadOptions, picker, fileUri } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { startNodeServer } from 'libentry.so';
import { RestartPrompt } from '../common/RestartPrompt';
import { hapticSuccess, hapticLight } from '../common/Haptics';
import { QuickCapture } from '../common/QuickCapture';
import { SuccessCheck } from '../components/SuccessCheck';
import { WebDavSettings, WebDavConfig } from '../common/WebDavSettings';
import { WebDavCredentialStore } from '../common/WebDavCredentialStore';
import { VipService } from '../common/VipService';
import { WebDavMount } from '../common/WebDavMount';
import { http } from '@kit.NetworkKit';

interface WebDavRuntimeVault {
  id: string;
  url: string;
  username: string;
  password: string;
}

interface WebDavRuntimeConfig {
  vaults: WebDavRuntimeVault[];
}

const IGNIS_PORT = 6791;
const IGNIS_URL = `http://127.0.0.1:${IGNIS_PORT}`;
// ignis bundle 构建号：每次重打 ignis-server.zip 必须同步改这里
// v3=server app:// 代理修复；v4=shim 层 app:// 同源改写（双保险）
const IGNIS_BUNDLE_VER = 'v44-0.8.18-mod.4-webdav-startup';

// Obsidian 组件包官方直链（GitHub releases）。与 IGNIS_BUNDLE_VER 适配版本及页面
// 页面"支持 1.12.7 – 1.14.4"文案联动，升级时同步改。合规口径（2026-09-16）：仅作
// 信息展示——用户主动点击后跳转系统浏览器自行获取；应用不代理下载、不内嵌分发。
const OBSIDIAN_ASAR_URL = 'https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.4/obsidian-1.14.4.asar.gz';

@Entry
@Component
struct NodeTest {
  // 背景动效联通：页面隐藏停表
  @State private bgVisible: boolean = true;
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
  @State private hasAssetsSnapshot: boolean = false;
  @State private compactStartup: boolean = false;
  private pollTimer: number = -1;
  private readyTimer: number = -1;
  private importTimer: number = -1;
  private recoveryTimer: number = -1;
  private pageAlive: boolean = true;
  private generation: number = 0;
  private starting: boolean = false;
  private startupPending: boolean = false;
  private navigationStarted: boolean = false;
  private pickerActive: boolean = false;

  private isCurrent(generation: number): boolean {
    return this.pageAlive && generation === this.generation;
  }

  private clearReadyTimer(): void {
    if (this.readyTimer !== -1) {
      clearTimeout(this.readyTimer);
      this.readyTimer = -1;
    }
  }

  private showStartupManagement(): void {
    this.compactStartup = false;
    if (this.recoveryTimer !== -1) {
      clearTimeout(this.recoveryTimer);
      this.recoveryTimer = -1;
    }
  }

  private scheduleReadyPage(delay: number): void {
    if (!this.pageAlive || this.navigationStarted || this.readyTimer !== -1) {
      return;
    }
    const generation = this.generation;
    this.readyTimer = setTimeout(() => {
      this.readyTimer = -1;
      if (this.isCurrent(generation)) {
        this.enterReadyPage();
      }
    }, delay);
  }

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
    return BundleDeployment.run(() => this.deployIgnisFiles());
  }

  private deployIgnisFiles(): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const filesDir: string = context.filesDir;
    const ignisDir = filesDir + '/ignis';
    const entryScript = ignisDir + '/apps/ignis-server/server/index.js';
    const stampedVer = filesDir + '/ignis-bundle-ver.txt';
    const BUNDLE_VER = IGNIS_BUNDLE_VER;

    return new Promise<string>((resolve, reject) => {
      const needDeploy = (): boolean => {
        // 冷启动也只凭版本戳判断（戳在解压完成后最后一步才写，半途被杀不会留下假戳）。
        // 旧逻辑每次冷启动都清目录重解压 ~2s+，是冷启动慢的一大块；
        // 代价：同一 IGNIS_BUNDLE_VER 下改了 zip 内容不会自动重部署——改 bundle 必须改版本串。
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
  // 支持 1.12.7 – 1.14.4：内嵌 ignis 0.8.14-mod（官方 0.8.14 基线）起带 1.13 适配层（terms/policy 版本
  // 探测、settings popout 守卫等），1.13+ 缺失的 unpacked i18n 由 server 内置兜底
  // 路由补齐（vitreus i18nFallback），单 asar/asar.gz 均可导入。两端真机验证通过。
  private importObsidianAssets(): void {
    const generation = this.generation;
    try {
      const docSelect = new picker.DocumentViewPicker();
      this.pickerActive = true;
      docSelect.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['gz', 'asar']
      }).then((uris: Array<string>) => {
        this.pickerActive = false;
        if (!this.isCurrent(generation) || uris.length === 0) {
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
          // 这里只完成组件源包复制，index.html 由下次 Node 启动解包后生成。
          this.hasAssetsSnapshot = this.hasObsidianAssets();
          // 大时刻：先播对勾动效 1.2s，再弹重启提示——完成感要有仪式
          this.showCheck = true;
          this.importTimer = setTimeout(() => {
            this.importTimer = -1;
            if (this.isCurrent(generation)) {
              this.showImportDialog();
            }
          }, 1200);
        } catch (e) {
          const err = e as Error;
          this.typeStatus('拷贝失败: ' + (err.message !== undefined ? err.message : JSON.stringify(e)));
        }
      }).catch((e: BusinessError) => {
        this.pickerActive = false;
        this.typeStatus('未选择文件');
      });
    } catch (e) {
      this.pickerActive = false;
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

  // 轮询 ignis 写的状态文件，把内容刷到页面（statusPath 固定路径，存成员便于后台停表后回页重启）
  private statusPath: string = '';
  private startPolling(statusPath: string) {
    if (!this.pageAlive) { return; }
    this.statusPath = statusPath;
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
    }
    const win = 65536; // 读尾部 64K 窗口，每次轮询复用
    const buf = new ArrayBuffer(win);
    this.pollTimer = setInterval(() => {
      try {
        const stat = fs.accessSync(statusPath);
        if (stat) {
          const st = fs.statSync(statusPath);
          const size = st.size;
          if (size === 0) {
            return;
          }
          const len = size > win ? win : size;
          const opts: ReadOptions = {
            offset: size > win ? size - win : 0,
            length: len
          };
          const file = fs.openSync(statusPath, fs.OpenMode.READ_ONLY);
          let readLen = 0;
          try {
            readLen = fs.readSync(file.fd, buf, opts);
          } finally {
            fs.closeSync(file);
          }
          if (readLen > 0) {
            const raw = String.fromCharCode(...new Uint8Array(buf, 0, Math.min(readLen, win)));
            const keep = raw.split('\n').filter((line: string) => {
              const t = line.trim();
              return t.length > 0 &&
                (t.includes('[cpp]') || t.includes('[js') || t.includes('[ignis]') ||
                 t.includes('Error') || t.includes('error') || t.includes('node') ||
                 t.includes('throw') || t.includes('at '));
            });
            // 合并而非覆盖：保留网页钩子写的 [web:...] 行（否则每秒轮询会把它们冲掉）
            const webLines = this.nodeLog.split('\n').filter((l: string) => l.startsWith('[web'));
            const nextLog = keep.slice(-40).concat(webLines).join('\n');
            if (this.nodeLog !== nextLog) {
              this.nodeLog = nextLog;
            }
            this.hasAssetsSnapshot = this.hasObsidianAssets();
            if (raw.includes('Server running') || raw.includes('listening')) {
              if (!this.webReady) {
                this.webReady = true;
                // 标记 server 就绪（重进本页时直接跳全屏，不再傻等状态文件）
                AppStorage.setOrCreate('ignisReady', true);
                // 没导资源：留在引导页（首页会 500，等用户导入后自动重启）
                if (!this.hasAssetsSnapshot) {
                  return;
                }
                this.bootLog('server running detected');
                this.typeStatus('启动完成');
                // 提前预连接本地服务：之后 LocalWeb 首个请求省掉建连
                try { webview.WebviewController.prepareForPageLoad('http://127.0.0.1:6791', true, 2); } catch (e) { /* 预连接失败不影响正常加载 */ }
                this.scheduleReadyPage(this.compactStartup ? 180 : 550);
              }
            }
          }
        }
      } catch (e) {
        // 文件还没创建，继续等
      }
    }, 300);
  }

  private bootLog(stage: string): void {
    const t0 = AppStorage.get<number>('bootT0') ?? 0;
    console.info('[boot] ' + stage + ' +' + (t0 > 0 ? Date.now() - t0 : -1) + 'ms');
  }

  private resumePendingStartup(): void {
    if (this.startupPending && this.pageAlive && this.bgVisible && !this.pickerActive && !this.starting) {
      this.startNode();
    }
  }

  private async startNode(): Promise<void> {
    if (!this.pageAlive || !this.bgVisible || this.starting || this.navigationStarted) { return; }
    this.startupPending = false;
    this.starting = true;
    const generation = this.generation;
    AppStorage.setOrCreate('bootT0', Date.now());
    this.bootLog('startNode begin');
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
        this.showImportDialog();
        return;
      }

      // 1. 部署 ignis（首次解压异步等待完成，之后直接用）
      const entryScript = await this.deployIgnis();
      if (!this.isCurrent(generation)) { return; }
      if (!this.bgVisible) { this.startupPending = true; return; }
      this.bootLog('deploy done');
      this.typeStatus('正在启动本地服务…');

      // 2. C++ 侧起 Node 跑 ignis 入口
      //    vaultRoot：官方 DOWNLOAD 模式自动建 Download/包名/（持久权限）；
      //    失败返回空串 → C++ 退回应用沙箱 filesDir/vaults
      const vaultRoot = await this.ensureVaultRootAsync();
      if (!this.isCurrent(generation)) { return; }
      if (!this.bgVisible) { this.startupPending = true; return; }
      // 记住落点：分享速记/小组件必须写进同一个 VAULT_ROOT（冷启动也要能读到）
      // 双写 AppStorage + 沙箱文件；picker 失败时 C++ 会退回沙箱 filesDir/vaults，同步记录之
      QuickCapture.saveVaultRoot(context, vaultRoot !== '' ? vaultRoot : filesDir + '/vaults');
      // Always pass an explicit runtime configuration: an absent/disabled
      // setting must not revive a stale on-disk remote-vaults.json.
      let webDavRuntime: string = '{"vaults":[]}';
      let webDav: WebDavConfig | undefined = undefined;
      try {
        webDav = WebDavSettings.load(context);
      } catch (e) {
        this.bootLog('WebDAV 配置无法读取，请在设置中重新填写；本地库仍可使用');
      }
      if (webDav !== undefined && webDav.enabled && !VipService.isVip()) {
        this.typeStatus('正在确认 WebDAV 会员权益…');
        await VipService.restore(context);
        if (!this.isCurrent(generation)) { return; }
        if (!this.bgVisible) { this.startupPending = true; return; }
      }
      if (webDav !== undefined && webDav.enabled && !VipService.isVip()) {
        throw new Error('WebDAV 远程库是会员功能，请先开通或恢复会员权益；也可关闭 WebDAV 后使用本地库');
      }
      if (webDav !== undefined && webDav.enabled && VipService.isVip()) {
        const credential = await WebDavCredentialStore.load(webDav.credentialId);
        if (!this.isCurrent(generation)) { return; }
        if (!this.bgVisible) { this.startupPending = true; return; }
        if (credential === undefined) { throw new Error('WebDAV 凭据不可用，请重新保存远程笔记库设置'); }
        const remoteVault: WebDavRuntimeVault = { id: webDav.vaultName, url: webDav.url,
          username: credential.user, password: credential.pwd };
        const runtimeConfig: WebDavRuntimeConfig = { vaults: [remoteVault] };
        webDavRuntime = JSON.stringify(runtimeConfig);
      }
      this.bootLog('vault root ready, startNodeServer call');
      startNodeServer(entryScript, statusPath, vaultRoot, webDavRuntime);
      // Track the configuration actually handed to this process; saved settings may change later.
      AppStorage.setOrCreate('webDavRuntimeStarted', true);
      AppStorage.setOrCreate('webDavRuntimeKey', webDav !== undefined && webDav.enabled ?
        WebDavSettings.connectionKey(webDav) : '');
      this.bootLog('startNodeServer returned');

      this.typeStatus('正在启动，可展开下方日志查看进度');
      this.startPolling(statusPath);
    } catch (e) {
      const err = e as Error;
      if (this.isCurrent(generation)) {
        this.showStartupManagement();
        this.typeStatus('启动失败: ' + (err.message !== undefined ? err.message : JSON.stringify(e)));
      }
    } finally {
      this.starting = false;
      // A hidden generation must finish its await before a new deployment may start.
      this.resumePendingStartup();
    }
  }

  // 只问本机服务要第一个本地库，超时很短，且任何失败都返回空串——
  // 这里只是优化进入速度，绝不能因为取不到库名而挡住本地模式。
  private async firstLocalVaultId(): Promise<string> {
    const request = http.createHttp();
    try {
      const result = await request.request('http://127.0.0.1:6791/api/vault/list', {
        method: http.RequestMethod.GET, connectTimeout: 1500, readTimeout: 1500,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode !== 200) { return ''; }
      const vaults = JSON.parse(result.result as string) as Array<Record<string, Object>>;
      for (const vault of vaults) {
        if (vault['remote'] !== true && typeof vault['id'] === 'string') { return vault['id'] as string; }
      }
    } catch (e) {
      return '';
    } finally {
      request.destroy();
    }
    return '';
  }

  private async enterReadyPage(): Promise<void> {
    if (!this.pageAlive || this.navigationStarted) { return; }
    this.navigationStarted = true;
    this.clearReadyTimer();
    const generation = this.generation;
    const mode = AppStorage.get<string>('bootMode');
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let savedWebDav: WebDavConfig | undefined = undefined;
      try { savedWebDav = WebDavSettings.load(context); } catch (e) { /* Existing verifier reports invalid configuration. */ }
      if (savedWebDav !== undefined && WebDavSettings.needsRestart(savedWebDav)) {
        this.navigationStarted = false;
        this.typeStatus('WebDAV 设置待生效，请重启应用');
        RestartPrompt.show(context, '连接设置待生效', '当前服务仍在使用原连接，重启后会应用已保存的设置。', () => {}, () => {
          if (this.pageAlive) { this.typeStatus('请从系统最近任务中划掉应用，再重新打开'); }
        });
        return;
      }
      // 远程库关闭时直接进本地：不校验远程、不恢复上次的远程库，也不等它超时。
      const webDavOff = savedWebDav !== undefined && !savedWebDav.enabled;
      if (webDavOff) {
        // ignis 会优先用自己记住的上次库；远程库已关闭时必须显式指定本地库，
        // 否则它会先去初始化那个已不存在的远程库，失败后才回到库选择界面。
        AppStorage.setOrCreate('webDavPreferLocal', true);
        AppStorage.setOrCreate('webDavLocalVault', await this.firstLocalVaultId());
      }
      let remoteId = '';
      if (!webDavOff) {
        // 已启用时保持原有严格校验：挂载不可用要提示，不能静默换成本地库。
        remoteId = await WebDavMount.verify(context);
      }
      if (!this.isCurrent(generation)) { return; }
      if (!this.bgVisible) { this.navigationStarted = false; return; }
      AppStorage.setOrCreate('webDavOpenVault', remoteId);
      await ServiceRestore.once(context);
      if (!this.isCurrent(generation)) { return; }
      await router.replaceUrl({ url: mode === 'remote' ? 'pages/Index' : (mode === 'ai' ? 'pages/AiConnectPage' : (mode === 'srv' ? 'pages/LanServerPage' : 'pages/LocalWeb')) });
    } catch (e) {
      if (this.isCurrent(generation)) {
        this.navigationStarted = false;
        this.showStartupManagement();
        const error = e as Error;
        this.typeStatus(error.message !== undefined ? error.message : '进入页面失败，请重试');
      }
    }
  }

  // 重试：server 已起（本页无预览区了，重试=直接进全屏）；没起过则启动
  private retry(): void {
    if (this.webReady) {
      this.enterReadyPage();
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
      this.pickerActive = true;
      let uris: Array<string> = [];
      try {
        uris = await docPicker.save(opt);
      } finally {
        this.pickerActive = false;
      }
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
    this.pageAlive = true;
    this.navigationStarted = false;
    // 用户从 ModeSelect 点"重新导入"进来：强制留本页出导入按钮，不跳 LocalWeb
    // （否则热活+已导入会立刻跳走，重导入口永远够不着）。诊断区保持默认收起
    // （与主流程一致，普通用户不该看到黑框；排障需要时手动展开）
    const forced = AppStorage.get<boolean>('forceImportPage') === true;
    this.hasAssetsSnapshot = this.hasObsidianAssets();
    if (forced) {
      AppStorage.setOrCreate('forceImportPage', false);
      this.forcedImport = true;
    }
    // 冷启动（进程刚建）：无条件走部署链——彻底保证 bundle 与 app 一致，
    // 不再依赖版本戳对不对得上（之前戳恰好相等+进程热活把旧 bundle 骗过关）。
    // 进程内热活（从 LocalWeb 返回）：跳过部署直接回全屏（Node 单次防重入，动了也白动）
    const coldStart = AppStorage.get<boolean>('ignisReady') !== true;
    if (!forced && this.hasAssetsSnapshot) {
      this.compactStartup = true;
      const generation = this.generation;
      this.recoveryTimer = setTimeout(() => {
        this.recoveryTimer = -1;
        if (this.isCurrent(generation) && !this.navigationStarted) {
          this.showStartupManagement();
        }
      }, 6000);
      if (!coldStart) {
        // 进程内返回时 Node 不会重写状态文件，沿用已就绪标记，保留转场等待。
        this.scheduleReadyPage(800);
        return;
      }
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
    this.pickerActive = false;
    this.onPageHide();
    this.startupPending = false;
  }


  // 导入成功后的重启提示（server 需重启才能解包新资源，C++ 单次防重入。
  // 确认后再退——静默退出太突兀）
  private showImportDialog(): void {
    // Keep pending state even when the user chooses “later”; never start another Node in this process.
    AppStorage.setOrCreate('ignisReady', false);
    AppStorage.setOrCreate('reimportPending', true);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    RestartPrompt.show(context, '资源导入成功', '新资源需要重启应用后生效。', () => {
      AppStorage.setOrCreate('ignisReady', false);
      AppStorage.setOrCreate('reimportPending', true);
    }, () => {
      if (this.pageAlive) { this.typeStatus('请从系统最近任务中划掉应用，再重新打开'); }
    });
  }

  // 状态文案打字机：逐字浮现（18ms/字），工程质感；"完成"类文案收尾给双脉冲触觉
  private typeTimer: number = -1;
  private typeStatus(full: string): void {
    if (!this.pageAlive) { return; }
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
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/ModeSelect' });
    }
    return true;
  }

  onPageShow() {
    this.pageAlive = true;
    this.bgVisible = true;
    this.resumePendingStartup();
    // 回页恢复轮询（进全屏 Web 时父页不销毁但 onHide 已停表，此处幂等重启）
    if (this.statusPath !== '' && this.pollTimer === -1) {
      this.startPolling(this.statusPath);
    }
  }

  onPageHide() {
    // System picker can cover this page without leaving its route.
    // Destruction explicitly clears pickerActive before invalidating it.
    if (this.pickerActive) { this.bgVisible = false; return; }
    if (this.starting) { this.startupPending = true; }
    this.pageAlive = false;
    this.generation += 1;
    this.navigationStarted = false;
    this.clearReadyTimer();
    if (this.recoveryTimer !== -1) {
      clearTimeout(this.recoveryTimer);
      this.recoveryTimer = -1;
    }
    if (this.importTimer !== -1) {
      clearTimeout(this.importTimer);
      this.importTimer = -1;
    }
    if (this.typeTimer !== -1) {
      clearInterval(this.typeTimer);
      this.typeTimer = -1;
    }
    this.bgVisible = false;
    // 后台停轮询：pushUrl 进全屏 Web 后父页不销毁，5s 一轮的文件 IO 在后台纯属浪费
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // 拉起系统浏览器打开 Obsidian 官方获取页（与 About.creditRow 同款 ctx.openLink，
  // 失败静默）。合规边界：只跳转浏览器，应用内不触发下载。
  private openObsidianDl(): void {
    hapticLight();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(OBSIDIAN_ASAR_URL);
    } catch (e) {
      // 无浏览器等极端场景：静默
    }
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
      MatrixRainBackground({ visible: this.bgVisible })

      if (this.compactStartup) {
        Column({ space: 18 }) {
          Text('VITREUS')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .letterSpacing(4)
          LoadingProgress()
            .width(34)
            .height(34)
            .color('#AAB5FF')
          Text('正在唤醒本地空间')
            .fontSize(14)
            .fontColor('#B7BDEB')
          Button('打开运行管理')
            .fontSize(12)
            .fontColor('#AAB5FF')
            .backgroundColor(Color.Transparent)
            .onClick(() => this.showStartupManagement())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
      // PC/平板窗口矮时内容超屏可滚（手机上内容不超屏无感知）；constraintSize 让内容少时仍占满视口
      Scroll() {
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
          if (!this.hasAssetsSnapshot) {
            // 首次使用：引导导入（合规口径 2026-09-16：官方链接仅信息展示，
            // 用户主动点击跳转浏览器自行获取；应用不分发、不代理下载、不强制不诱导）
            Text('首次使用，导入 Obsidian 组件包')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
            Text() {
              Span('导入一次，之后全部离线可用\n数据只保存在你的设备上\n\n')
                .fontColor('#9AA3D8')
              Span('格式 .asar / .asar.gz · 支持 1.12.7 – 1.14.4')
                .fontColor('#FF6B6B')
                .fontWeight(FontWeight.Bold)
            }
            .fontSize(12)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            // 官方获取渠道：信息展示型文字链（弱化样式，区别于主操作按钮，避免诱导误点）
            Row({ space: 5 }) {
              Text('官方获取')
                .fontSize(12)
                .fontColor('#6A74A8')
              Text('GitHub 发布页 ↗')
                .fontSize(12)
                .fontColor('#7A88E8')
                .decoration({ type: TextDecorationType.Underline, color: 'rgba(122,136,232,0.55)' })
                .onClick(() => {
                  this.openObsidianDl();
                })
            }
            .margin({ top: 8 })
            Button('选择文件')
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor(Color.White)
              .borderRadius(16)
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
            if (this.hasAssetsSnapshot) {
              // 已导入过：出重新导入主按钮（升级 obsidian.asar 版本用）。
              // 提示与官方获取链接对齐首次导入区（用户更换时同样需要版本指引）
              Text() {
                Span('格式 .asar / .asar.gz · 支持 1.12.7 – 1.14.4')
                  .fontColor('#FF6B6B')
                  .fontWeight(FontWeight.Bold)
              }
              .fontSize(12)
              .textAlign(TextAlign.Center)
              .margin({ bottom: 4 })
              Row({ space: 5 }) {
                Text('官方获取')
                  .fontSize(12)
                  .fontColor('#6A74A8')
                Text('GitHub 发布页 ↗')
                  .fontSize(12)
                  .fontColor('#7A88E8')
                  .decoration({ type: TextDecorationType.Underline, color: 'rgba(122,136,232,0.55)' })
                  .onClick(() => {
                    this.openObsidianDl();
                  })
              }
              .margin({ bottom: 8 })
              Button('更换组件包')
                .width('100%')
                .height(48)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                .fontColor(Color.White)
                .borderRadius(16)
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
              .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
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
        .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255,255,255,0.32)' })

        // ── 诊断折叠区（开发者/排障用，任何路径默认收起）──
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
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
            .height(200)
            .width('100%')
            .align(Alignment.Top)
            .scrollBar(BarState.Off) // PC端滚动条隐藏

            Row({ space: 12 }) {
              Button('复制日志')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                .fontColor('#FFFFFF')
                .borderRadius(16)
                .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
                .onClick(() => {
                  const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.nodeLog);
                  pasteboard.getSystemPasteboard().setData(pasteData);
                  promptAction.showToast({ message: '日志已复制', duration: 1500 });
                })
            }
            .width('100%')
          }
          .width('86%')
          .padding({ left: 18, right: 18, top: 16, bottom: 16 })
          .backgroundEffect({ radius: 30, saturation: 1.15, brightness: 1.1, color: 'rgba(255,255,255,0)' })
          .borderRadius(14)
          .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
          .margin({ top: 14, bottom: 4 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 14 }))
            .animation({ duration: 160, curve: Curve.EaseOut }))
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
      .constraintSize({ minHeight: '100%' })
      .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off) // PC端滚动条隐藏
      }

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
    PageTransitionEnter({ type: RouteType.Push, duration: 200, curve: Curve.EaseOut })
      .translate({ x: 320 })
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
  }
}
