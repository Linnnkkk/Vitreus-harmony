import common from '@ohos.app.ability.common';
import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { createNativeRemoteRequester } from '../common/RemoteCaptureHttp';
import { RemoteCredential, RemoteCredentialStore } from '../common/RemoteCredentialStore';
import {
  RemoteCapture,
  RemoteCaptureEngine,
  RemoteCaptureOperation,
  RemoteCaptureQueued,
  RemoteVault
} from '../common/RemoteCapture';

// 远程保存页：把这次速记/剪藏写到远程 ignis 服务器。
// 请求走系统网络库（NativeRemoteRequester），不依赖隐藏网页，所以没有
// 「助手未就绪 → 按钮全灰」的前置状态：进页面自动连接，失败只留一条可重试的提示。
// 只有表单登录（SSO / 自建登录页）才用到 WebView，它没有桥接，也拿不到本页凭据。
@Entry
@Component
struct RemoteCapturePage {
  private loginController: webview.WebviewController = new webview.WebviewController();
  private op: RemoteCaptureOperation | undefined = undefined;
  private alive: boolean = true;
  @State private captureText: string = '';
  @State private targetPath: string = '';
  @State private targetHeading: string = '';
  @State private server: string = '';
  @State private status: string = '正在连接服务器…';
  @State private vaults: RemoteVault[] = [];
  @State private selected: string = '';
  @State private busy: boolean = false;
  @State private showLogin: boolean = false;
  @State private showAdvanced: boolean = false;
  @State private user: string = '';
  @State private password: string = '';
  @State private stage: string = '';
  @State private queued: RemoteCaptureQueued[] = [];
  @State private credentialSaved: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    try {
      this.queued = RemoteCapture.listQueued(this.context());
      this.op = RemoteCapture.load(this.context());
      if (this.op === undefined) {
        this.status = '没有待处理的远程捕获';
        return;
      }
      this.server = this.op.serverURL;
      this.stage = this.op.stage;
      this.selected = this.op.vault;
      this.captureText = this.op.text;
      this.targetPath = this.op.quickPath;
      this.targetHeading = this.op.quickHeading;
      if (this.op.kind === 'quick' && this.op.stage === 'done') {
        AppStorage.setOrCreate<string>('remoteCaptureQuickSavedText', this.op.text);
      }
      this.loadSavedCredential();
      setTimeout(() => { this.connect(false); }, 100);
    } catch (e) {
      this.status = RemoteCapturePage.describe(e);
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.password = '';
    this.user = '';
  }

  private loadSavedCredential(): void {
    if (this.op === undefined) { return; }
    RemoteCredentialStore.load(this.op.serverURL).then((cred: RemoteCredential | undefined) => {
      if (!this.alive || cred === undefined) { return; }
      this.user = cred.user;
      this.password = cred.pwd;
      this.credentialSaved = true;
    }).catch(() => {
      // 保险箱读不到就让用户手动填
    });
  }

  private rememberCredential(): void {
    if (this.op === undefined || this.user === '' || this.password === '') { return; }
    RemoteCredentialStore.save(this.op.serverURL, this.user, this.password).then((ok: boolean) => {
      if (ok && this.alive) { this.credentialSaved = true; }
    }).catch(() => {
      // 保险箱不可用不影响已经完成的保存
    });
  }

  private engine(): RemoteCaptureEngine {
    const url = this.op !== undefined ? this.op.serverURL : this.server;
    return new RemoteCaptureEngine(this.context(),
      createNativeRemoteRequester(url, this.user, this.password));
  }

  private async connect(explicit: boolean = true): Promise<void> {
    if (this.busy || this.op === undefined) { return; }
    this.busy = true;
    this.status = '正在连接服务器…';
    try {
      const normalized = RemoteCapture.normalizeServer(this.server);
      if (normalized !== this.op.serverURL) {
        if (this.op.stage !== 'new') { throw new Error('已开始保存的记录不能更换服务器'); }
        this.op.serverURL = normalized;
        RemoteCapture.persist(this.context(), this.op);
        this.vaults = [];
        this.selected = '';
        if (explicit) { this.credentialSaved = false; }
      }
      const list = await this.engine().listVaults();
      this.vaults = list;
      if (this.vaults.length === 1 && this.selected === '') {
        this.selected = this.vaults[0].id;
      }
      if (this.vaults.length === 0) {
        this.status = '服务器上没有可用笔记库，请先在服务器端创建';
      } else if (this.selected !== '') {
        this.status = '已连接，点下方按钮保存';
        this.rememberCredential();
      } else {
        this.status = '请选择目标笔记库';
      }
    } catch (e) {
      this.status = RemoteCapturePage.describe(e);
    } finally {
      this.busy = false;
    }
  }

  private async save(): Promise<void> {
    if (this.busy || this.op === undefined) { return; }
    if (this.op.stage === 'archived' || this.op.stage === 'undone' || this.op.stage.startsWith('undo')) { return; }
    if (this.vaults.length === 0 || this.selected === '') {
      await this.connect(false);
      if (this.selected === '') { return; }
    }
    this.busy = true;
    this.status = '正在保存…';
    try {
      const vault = this.vaults.filter((v: RemoteVault) => v.id === this.selected)[0];
      if (vault === undefined) { throw new Error('请选择有效的远程笔记库'); }
      await this.engine().prepare(this.op, vault);
      this.stage = this.op.stage;
      this.targetPath = this.op.quickPath;
      this.targetHeading = this.op.quickHeading;
      await this.engine().save(this.op);
      this.stage = this.op.stage;
      if (this.op.kind === 'quick' && this.op.stage === 'done') {
        AppStorage.setOrCreate<string>('remoteCaptureQuickSavedText', this.op.text);
      }
      this.rememberCredential();
      this.status = '已保存到远程库 ' + vault.name + ' / ' + this.op.quickPath;
    } catch (e) {
      this.stage = this.op.stage;
      this.status = RemoteCapturePage.describe(e);
    } finally {
      this.busy = false;
    }
  }

  private async undo(): Promise<void> {
    if (this.busy || this.op === undefined) { return; }
    this.busy = true;
    try {
      await this.engine().undo(this.op);
      this.stage = this.op.stage;
      if (this.op.kind === 'quick') {
        AppStorage.setOrCreate<string>('remoteCaptureQuickSavedText', '');
      }
      this.status = '已撤销本次保存';
    } catch (e) {
      this.stage = this.op.stage;
      this.status = RemoteCapturePage.describe(e);
    } finally {
      this.busy = false;
    }
  }

  private keepForLater(): void {
    if (this.op === undefined || this.busy) { return; }
    AlertDialog.show({
      title: '稍后再存？',
      message: '记录会保留在本机，服务器不会被修改。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '保留记录',
        action: () => {
          if (this.op !== undefined) {
            RemoteCapture.archive(this.context(), this.op);
            this.stage = this.op.stage;
            this.status = '记录已保留，服务器未修改';
          }
        }
      }
    });
  }

  private activateDraft(filename: string): void {
    if (this.busy) { return; }
    try {
      this.op = RemoteCapture.activateQueued(this.context(), filename);
      this.server = this.op.serverURL;
      this.stage = this.op.stage;
      this.selected = this.op.vault;
      this.captureText = this.op.text;
      this.targetPath = this.op.quickPath;
      this.targetHeading = this.op.quickHeading;
      this.user = '';
      this.password = '';
      this.vaults = [];
      this.queued = RemoteCapture.listQueued(this.context());
      this.credentialSaved = false;
      this.loadSavedCredential();
      this.status = '草稿已恢复，正在连接…';
      setTimeout(() => { this.connect(false); }, 100);
    } catch (e) {
      this.status = RemoteCapturePage.describe(e);
    }
  }

  private async finish(): Promise<void> {
    if (this.busy) { return; }
    try {
      await this.context().terminateSelf();
    } catch (e) {
      this.status = '已保存，但无法关闭页面；可点返回。';
    }
  }

  private forgetCredential(): void {
    if (this.op === undefined) { return; }
    RemoteCredentialStore.forget(this.op.serverURL);
    this.credentialSaved = false;
    this.password = '';
    this.status = '已清除本机保存的账号密码';
  }

  private saveCredential(): void {
    if (this.op === undefined || this.user === '' || this.password === '') { return; }
    RemoteCredentialStore.save(this.op.serverURL, this.user, this.password).then((ok: boolean) => {
      this.credentialSaved = ok;
      this.status = ok ? '账号密码已加密保存' : '保存失败，本次仍可继续使用';
    }).catch(() => {
      this.status = '保存失败，本次仍可继续使用';
    });
  }

  private static describe(e: Object): string {
    if (e instanceof Error) {
      const message = (e as Error).message;
      return message === undefined || message === '' ? '操作失败，请重试' : message;
    }
    return String(e);
  }

  @Builder
  credentialFields() {
    Column({ space: 10 }) {
      TextInput({ text: this.server, placeholder: 'https://服务器地址' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_TERTIARY)
        .backgroundColor(Theme.FIELD)
        .enabled(!this.busy && this.stage === 'new')
        .onChange((v: string) => { this.server = v; })
      TextInput({ text: this.user, placeholder: '账号（服务器要求登录时填写）' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_TERTIARY)
        .backgroundColor(Theme.FIELD)
        .enabled(!this.busy)
        .onChange((v: string) => { this.user = v; })
      TextInput({ text: this.password, placeholder: '密码' })
        .type(InputType.Password)
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_TERTIARY)
        .backgroundColor(Theme.FIELD)
        .enabled(!this.busy)
        .onChange((v: string) => { this.password = v; })
      Text(this.credentialSaved
        ? '账号密码已加密保存在本机系统保险箱（仅本设备可用，不参与云同步）。'
        : '保存后，下次远程捕获会自动带上账号密码。密码只写入系统保险箱，不存普通文件。')
        .fontSize(Theme.FS_FOOT)
        .fontColor(Theme.TEXT_TERTIARY)
        .lineHeight(17)
        .width('100%')
      Row({ space: 10 }) {
        Button(this.credentialSaved ? '重新保存' : '保存账号密码')
          .enabled(!this.busy && this.user !== '' && this.password !== '')
          .backgroundColor(Theme.CHIP)
          .fontColor(Theme.TEXT_SECONDARY)
          .borderRadius(Theme.R_CONTROL)
          .onClick(() => { this.saveCredential(); })
        if (this.credentialSaved) {
          Button('清除已存账号')
            .enabled(!this.busy)
            .backgroundColor(Theme.CHIP)
            .fontColor(Theme.WARN)
            .borderRadius(Theme.R_CONTROL)
            .onClick(() => { this.forgetCredential(); })
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.FIELD)
    .borderRadius(Theme.R_CONTROL)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button('返回')
          .onClick(() => { router.back(); })
          .enabled(!this.busy)
          .backgroundColor(Theme.CHIP)
          .fontColor(Theme.TEXT_SECONDARY)
          .borderRadius(Theme.R_CONTROL)
        Text('远程保存')
          .fontSize(Theme.FS_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
      }
      .width('100%')

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 6 }) {
            Text('本次捕获')
              .fontSize(Theme.FS_FOOT)
              .fontColor(Theme.TEXT_TERTIARY)
              .width('100%')
            Text(this.captureText)
              .fontSize(Theme.FS_BODY)
              .fontColor(Theme.TEXT_PRIMARY)
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.FIELD)
          .borderRadius(Theme.R_CONTROL)
          .alignItems(HorizontalAlign.Start)

          if (this.vaults.length > 0) {
            Column({ space: 4 }) {
              Text('保存到')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.TEXT_TERTIARY)
                .width('100%')
              ForEach(this.vaults, (v: RemoteVault) => {
                Text((this.selected === v.id ? '✓  ' : '·  ') + v.name)
                  .fontSize(Theme.FS_BODY)
                  .fontColor(this.selected === v.id ? Theme.SUCCESS : Theme.TEXT_SECONDARY)
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                  .onClick(() => {
                    if (this.stage === 'new' || this.selected === v.id) { this.selected = v.id; }
                  })
              }, (v: RemoteVault) => v.id)
              if (this.targetPath !== '') {
                Text('目标：' + this.targetPath + (this.targetHeading !== '' ? ' › ' + this.targetHeading : ''))
                  .fontSize(Theme.FS_FOOT)
                  .fontColor(Theme.TEXT_TERTIARY)
                  .width('100%')
              }
            }
            .padding(16)
            .width('100%')
            .backgroundColor(Theme.FIELD)
            .borderRadius(Theme.R_CONTROL)
            .alignItems(HorizontalAlign.Start)
          }

          Text(this.status)
            .fontSize(Theme.FS_CAPTION)
            .fontColor(this.stage === 'done' ? Theme.SUCCESS : Theme.TEXT_SECONDARY)
            .width('100%')

          Button(this.stage === 'done' ? '完成' : this.busy ? '正在保存…' : '保存到远程库')
            .width('100%')
            .height(46)
            .backgroundColor(this.stage === 'done' ? Theme.CHIP : Theme.ACCENT_DEEP)
            .fontColor(this.stage === 'done' ? Theme.TEXT_PRIMARY : Color.White)
            .borderRadius(Theme.R_CONTROL)
            .enabled(!this.busy && (this.stage === 'done' ||
              (this.stage !== 'undone' && this.stage !== 'archived' && !this.stage.startsWith('undo'))))
            .onClick(() => {
              if (this.stage === 'done') { this.finish(); } else { this.save(); }
            })

          Row({ space: 10 }) {
            Button('重试连接')
              .enabled(!this.busy)
              .backgroundColor(Theme.CHIP)
              .fontColor(Theme.TEXT_SECONDARY)
              .borderRadius(Theme.R_CONTROL)
              .onClick(() => { this.connect(); })
            Button(this.showLogin ? '收起网页登录' : '网页登录')
              .enabled(!this.busy)
              .backgroundColor(Theme.CHIP)
              .fontColor(Theme.TEXT_SECONDARY)
              .borderRadius(Theme.R_CONTROL)
              .onClick(() => { this.showLogin = !this.showLogin; })
            Button(this.showAdvanced ? '收起设置' : '设置')
              .enabled(!this.busy)
              .backgroundColor(Theme.CHIP)
              .fontColor(Theme.TEXT_TERTIARY)
              .borderRadius(Theme.R_CONTROL)
              .onClick(() => { this.showAdvanced = !this.showAdvanced; })
          }
          .width('100%')

          if (this.showAdvanced) {
            this.credentialFields()
          }

          if (this.showLogin) {
            Text('在下面完成服务器登录（表单 / SSO），然后点「重试连接」。这个页面不会收到上面填写的账号密码。')
              .fontSize(Theme.FS_FOOT)
              .fontColor(Theme.TEXT_TERTIARY)
              .lineHeight(17)
              .width('100%')
            Web({ src: this.op !== undefined ? this.op.serverURL + '/' : 'about:blank', controller: this.loginController })
              .height(320)
              .width('100%')
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .backgroundColor(Theme.CARD_SOLID)
              .onHttpAuthRequest((event: OnHttpAuthRequestEvent) => {
                // 只向配置的服务器回 Basic/Digest 凭据；其他主机一律不提供。
                const base = this.op !== undefined ? this.op.serverURL : '';
                const sameHost = base !== '' && base.toLowerCase().indexOf(event.host.toLowerCase()) >= 0;
                if (sameHost && this.user !== '' && this.password !== '') {
                  event.handler.confirm(this.user, this.password);
                  return true;
                }
                event.handler.cancel();
                return false;
              })
          }

          if (this.stage === 'done' || this.stage.startsWith('undo')) {
            Button('撤销本次保存')
              .width('100%')
              .height(40)
              .backgroundColor(Theme.CHIP)
              .fontColor(Theme.WARN)
              .borderRadius(Theme.R_CONTROL)
              .enabled(!this.busy)
              .onClick(() => {
                AlertDialog.show({
                  title: '撤销本次远程保存？',
                  message: '会删除本次条目；如果笔记之后被修改过，将拒绝操作以免覆盖。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '确认撤销', action: () => { this.undo(); } }
                });
              })
          }

          if (this.stage !== 'done' && this.stage !== 'archived' && this.stage !== 'undone') {
            Button('稍后再存')
              .width('100%')
              .height(40)
              .backgroundColor(Theme.CHIP)
              .fontColor(Theme.TEXT_SECONDARY)
              .borderRadius(Theme.R_CONTROL)
              .enabled(!this.busy)
              .onClick(() => { this.keepForLater(); })
          }

          if (this.queued.length > 0) {
            Column({ space: 4 }) {
              Text('另有未处理的捕获')
                .fontSize(Theme.FS_FOOT)
                .fontColor(Theme.TEXT_TERTIARY)
                .width('100%')
              ForEach(this.queued, (draft: RemoteCaptureQueued) => {
                Text('· ' + draft.operation.text.substring(0, 30))
                  .fontSize(Theme.FS_CAPTION)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                  .onClick(() => { this.activateDraft(draft.filename); })
              }, (draft: RemoteCaptureQueued) => draft.filename)
            }
            .padding(16)
            .width('100%')
            .backgroundColor(Theme.FIELD)
            .borderRadius(Theme.R_CONTROL)
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.CARD_SOLID)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
