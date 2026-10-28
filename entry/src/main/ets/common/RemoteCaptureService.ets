import common from '@ohos.app.ability.common';
import { RemoteCapture, RemoteCaptureEngine, RemoteCaptureOperation, RemoteVault, RemoteResponse } from './RemoteCapture';
import { createNativeRemoteRequester } from './RemoteCaptureHttp';
import { RemoteCredentialStore } from './RemoteCredentialStore';
import { CapturePathSettings } from './CapturePathSettings';
import { VipService } from './VipService';
import { RemoteServerSettings } from './RemoteServerSettings';
import { WebDavSettings, WebDavConfig } from './WebDavSettings';
import { WebDavCredentialStore } from './WebDavCredentialStore';
import { createWebDavCaptureRequester } from './WebDavCaptureHttp';

// 捕获不依赖主窗口正在浏览的模式；只使用统一配置的服务器与保险箱凭据。
export class RemoteCaptureService {
  private static busy: boolean = false;

  // 冷启动兜底：AppStorage 里的地址可能还没恢复（分享/速记独立进程），
  // 以文件为准补一次，避免误报"尚未配置远程服务器"。
  static restore(context: common.UIAbilityContext): void {
    if (RemoteCaptureService.server() !== '') { return; }
    try {
      RemoteServerSettings.restore(context);
    } catch (e) {
      // 读不到就保持未配置状态
    }
  }

  static server(): string {
    return (AppStorage.get<string>('serverUrl') ?? '').trim().replace(/\/+$/, '');
  }

  private static async engine(context: common.UIAbilityContext, server: string): Promise<RemoteCaptureEngine> {
    if (/^https:\/\/webdav-[a-z0-9]+\.capture\.invalid$/.test(server)) {
      const config = WebDavSettings.load(context);
      if (config === undefined || !config.enabled || RemoteCaptureService.webDavServer(config) !== server) {
        throw new Error('WebDAV 连接已变更或停用，请重新选择笔记库');
      }
      if (!VipService.isVip()) { throw new Error('WebDAV 远程库需要会员权益，请先开通或恢复购买'); }
      const credential = await WebDavCredentialStore.load(config.credentialId);
      if (credential === undefined) { throw new Error('WebDAV 凭据不可用，请重新保存连接设置'); }
      // await 后再次检查连接，不能使用已经被关闭或替换的配置。
      const current = WebDavSettings.load(context);
      if (!VipService.isVip() || current === undefined || !current.enabled ||
        WebDavSettings.connectionKey(current) !== WebDavSettings.connectionKey(config)) {
        throw new Error('WebDAV 连接或会员状态已变更，请重新选择');
      }
      const requester = createWebDavCaptureRequester(config, credential.user,
        credential.pwd, RemoteCaptureService.webDavId(config));
      return new RemoteCaptureEngine(context, async (method: string, route: string, body: string): Promise<RemoteResponse> => {
        const latest = WebDavSettings.load(context);
        if (!VipService.isVip() || latest === undefined || !latest.enabled ||
          WebDavSettings.connectionKey(latest) !== WebDavSettings.connectionKey(config)) {
          throw new Error('WebDAV 连接或会员状态已变更');
        }
        return requester(method, route, body);
      });
    }
    const normalized = RemoteCapture.normalizeServer(server);
    const credential = await RemoteCredentialStore.load(normalized);
    return new RemoteCaptureEngine(context, createNativeRemoteRequester(normalized,
      credential !== undefined ? credential.user : '', credential !== undefined ? credential.pwd : ''));
  }

  private static webDavId(config: WebDavConfig): string {
    return 'webdav:' + config.credentialId;
  }

  private static webDavServer(config: WebDavConfig): string {
    // 非网络地址：仅作为持久操作的目标身份，不包含账号密码或真实服务器地址。
    return 'https://webdav-' + config.credentialId + '.capture.invalid';
  }

  static label(context: common.UIAbilityContext): string {
    try {
      const config = WebDavSettings.load(context);
      return config !== undefined && config.enabled ? 'WebDAV · ' + config.vaultName : RemoteCaptureService.server();
    } catch (e) { return 'WebDAV 配置读取失败，请重新保存连接'; }
  }

  static async list(context: common.UIAbilityContext): Promise<RemoteVault[]> {
    RemoteCaptureService.restore(context);
    const targets: RemoteVault[] = [];
    const config = WebDavSettings.load(context);
    if (config !== undefined && config.enabled && VipService.isVip()) {
      const target: RemoteVault = { id: RemoteCaptureService.webDavId(config), name: config.vaultName + ' · WebDAV' };
      targets.push(target);
    }
    const server = RemoteCaptureService.server();
    if (server !== '') {
      try {
        const vaults = await (await RemoteCaptureService.engine(context, server)).listVaults();
        for (const vault of vaults) {
          // 保留WebDAV前缀供目标路由，不能让外部服务器伪装该目标。
          if (!vault.id.startsWith('webdav:')) { targets.push(vault); }
        }
      } catch (e) {
        if (targets.length === 0) { throw RemoteCaptureEngine.asError(e); }
      }
    }
    if (targets.length === 0 && server === '') {
      throw new Error(config !== undefined && config.enabled && !VipService.isVip()
        ? 'WebDAV 远程库需要会员权益，请先开通或恢复购买'
        : '请先在主页配置 WebDAV 远程库或 Ignis 服务器');
    }
    return targets;
  }

  static async capture(context: common.UIAbilityContext, text: string, isTask: boolean,
    addTime: boolean, kind: string, vault: RemoteVault): Promise<RemoteCaptureOperation> {
    if (RemoteCaptureService.busy) { throw new Error('远程捕获正在保存，请稍候'); }
    if (text.trim() === '' || vault.id === '') { throw new Error('请输入内容并选择远程笔记库'); }
    RemoteCaptureService.busy = true;
    try {
      let server = '';
      let webDavKey = '';
      if (vault.id.startsWith('webdav:')) {
        const config = WebDavSettings.load(context);
        if (config === undefined || !config.enabled || vault.id !== RemoteCaptureService.webDavId(config)) {
          throw new Error('WebDAV 连接已变更或停用，请重新选择笔记库');
        }
        if (!VipService.isVip()) { throw new Error('WebDAV 远程库需要会员权益'); }
        server = RemoteCaptureService.webDavServer(config);
        webDavKey = WebDavSettings.connectionKey(config);
      } else {
        server = RemoteCapture.normalizeServer(RemoteCaptureService.server());
      }
      let op = RemoteCapture.load(context);
      if (op !== undefined && op.stage !== 'done' && op.stage !== 'undone' && op.stage !== 'archived') {
        // 只允许继续完全相同的操作；绝不把未知结果归档后再次追加。
        if (op.serverURL !== server || (op.webDavKey ?? '') !== webDavKey || op.text !== text || op.kind !== kind ||
          op.isTask !== isTask || op.addTime !== addTime || (op.vault !== '' && op.vault !== vault.id)) {
          throw new Error('还有一条未确认的远程保存，请先恢复原内容和目标库重试，避免重复或丢失');
        }
      } else {
        if (op !== undefined) { RemoteCapture.archive(context, op); }
        const at = Date.now();
        op = {
          version: 1, id: at.toString(36) + '-' + Math.random().toString(36).substring(2, 12),
          text: text, isTask: isTask, addTime: addTime, kind: kind, capturedAt: at,
          serverURL: server, stage: 'new', vault: '', quickPath: '', quickHeading: '',
          clipPath: '', clipBody: '', entry: '', before: '', after: '', existed: false,
          templates: CapturePathSettings.load(context), premium: VipService.isVip(), webDavKey: webDavKey
        };
        RemoteCapture.persist(context, op);
      }
      const engine = await RemoteCaptureService.engine(context, server);
      // 列表可能来自页面缓存；写入前重新核实身份，不能把本地名称当远程 id。
      const available = await engine.listVaults();
      const target = available.filter((item: RemoteVault) => item.id === vault.id)[0];
      if (target === undefined) { throw new Error('远程笔记库已不可用，请重新选择'); }
      await engine.prepare(op, target);
      await engine.save(op);
      return op;
    } finally {
      RemoteCaptureService.busy = false;
    }
  }

  static async undo(context: common.UIAbilityContext, op: RemoteCaptureOperation): Promise<void> {
    if (op.webDavKey) {
      const config = WebDavSettings.load(context);
      if (config === undefined || !config.enabled || WebDavSettings.connectionKey(config) !== op.webDavKey) {
        throw new Error('WebDAV 连接已变更，不能在其他连接中撤销原记录');
      }
    }
    const engine = await RemoteCaptureService.engine(context, op.serverURL);
    await engine.undo(op);
  }
}
