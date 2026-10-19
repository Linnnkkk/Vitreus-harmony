import common from '@ohos.app.ability.common';
import { RemoteCapture, RemoteCaptureEngine, RemoteCaptureOperation, RemoteVault } from './RemoteCapture';
import { createNativeRemoteRequester } from './RemoteCaptureHttp';
import { RemoteCredentialStore } from './RemoteCredentialStore';
import { CapturePathSettings } from './CapturePathSettings';
import { VipService } from './VipService';
import { RemoteServerSettings } from './RemoteServerSettings';

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
    const normalized = RemoteCapture.normalizeServer(server);
    const credential = await RemoteCredentialStore.load(normalized);
    return new RemoteCaptureEngine(context, createNativeRemoteRequester(normalized,
      credential !== undefined ? credential.user : '', credential !== undefined ? credential.pwd : ''));
  }

  static async list(context: common.UIAbilityContext): Promise<RemoteVault[]> {
    if (RemoteCaptureService.server() === '') {
      throw new Error('请先在主界面的远程模式中保存服务器地址和账号密码');
    }
    return (await RemoteCaptureService.engine(context, RemoteCaptureService.server())).listVaults();
  }

  static async capture(context: common.UIAbilityContext, text: string, isTask: boolean,
    addTime: boolean, kind: string, vault: RemoteVault): Promise<RemoteCaptureOperation> {
    if (RemoteCaptureService.busy) { throw new Error('远程捕获正在保存，请稍候'); }
    if (text.trim() === '' || vault.id === '') { throw new Error('请输入内容并选择远程笔记库'); }
    RemoteCaptureService.busy = true;
    try {
      const server = RemoteCapture.normalizeServer(RemoteCaptureService.server());
      let op = RemoteCapture.load(context);
      if (op !== undefined && op.stage !== 'done' && op.stage !== 'undone' && op.stage !== 'archived') {
        // 只允许继续完全相同的操作；绝不把未知结果归档后再次追加。
        if (op.serverURL !== server || op.text !== text || op.kind !== kind ||
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
          templates: CapturePathSettings.load(context), premium: VipService.isVip()
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
    const engine = await RemoteCaptureService.engine(context, op.serverURL);
    await engine.undo(op);
  }
}
