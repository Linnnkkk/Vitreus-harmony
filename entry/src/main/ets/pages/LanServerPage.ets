// 伺服器模式主页（VIP）：把手机变成家里的笔记伺服器
// 与本地模式悬浮球开关的区别：这里开关持久（srvModeEnabled，冷启动自动恢复直达本页）；
// 悬浮球开关会话级，App 退出即失效。两入口共用同一 serverB（管理 API 幂等）。
// 底层：NodeTest 启动链起 Node（serverA 127.0.0.1:6791）→ 本页 fetch 管理 API 起 serverB。
// 安全：Digest 挑战应答（密码不上线）+ 失败锁定 + 随机高位端口 + 仅 Wi-Fi 开放。
import { router } from '@kit.ArkUI';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { http } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackButton } from '../components/BackButton';
import { hapticLight, hapticSuccess } from '../common/Haptics';
import { VipService } from '../common/VipService';

interface LanShareStatus {
  running: boolean;
  port: number;
  since: number;
  user: string;
}

// 管理API请求体（ArkTS：字面量必须对应显式interface）
interface LanShareApiBody {
  action: string;
  user?: string;
  pass?: string;
  port?: number;
}

@Entry
@Component
struct LanServerPage {
  @State private running: boolean = false;
  @State private port: number = 0;
  @State private lanIp: string = '';
  @State private savedUser: string = '';
  @State private inputUser: string = '';
  @State private inputPass: string = '';
  @State private showCredForm: boolean = false;
  @State private busy: boolean = false;
  @State private pollTimer: number = -1;

  aboutToAppear() {
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    PersistentStorage.persistProp('srvModeEnabled', false);
    PersistentStorage.persistProp('lanSharePort', 0); // 端口持久：重启后固定，家人书签不失效
    this.savedUser = AppStorage.get<string>('lanShareUser') ?? '';
    this.lanIp = this.getLanIp();
    this.refreshStatus();
    // 轻量巡检：路由器重分配 IP / serverB 异常时状态如实呈现
    this.pollTimer = setInterval(() => {
      if (!this.busy) {
        this.lanIp = this.getLanIp();
        this.refreshStatus();
      }
    }, 5000);
  }

  onPageShow() {
    // 从购买页返回（购买成功）自动续开——完成用户点开关时的原始意图
    if (VipService.isVip() && !this.running && !this.busy) {
      const user = AppStorage.get<string>('lanShareUser') ?? '';
      const pass = AppStorage.get<string>('lanSharePass') ?? '';
      if (user !== '' && pass !== '') {
        this.doEnable(user, pass);
      }
    } else {
      this.refreshStatus();
    }
  }

  aboutToDisappear() {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // ── 管理API（仅回环，server 侧 lan-share.js）──
  private apiCall(body: LanShareApiBody | null): Promise<LanShareStatus | null> {
    return new Promise<LanShareStatus | null>((resolve) => {
      const client = http.createHttp();
      const opts: http.HttpRequestOptions = {
        method: body === null ? http.RequestMethod.GET : http.RequestMethod.POST,
        connectTimeout: 3000,
        readTimeout: 6000,
        expectDataType: http.HttpDataType.STRING
      };
      if (body !== null) {
        opts.header = { 'Content-Type': 'application/json' } as Record<string, string>;
        opts.extraData = JSON.stringify(body);
      }
      client.request('http://127.0.0.1:6791/api/admin/lan-share', opts,
        (err: BusinessError, resp: http.HttpResponse) => {
          client.destroy();
          if (err !== undefined && err !== null || resp.responseCode !== 200) {
            resolve(null);
            return;
          }
          try {
            resolve(JSON.parse(resp.result as string) as LanShareStatus);
          } catch (e) {
            resolve(null);
          }
        });
    });
  }

  private refreshStatus(): void {
    this.apiCall(null).then((st: LanShareStatus | null) => {
      if (st !== null) {
        this.running = st.running;
        this.port = st.port;
        AppStorage.setOrCreate('srvRunning', st.running);
        // 冷启动自动恢复：持久开关开着但 serverB 未跑（Node 刚起/进程曾被杀）
        const persistOn = AppStorage.get<boolean>('srvModeEnabled') === true;
        const user = AppStorage.get<string>('lanShareUser') ?? '';
        const pass = AppStorage.get<string>('lanSharePass') ?? '';
        if (!st.running && persistOn && user !== '' && pass !== '' && !this.busy) {
          this.doEnable(user, pass);
        }
      }
    });
  }

  // Wi-Fi 本机 IP（wifiManager.getIpInfo 返回整数，转点分；无 Wi-Fi 返回空）
  private getLanIp(): string {
    try {
      const n = wifiManager.getIpInfo().ipAddress >>> 0;
      if (n === 0) {
        return '';
      }
      return ((n >>> 24) & 0xff) + '.' + ((n >>> 16) & 0xff) + '.' + ((n >>> 8) & 0xff) + '.' + (n & 0xff);
    } catch (e) {
      return '';
    }
  }

  private fullAddr(): string {
    return 'http://' + this.lanIp + ':' + this.port;
  }

  // ── 开关 ──
  private onToggle(on: boolean): void {
    if (this.busy) {
      return;
    }
    if (on) {
      this.tryEnable();
    } else {
      this.doDisable();
    }
  }

  private tryEnable(): void {
    // VIP 门禁（Mock 通道，IAP 签约后切真校验）
    if (!VipService.isVip()) {
      hapticLight();
      router.pushUrl({ url: 'pages/VipPanelPage' });
      return;
    }
    const user = AppStorage.get<string>('lanShareUser') ?? '';
    const pass = AppStorage.get<string>('lanSharePass') ?? '';
    if (user === '' || pass === '') {
      // 首次：面板内嵌账密设置
      this.showCredForm = true;
      return;
    }
    this.doEnable(user, pass);
  }

  private doEnable(user: string, pass: string): void {
    if (this.lanIp === '') {
      this.getUIContext().getPromptAction().showToast({ message: '未检测到 Wi-Fi，请先连接家庭网络', duration: 2500 });
      return;
    }
    this.busy = true;
    const persistPort: number = AppStorage.get<number>('lanSharePort') ?? 0;
    this.apiCall({ action: 'enable', user: user, pass: pass, port: persistPort }).then((st: LanShareStatus | null) => {
      this.busy = false;
      if (st === null || !st.running) {
        this.getUIContext().getPromptAction().showToast({ message: '开启失败，请重试', duration: 2000 });
        return;
      }
      this.running = true;
      this.port = st.port;
      AppStorage.setOrCreate('lanSharePort', st.port); // 端口持久：重启后固定，家人书签不失效
      AppStorage.setOrCreate('srvModeEnabled', true);
      AppStorage.setOrCreate('srvRunning', true);
      this.showCredForm = false;
      this.startKeepAlive();
      hapticSuccess();
    });
  }

  private doDisable(): void {
    this.busy = true;
    this.apiCall({ action: 'disable' }).then((st: LanShareStatus | null) => {
      this.busy = false;
      this.running = false;
      AppStorage.setOrCreate('srvModeEnabled', false);
      AppStorage.setOrCreate('srvRunning', false);
      this.stopKeepAlive();
      hapticLight();
    });
  }

  // DATA_TRANSFER 长时任务：熄屏锁屏持续运行（不开不耗电）
  private async startKeepAlive(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
    } catch (e) {
      const err = e as BusinessError;
      console.error('[lan-server] keepalive failed: ' + err.code + ' ' + err.message);
    }
  }

  private async stopKeepAlive(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await backgroundTaskManager.stopBackgroundRunning(ctx);
    } catch (e) {
      // 已停/系统回收时静默
    }
  }

  private saveCredAndEnable(): void {
    if (this.inputUser === '' || this.inputPass.length < 4) {
      this.getUIContext().getPromptAction().showToast({ message: '账号必填，密码至少 4 位', duration: 2000 });
      return;
    }
    AppStorage.setOrCreate('lanShareUser', this.inputUser);
    AppStorage.setOrCreate('lanSharePass', this.inputPass);
    this.savedUser = this.inputUser;
    this.doEnable(this.inputUser, this.inputPass);
  }

  private copyAddr(): void {
    if (this.lanIp === '' || this.port === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.fullAddr());
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      hapticSuccess();
      this.getUIContext().getPromptAction().showToast({ message: '已复制，发给家人即可', duration: 2000 });
    });
  }

  private goLocal(): void {
    hapticLight();
    AppStorage.setOrCreate('appMode', 'local');
    // 显式重置 bootMode，否则 NodeTest ready 后按残留的 'srv' 又弹回本页
    AppStorage.setOrCreate('bootMode', 'local');
    router.pushUrl({ url: 'pages/NodeTest' });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 160, colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]] })

      Scroll() {
        Column({ space: 16 }) {
          Text('伺服器模式')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ top: 96 })

          // ── 状态大卡 ──
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Circle({ width: 12, height: 12 })
                .fill(this.running ? '#9BE8B4' : '#5A649E')
              Text(this.running ? '伺服器运行中' : '伺服器已停止')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.running ? '#E2E6F8' : '#8F9BD8')
            }

            Toggle({ type: ToggleType.Switch, isOn: this.running })
              .selectedColor('#5F6BD8')
              .switchPointColor('#FFFFFF')
              .onChange((on: boolean) => this.onToggle(on))

            if (this.running) {
              Column({ space: 8 }) {
                Text('家人设备浏览器输入')
                  .fontSize(12)
                  .fontColor('#8F9BD8')
                Text(this.lanIp !== '' && this.port > 0 ? this.fullAddr() : '获取 IP 失败（是否已连 Wi-Fi？）')
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9BE8B4')
                Button('一键复制地址')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#5F6BD8')
                  .borderRadius(14)
                  .height(36)
                  .padding({ left: 20, right: 20 })
                  .enabled(this.lanIp !== '' && this.port > 0)
                  .onClick(() => { this.copyAddr(); })
              }
              .width('100%')
              .padding({ top: 14 })
            }
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 24, bottom: 24 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: this.running ? '#4A5498' : '#3A4078' })
          .alignItems(HorizontalAlign.Center)

          // ── 账密区 ──
          Column({ space: 10 }) {
            Text('访问凭证')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E2E6F8')
            if (!this.showCredForm) {
              Text(this.savedUser !== '' ? '账号：' + this.savedUser + ' · Digest 加密（密码不上线）' : '尚未设置')
                .fontSize(12)
                .fontColor('#8F9BD8')
              Button(this.savedUser !== '' ? '修改账号密码' : '设置账号密码')
                .fontSize(13)
                .fontColor('#B8C0E4')
                .backgroundColor('#161A3E')
                .borderRadius(12)
                .border({ width: 1, color: '#2A2E5E' })
                .height(34)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  hapticLight();
                  this.inputUser = this.savedUser;
                  this.inputPass = '';
                  this.showCredForm = true;
                })
            } else {
              TextInput({ placeholder: '账号', text: this.inputUser })
                .onChange((v: string) => { this.inputUser = v; })
                .width('100%')
                .height(44)
                .fontColor('#E2E6F8')
                .backgroundColor('#161A3E')
                .borderRadius(10)
              TextInput({ placeholder: '密码（至少 4 位）', text: this.inputPass })
                .type(InputType.Password)
                .onChange((v: string) => { this.inputPass = v; })
                .width('100%')
                .height(44)
                .fontColor('#E2E6F8')
                .backgroundColor('#161A3E')
                .borderRadius(10)
              Row({ space: 10 }) {
                Button('取消')
                  .fontSize(13)
                  .fontColor('#8F9BD8')
                  .backgroundColor('#161A3E')
                  .borderRadius(10)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => { this.showCredForm = false; })
                Button('保存' + (this.running ? '并重启伺服器' : '并开启'))
                  .fontSize(13)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#5F6BD8')
                  .borderRadius(10)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => { this.saveCredAndEnable(); })
              }
              .width('100%')
            }
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 18, bottom: 18 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: '#3A4078' })
          .alignItems(HorizontalAlign.Start)

          // ── 本地编辑入口（共用同一 Node，互不打扰）──
          Button('去本地编辑笔记')
            .fontSize(14)
            .fontColor('#B8C0E4')
            .backgroundColor('#161A3E')
            .borderRadius(14)
            .border({ width: 1, color: '#2A2E5E' })
            .height(40)
            .padding({ left: 22, right: 22 })
            .onClick(() => { this.goLocal(); })

          // ── 信任脚注 ──
          Column({ space: 5 }) {
            Text('✓ 熄屏锁屏持续运行 · 开关持久（下次打开 App 自动恢复）')
              .fontSize(11)
              .fontColor('#6A74A8')
            Text('✓ Digest 挑战应答（密码不上线）· 失败锁定 · 随机端口')
              .fontSize(11)
              .fontColor('#6A74A8')
            Text('· 内网 HTTP 传输，建议家庭可信网络使用')
              .fontSize(11)
              .fontColor('#6A74A8')
          }
          .width('86%')
          .margin({ top: 4, bottom: 40 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  onBackPress(): boolean {
    // 伺服器运行中返回首页继续跑（长时任务保活），不弹退出确认
    return false;
  }

  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 200, curve: Curve.EaseOut })
      .translate({ x: 320 })
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
      .opacity(0)
  }
}
