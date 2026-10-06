// 伺服器模式主页（VIP）：把手机变成家里的笔记伺服器
// 与本地模式悬浮球开关的区别：这里开关持久（srvModeEnabled，冷启动自动恢复直达本页）；
// 悬浮球开关会话级，App 退出即失效。两入口共用同一 serverB（管理 API 幂等）。
// 底层：NodeTest 启动链起 Node（serverA 127.0.0.1:6791）→ 本页 fetch 管理 API 起 serverB。
// 安全：Digest 挑战应答（密码不上线）+ 失败锁定 + 随机高位端口 + 仅 Wi-Fi 开放。
import { router } from '@kit.ArkUI';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackButton } from '../components/BackButton';
import { SignalRippleBackground } from '../components/AmbientBackground';
import { hapticLight, hapticSuccess } from '../common/Haptics';
import { VipService } from '../common/VipService';
import { SrvSafetyDialog } from '../common/SrvSafetyDialog';
import { LanShareApi, LanShareStatus } from '../common/LanShareApi';
import { requestAppPermissionsOnce } from '../common/AppPermissions';

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
  @State private credGlow: boolean = false; // 首次引导：凭证卡高亮提示
  @State private srvSafetyShow: boolean = false; // 凭证保存前的安全提示弹窗
  // 响应式会员状态：AppStorage 一变（购买/restore 写入）自动重绘——修"买完返回本页小字不刷新"
  @StorageProp('vipPermanent') private permWatch: boolean = false;
  @StorageProp('vipUntil') private untilWatch: number = 0;
  @State private busy: boolean = false;
  @State private pollTimer: number = -1;
  @State private tlsOn: boolean = false; // 加密连接（HTTPS 自签证书）偏好
  @State private fingerprint: string = ''; // 运行中证书指纹（供浏览器首次放行时比对）
  @State private runTls: boolean = false; // serverB 实际运行的档位（地址协议以它为准，而非偏好）

  aboutToAppear() {
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    PersistentStorage.persistProp('srvModeEnabled', false);
    PersistentStorage.persistProp('lanSharePort', 0); // 端口持久：重启后固定，家人书签不失效
    PersistentStorage.persistProp('lanShareTls', false);
    this.tlsOn = LanShareApi.tlsPreferred();
    this.savedUser = AppStorage.get<string>('lanShareUser') ?? '';
    this.lanIp = LanShareApi.getLanIp();
    this.refreshStatus();
    this.startPoll();
  }

  // 轻量巡检：路由器重分配 IP / serverB 异常时状态如实呈现（后台停表省电，回页幂等重启）
  private startPoll(): void {
    if (this.pollTimer !== -1) {
      return;
    }
    this.pollTimer = setInterval(() => {
      if (!this.busy) {
        this.lanIp = LanShareApi.getLanIp();
        this.refreshStatus();
      }
    }, 5000);
  }

  private stopPoll(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  onPageShow() {
    // 自动续开仅限"点开关→被拦去购买→买成返回"这条链（标志消费制）：
    // 原条件 VIP+有凭证+未运行 会让任何进入本页都自动开伺服器（用户手动关了却自己亮=状态鬼魅）
    const pending = AppStorage.get<boolean>('vipPendingEnable') === true;
    AppStorage.setOrCreate('vipPendingEnable', false); // 消费即清，一次生效
    if (pending && VipService.isVip() && !this.running && !this.busy) {
      const user = AppStorage.get<string>('lanShareUser') ?? '';
      const pass = AppStorage.get<string>('lanSharePass') ?? '';
      if (user !== '' && pass !== '') {
        this.doEnable(user, pass);
        return;
      }
    }
    this.refreshStatus();
    this.startPoll(); // 回页恢复巡检（onHide 已停表，幂等）
  }

  onPageHide() {
    this.stopPoll(); // 后台停巡检：进全屏 Web/锁屏时 UI 轮询无意义，省电
  }

  aboutToDisappear() {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private refreshStatus(): void {
    LanShareApi.status().then((st: LanShareStatus | null) => {
      if (st !== null) {
        this.running = st.running;
        this.port = st.port;
        this.fingerprint = st.tls === true ? st.fingerprint : '';
        this.runTls = st.tls === true;
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

  private fullAddr(): string {
    return LanShareApi.scheme(this.runTls) + this.lanIp + ':' + this.port;
  }

  // 指纹分两行展示（32 组十六进制，一行放不下）
  private fingerprintLines(): string[] {
    const parts: string[] = this.fingerprint.split(':');
    if (parts.length < 32) {
      return [this.fingerprint];
    }
    return [parts.slice(0, 16).join(':'), parts.slice(16).join(':')];
  }

  // 加密连接开关：运行中立即以新档位重启 serverB（地址协议随之变化，需告知用户）
  private onTlsToggle(on: boolean): void {
    if (this.busy) {
      return;
    }
    hapticLight();
    AppStorage.setOrCreate('lanShareTls', on);
    this.tlsOn = on;
    if (!this.running) {
      return;
    }
    const user = AppStorage.get<string>('lanShareUser') ?? '';
    const pass = AppStorage.get<string>('lanSharePass') ?? '';
    if (user !== '' && pass !== '') {
      this.getUIContext().getPromptAction().showToast({
        message: on ? '已切换为加密连接，请用新的 https 地址访问' : '已切换为普通连接，请用新的 http 地址访问',
        duration: 2600
      });
      this.doEnable(user, pass);
    }
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
    // VIP 门禁：非会员去购买页，并立续开标志（买成返回时 onPageShow 完成开伺服器的原始意图）
    if (!VipService.isVip()) {
      hapticLight();
      AppStorage.setOrCreate('vipPendingEnable', true);
      router.pushUrl({ url: 'pages/VipPanelPage' });
      return;
    }
    const user = AppStorage.get<string>('lanShareUser') ?? '';
    const pass = AppStorage.get<string>('lanSharePass') ?? '';
    if (user === '' || pass === '') {
      // 首次引导：开关按下无凭证时明确告知下一步（不再静默展开表单让用户懵）
      this.getUIContext().getPromptAction().showToast({ message: '首次使用：请在下方设置访问账号密码，保存后自动开启', duration: 3000 });
      this.inputUser = this.savedUser;
      this.inputPass = '';
      this.credGlow = true;
      this.showCredForm = true;
      return;
    }
    this.doEnable(user, pass);
  }

  private doEnable(user: string, pass: string): void {
    // VIP 门禁（逻辑层自证，2026-09-01 实测白嫖根因：门禁只在 tryEnable，表单保存/自动恢复/续开链直调本函数全部绕过）
    // 所有开启路径唯一闸口——UI 层引导在 tryEnable/saveCredAndEnable，安全在这里
    if (!VipService.isVip()) {
      AppStorage.setOrCreate('srvModeEnabled', false); // 开关降级：防过期用户巡检反复尝试自动恢复
      return;
    }
    if (this.lanIp === '') {
      this.getUIContext().getPromptAction().showToast({ message: '未检测到局域网：请连接 Wi-Fi，或开启移动热点共享给设备', duration: 2500 });
      return;
    }
    // 权限时机：伺服器模式不进 ArkWeb（网页 onPageEnd 不会触发），首次开启时在此索要
    requestAppPermissionsOnce(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.busy = true;
    const persistPort: number = AppStorage.get<number>('lanSharePort') ?? 0;
    LanShareApi.enable(user, pass, persistPort).then((st: LanShareStatus | null) => {
      this.busy = false;
      if (st === null || !st.running) {
        this.getUIContext().getPromptAction().showToast({ message: '开启失败，请重试', duration: 2000 });
        return;
      }
      this.running = true;
      this.port = st.port;
      this.fingerprint = st.tls === true ? st.fingerprint : '';
      this.runTls = st.tls === true;
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
    LanShareApi.disable().then((st: LanShareStatus | null) => {
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
    // 安全提示前置：每次保存凭证都弹（HTTP 明文传输的知情确认）
    this.srvSafetyShow = true;
  }

  private confirmSaveCred(): void {
    AppStorage.setOrCreate('lanShareUser', this.inputUser);
    AppStorage.setOrCreate('lanSharePass', this.inputPass);
    this.savedUser = this.inputUser;
    this.credGlow = false; // 凭证落定，引导高亮熄灭
    // 非 VIP：凭证先存（买完会员回来自动续开），引导去购买页——2026-09-01 白嫖路径封堵
    if (!VipService.isVip()) {
      hapticLight();
      AppStorage.setOrCreate('vipPendingEnable', true);
      this.getUIContext().getPromptAction().showToast({ message: '凭证已保存，开通会员后自动开启伺服器', duration: 2600 });
      router.pushUrl({ url: 'pages/VipPanelPage' });
      return;
    }
    this.doEnable(this.inputUser, this.inputPass);
  }

  private copyAddr(): void {
    if (this.lanIp === '' || this.port === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.fullAddr());
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      hapticSuccess();
      this.getUIContext().getPromptAction().showToast({ message: '已复制访问地址', duration: 2000 });
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

      // 专属动态背景：信号波纹（伺服器广播语义，区别于主页波浪/登录粒子/验证星野/终端符号雨）
      SignalRippleBackground({ visible: true })

      Scroll() {
        Column({ space: 16 }) {
          Text('伺服器模式')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ top: 96 })

          // ── 会员入口（绑定 @StorageProp 响应式：购买/恢复写入瞬间自动刷新）──
          Row({ space: 8 }) {
            Text(this.permWatch
              ? '永久会员'
              : (this.untilWatch > Date.now()                ? '会员生效中'
                : '开通会员解锁伺服器模式'))
              .fontSize(13)
              .fontColor(this.permWatch || this.untilWatch > Date.now() ? '#9BE8B4' : '#8F9BD8')
            Text('›')
              .fontSize(15)
              .fontColor('#6A74A8')
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('rgba(255,255,255,0.04)')
          .borderRadius(12)
          .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
          .onClick(() => {
            hapticLight();
            router.pushUrl({ url: 'pages/VipPanelPage' });
          })

          // ── 状态大卡 ──
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Circle({ width: 12, height: 12 })
                .fill(this.running ? '#9BE8B4' : '#5A649E')
                .shadow(this.running ? { radius: 10, color: '#9BE8B4AA' } : { radius: 0, color: 'transparent' })
              Text(this.running ? '伺服器运行中' : '伺服器已停止')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.running ? '#E2E6F8' : '#8F9BD8')
            }

            // 自绘受控开关（系统Toggle点击即视觉切换，拒绝开启后无法回弹 → 假开状态）
            Row() {
              Circle({ width: 30, height: 30 })
                .fill('#FFFFFF')
                .margin({ left: this.running ? 40 : 5 })
                .shadow({ radius: 6, color: '#00000055', offsetY: 2 })
                .animation({ duration: 200, curve: Curve.EaseOut })
            }
            .width(74)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.running ? '#5F6BD8' : '#3A4078')
            .linearGradient(this.running ? { angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] } : { angle: 90, colors: [['#3A4078', 0], ['#3A4078', 1]] })
            .shadow(this.running ? { radius: 14, color: '#5F6BD844', offsetY: 4 } : { radius: 0, color: 'transparent' })
            .onClick(() => {
              this.onToggle(!this.running);
            })

            if (this.running) {
              Column({ space: 8 }) {
                Text('局域网设备浏览器输入')
                  .fontSize(12)
                  .fontColor('#8F9BD8')
                Text(this.lanIp !== '' && this.port > 0 ? this.fullAddr() : '获取 IP 失败（请连接 Wi-Fi 或开启移动热点）')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9BE8B4')
                  .letterSpacing(0.6)
                Button('一键复制地址')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                  .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                  .borderRadius(16)
                  .height(38)
                  .padding({ left: 24, right: 24 })
                  .shadow({ radius: 10, color: '#5F6BD844', offsetY: 4 })
                  .enabled(this.lanIp !== '' && this.port > 0)
                  .onClick(() => { this.copyAddr(); })
              }
              .width('100%')
              .padding({ top: 14 })
            }
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 24, bottom: 24 })
          .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: 1, color: this.running ? '#4A5498' : 'rgba(255,255,255,0.32)' })
          .alignItems(HorizontalAlign.Center)

          // ── 加密连接（单向 TLS，自签证书）──
          Column({ space: 10 }) {
            Row() {
              Column({ space: 3 }) {
                Text('加密连接（HTTPS）')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E2E6F8')
                Text(this.tlsOn ? '传输全程加密，同一 Wi-Fi 下的人无法偷看内容' : '默认关闭：家庭 Wi-Fi 足够；在公共或不信任的网络请开启')
                  .fontSize(12)
                  .fontColor('#8F9BD8')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Row() {
                Circle({ width: 22, height: 22 })
                  .fill('#FFFFFF')
                  .margin({ left: this.tlsOn ? 25 : 3 })
                  .shadow({ radius: 4, color: '#00000055', offsetY: 1 })
                  .animation({ duration: 180, curve: Curve.EaseOut })
              }
              .width(50)
              .height(28)
              .borderRadius(14)
              .backgroundColor(this.tlsOn ? '#5F6BD8' : '#3A4078')
              .onClick(() => { this.onTlsToggle(!this.tlsOn); })
            }
            .width('100%')

            if (this.tlsOn) {
              Text('首次用浏览器打开会提示“连接不安全 / 证书无效”——这是自签证书的正常现象，不是被攻击。点“高级”→“继续访问”即可（iPhone/iPad 的 Safari 选“显示详细信息”→“访问此网站”）。')
                .fontSize(11)
                .fontColor('#8F9BD8')
                .lineHeight(16)
              if (this.running && this.fingerprint !== '') {
                Text('证书指纹（SHA-256，可与浏览器证书详情比对）')
                  .fontSize(11)
                  .fontColor('#6A74A8')
                  .margin({ top: 2 })
                ForEach(this.fingerprintLines(), (line: string) => {
                  Text(line)
                    .fontSize(10)
                    .fontColor('#B8C0E4')
                    .fontFamily('monospace')
                }, (line: string) => line)
              }
            }
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 16, bottom: 16 })
          .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: 1, color: this.tlsOn ? '#4A5498' : 'rgba(255,255,255,0.32)' })
          .alignItems(HorizontalAlign.Start)

          // ── 账密区 ──
          Column({ space: 10 }) {
            Text(this.credGlow ? '① 首次使用：设置访问凭证（保存后自动开启）' : '访问凭证')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.credGlow ? '#9BB4FF' : '#E2E6F8')
            if (!this.showCredForm) {
              Text(this.savedUser !== '' ? '账号：' + this.savedUser + ' · Digest 加密（密码不上线）' : '尚未设置')
                .fontSize(12)
                .fontColor('#8F9BD8')
              Button(this.savedUser !== '' ? '修改账号密码' : '设置账号密码')
                .fontSize(13)
                .fontColor('#B8C0E4')
                .backgroundColor('rgba(255,255,255,0.04)')
                .borderRadius(16)
                .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
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
                .placeholderColor('#8F9BD8')
                .backgroundColor('rgba(255,255,255,0.04)')
                .borderRadius(10)
              TextInput({ placeholder: '密码（至少 4 位）', text: this.inputPass })
                .type(InputType.Password)
                .onChange((v: string) => { this.inputPass = v; })
                .width('100%')
                .height(44)
                .fontColor('#E2E6F8')
                .placeholderColor('#8F9BD8')
                .backgroundColor('rgba(255,255,255,0.04)')
                .borderRadius(10)
              Row({ space: 10 }) {
                Button('取消')
                  .fontSize(13)
                  .fontColor('#8F9BD8')
                  .backgroundColor('rgba(255,255,255,0.04)')
                  .borderRadius(16)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => { this.showCredForm = false; })
                Button('保存' + (this.running ? '并重启伺服器' : '并开启'))
                  .fontSize(13)
                  .fontColor('#FFFFFF')
                  .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                  .borderRadius(16)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => { this.saveCredAndEnable(); })
              }
              .width('100%')
            }
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 18, bottom: 18 })
          .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: this.credGlow ? 1.5 : 1, color: this.credGlow ? '#7A88E8' : 'rgba(255,255,255,0.32)' })
          .alignItems(HorizontalAlign.Start)
          Button('去本地编辑笔记')
            .fontSize(14)
            .fontColor('#B8C0E4')
            .backgroundColor('rgba(255,255,255,0.04)')
            .borderRadius(16)
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
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
            Text(this.tlsOn ? '✓ 已启用 HTTPS 加密传输（自签证书，首次访问需手动放行）' : '· 内网 HTTP 传输，建议家庭可信网络使用；不信任的网络请开启加密连接')
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

      // 凭证保存安全提示（遮罩层，样式同 Splash 免责声明）
      SrvSafetyDialog({
        show: this.srvSafetyShow,
        onConfirm: () => {
          this.srvSafetyShow = false;
          this.confirmSaveCred();
        }
      })
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
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
  }
}
