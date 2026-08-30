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
  // 响应式会员状态：AppStorage 一变（购买/restore 写入）自动重绘——修"买完返回本页小字不刷新"
  @StorageProp('vipPermanent') private permWatch: boolean = false;
  @StorageProp('vipUntil') private untilWatch: number = 0;
  @State private busy: boolean = false;
  @State private pollTimer: number = -1;

  aboutToAppear() {
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    PersistentStorage.persistProp('srvModeEnabled', false);
    PersistentStorage.persistProp('lanSharePort', 0); // 端口持久：重启后固定，家人书签不失效
    this.savedUser = AppStorage.get<string>('lanShareUser') ?? '';
    this.lanIp = LanShareApi.getLanIp();
    this.refreshStatus();
    // 轻量巡检：路由器重分配 IP / serverB 异常时状态如实呈现
    this.pollTimer = setInterval(() => {
      if (!this.busy) {
        this.lanIp = LanShareApi.getLanIp();
        this.refreshStatus();
      }
    }, 5000);
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
    if (this.lanIp === '') {
      this.getUIContext().getPromptAction().showToast({ message: '未检测到 Wi-Fi，请先连接家庭网络', duration: 2500 });
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
    AppStorage.setOrCreate('lanShareUser', this.inputUser);
    AppStorage.setOrCreate('lanSharePass', this.inputPass);
    this.savedUser = this.inputUser;
    this.credGlow = false; // 凭证落定，引导高亮熄灭
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
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(12)
          .border({ width: 1, color: '#3A4078' })
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
                Text(this.lanIp !== '' && this.port > 0 ? this.fullAddr() : '获取 IP 失败（是否已连 Wi-Fi？）')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9BE8B4')
                  .letterSpacing(0.6)
                Button('一键复制地址')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#5F6BD8')
                  .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
                  .borderRadius(18)
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
          .backgroundEffect({ radius: 45, saturation: 1.2, brightness: 1.15, color: 'rgba(255,255,255,0.12)' })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: 1, color: this.running ? '#4A5498' : '#3A4078' })
          .alignItems(HorizontalAlign.Center)

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
                .backgroundColor('rgba(255,255,255,0.06)')
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
                .placeholderColor('#8F9BD8')
                .backgroundColor('rgba(255,255,255,0.06)')
                .borderRadius(10)
              TextInput({ placeholder: '密码（至少 4 位）', text: this.inputPass })
                .type(InputType.Password)
                .onChange((v: string) => { this.inputPass = v; })
                .width('100%')
                .height(44)
                .fontColor('#E2E6F8')
                .placeholderColor('#8F9BD8')
                .backgroundColor('rgba(255,255,255,0.06)')
                .borderRadius(10)
              Row({ space: 10 }) {
                Button('取消')
                  .fontSize(13)
                  .fontColor('#8F9BD8')
                  .backgroundColor('rgba(255,255,255,0.06)')
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
          .backgroundEffect({ radius: 45, saturation: 1.2, brightness: 1.15, color: 'rgba(255,255,255,0.12)' })
          .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
          .shadow({ radius: 22, color: 'rgba(0,0,0,0.35)', offsetY: 6 })
          .borderRadius(18)
          .border({ width: this.credGlow ? 1.5 : 1, color: this.credGlow ? '#7A88E8' : '#3A4078' })
          .alignItems(HorizontalAlign.Start)
          Button('去本地编辑笔记')
            .fontSize(14)
            .fontColor('#B8C0E4')
            .backgroundColor('rgba(255,255,255,0.06)')
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
