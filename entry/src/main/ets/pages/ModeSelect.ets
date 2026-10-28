import { ServiceSwitch } from '../components/ServiceSwitch';
import { router } from '@kit.ArkUI';
import { hapticLight, hapticSelect } from '../common/Haptics';
import { WaveBackground } from '../components/WaveBackground';
import { WebDavSettings } from '../common/WebDavSettings';
import { UpdateNoticeDialog, UPDATE_NOTICE_ID } from '../components/UpdateNotice';
import { NoticeState } from '../common/NoticeState';
import { common } from '@kit.AbilityKit';
import { VipService } from '../common/VipService';
import { Theme } from '../common/Theme';
import { HomeServiceControl } from '../common/HomeServiceControl';
import { LanShareApi } from '../common/LanShareApi';
import { AiLanApi } from '../common/AiLanApi';
import { StartupPreferences } from '../common/StartupPreferences';

// 主页：突出打开笔记，服务器入口和设备连接按使用目的分层。设计语言：
//   底色深靛蓝渐变 + 玻璃卡片（半透明白描边）+ 无 emoji（SymbolGlyph 图标）
@Entry
@Component
struct ModeSelect {
  // 入场 stagger：标题→卡片→文字链 依次浮现（40ms 间隔起步）
  // 背景动效联通：页面隐藏停表
  @State private bgVisible: boolean = true;
  @State private t1: boolean = false;
  @State private t2: boolean = false;
  @State private t3: boolean = false;
  // 卡片按压反馈（spring 物理曲线）
  @State private pressedLocal: boolean = false;
  @StorageLink('aiRunning') private aiRunning: boolean = false;
  // 伺服器运行状态点（LanServerPage 回写）
  @StorageLink('srvRunning') private srvRunning: boolean = false;
  // 点击选中强调：亮边框+微放大，亮完再跳（点击有"被选中"的回应感）
  @State private selectedCard: string = '';
  // Obsidian 1.13.7 兼容性公告：只在当前公告 ID 未确认时展示一次。
  @State private showUpdateNotice: boolean = false;
  @State private isVipNow: boolean = false;
  private readonly updateNoticeId: string = UPDATE_NOTICE_ID;
  private updateNoticeTimer: number = -1;
  private noticeFilesDir: string = '';
  @State private serviceBusy: boolean = false;
  @State private remoteVaultLabel: string = '';
  @State private lanAddr: string = '';
  @State private pairedClients: number = -1;
  @State private serverConfigured: boolean = false;
  private serviceRevision: number = 0;
  private routeTimer: number = -1;
  private pageAlive: boolean = true;
  private generation: number = 0;

  private clearRouteTimer(): void {
    if (this.routeTimer !== -1) {
      clearTimeout(this.routeTimer);
      this.routeTimer = -1;
    }
  }

  private enterFx(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
      .animation({ duration: 200, curve: Curve.EaseOut });
  }

  // 返回主页恢复交互和服务状态，并记录下次启动位置。
  onPageShow() {
    this.pageAlive = true;
    // Home is the route root; prune stale pages after it is active.
    router.clear();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!StartupPreferences.enterHome(context)) {
      this.getUIContext().getPromptAction().showToast({ message: '主页位置保存失败，请稍后重试' });
    }
    this.selectedCard = '';
    this.bgVisible = true;
    this.isVipNow = VipService.isVip();
    PersistentStorage.persistProp('srvModeEnabled', false);
    PersistentStorage.persistProp('aiModeEnabled', false);
    PersistentStorage.persistProp('lanSharePort', 0);
    this.refreshServices();
    this.serverConfigured = (AppStorage.get<string>('serverUrl') ?? '').trim() !== '';
    this.remoteVaultLabel = '';
    try {
      const config = WebDavSettings.load(context);
      if (config !== undefined && config.enabled) { this.remoteVaultLabel = config.vaultName; }
    } catch (e) { /* 配置错误交给配置页处理，不阻塞主页。 */ }
    this.noticeFilesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir;
    if (!NoticeState.isSeen(this.noticeFilesDir, this.updateNoticeId)) {
      if (this.updateNoticeTimer !== -1) {
        clearTimeout(this.updateNoticeTimer);
      }
      // 等首页转场和入场动画落定后再展示，不抢首帧。
      this.updateNoticeTimer = setTimeout(() => {
        this.updateNoticeTimer = -1;
        if (!NoticeState.isSeen(this.noticeFilesDir, this.updateNoticeId)) {
          this.showUpdateNotice = true;
        }
      }, 720);
    }
    // pushUrl/back 后页面实例存活，选中态会残留——防连点早退把后续点击全吞了
    // （表现为：进过一次子页返回后，两张卡片都点不动）
    this.selectedCard = '';
    this.pressedLocal = false;
  }

  onPageHide() {
    this.pageAlive = false;
    this.generation += 1;
    this.clearRouteTimer();
    this.bgVisible = false;
    if (this.updateNoticeTimer !== -1) {
      clearTimeout(this.updateNoticeTimer);
      this.updateNoticeTimer = -1;
    }
  }

  aboutToDisappear() {
    this.onPageHide();
  }

  private closeUpdateNotice(): void {
    if (this.noticeFilesDir !== '') {
      NoticeState.markSeen(this.noticeFilesDir, this.updateNoticeId);
    }
    this.showUpdateNotice = false;
  }

  aboutToAppear() {
    // stagger 三拍挪到转场后：转场期间不跑插入动画（与转场动画抢主线程是卡顿源之一），落定后依次浮现
    setTimeout(() => { this.t1 = true; }, 240);
    setTimeout(() => { this.t2 = true; }, 310);
    setTimeout(() => { this.t3 = true; }, 380);
  }

  // 选中卡片 → 强调动效亮起 → 短暂停留后跳转（不生硬的关键）
  private selectCard(card: string, mode: string, target: string): void {
    if (!this.pageAlive || this.selectedCard !== '') {
      return; // 防连点重复跳转
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!StartupPreferences.enterMode(context, mode)) {
      this.getUIContext().getPromptAction().showToast({ message: '启动模式保存失败，请重试' });
      return;
    }
    this.selectedCard = card;
    hapticSelect();
    AppStorage.setOrCreate('bootMode', mode);
    const generation = this.generation;
    this.routeTimer = setTimeout(() => {
      this.routeTimer = -1;
      if (this.pageAlive && generation === this.generation) {
        router.pushUrl({ url: target });
      }
    }, 170);
  }

  private async refreshServices(): Promise<void> {
    if (this.serviceBusy || AppStorage.get<boolean>('ignisReady') !== true) { return; }
    const epoch = this.generation;
    const revision = this.serviceRevision;
    const srv = await LanShareApi.status();
    if (!this.pageAlive || epoch !== this.generation || revision !== this.serviceRevision || this.serviceBusy) { return; }
    if (srv !== null) {
      AppStorage.setOrCreate('srvRunning', srv.running);
      const ip = LanShareApi.getLanIp();
      const port = srv.port > 0 ? srv.port : (AppStorage.get<number>('lanSharePort') ?? 0);
      this.lanAddr = srv.running && ip !== '' && port > 0 ? ip + ':' + port : '';
    }
    const ai = await AiLanApi.status();
    if (!this.pageAlive || epoch !== this.generation || revision !== this.serviceRevision || this.serviceBusy) { return; }
    if (ai !== null) {
      AppStorage.setOrCreate('aiRunning', ai.running);
      this.pairedClients = ai.running ? ai.pairedClients : -1;
    }
  }

  private async changeService(kind: string, enabled: boolean): Promise<void> {
    if (!this.pageAlive || this.serviceBusy || this.selectedCard !== '') { return; }
    this.serviceBusy = true;
    this.serviceRevision++;
    const epoch = this.generation;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const result = await HomeServiceControl.change(context, kind, enabled);
      if (!this.pageAlive || epoch !== this.generation) { return; }
      if (result === 'vip') {
        router.pushUrl({ url: 'pages/VipPanelPage' });
      } else if (result === 'startup' || result === 'srvSetup' || result === 'aiSetup') {
        if (result === 'startup') {
          AppStorage.setOrCreate(kind === 'srv' ? 'srvModeEnabled' : 'aiModeEnabled', true);
          this.getUIContext().getPromptAction().showToast({ message: '正在准备本机服务，首次使用请完成页面中的配置' });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: kind === 'srv' ? '请先设置访问账号和密码' : '请先确认笔记库授权设置' });
        }
        this.selectCard(kind, kind, 'pages/NodeTest');
      } else if (result !== '') {
        this.getUIContext().getPromptAction().showToast({ message: result });
      }
    } catch (e) {
      if (this.pageAlive && epoch === this.generation) {
        this.getUIContext().getPromptAction().showToast({ message: '操作结果未确认，请稍后重试' });
      }
    } finally {
      this.serviceBusy = false;
    }
  }

  @Builder
  configAction(label: string, target: string) {
    Button(label).fontSize(12).height(36).padding({ left: 12, right: 12 })
      .fontColor('#C7CDF0').backgroundColor('rgba(255,255,255,0.04)')
      .border({ width: 1, color: 'rgba(255,255,255,0.18)' }).borderRadius(18)
      .enabled(!this.serviceBusy && this.selectedCard === '')
      .onClick(() => { if (this.pageAlive) { hapticLight(); router.pushUrl({ url: target }); } })
  }

  build() {
    Stack() {
      Column() {}.width('100%').height('100%')
        .linearGradient({ angle: 160, colors: [[Theme.PAGE_BG_START, 0], [Theme.PAGE_BG_MIDDLE, 0.55], [Theme.PAGE_BG_END, 1]] })
      WaveBackground({ visible: this.bgVisible })
      Scroll() {
        Column() {
          if (this.t1) {
            Text('VITREUS')
              .fontSize(36).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
              .letterSpacing(7).textAlign(TextAlign.Center).width('100%')
              .margin({ top: 76, bottom: 40 }).transition(this.enterFx())
          }

          if (this.t2) {
            Column() {
              Column() {
                Button({ type: ButtonType.Normal, stateEffect: false }) {
                  Column({ space: 14 }) {
                    Row({ space: 13 }) {
                      SymbolGlyph($r('sys.symbol.book')).fontSize(30).fontColor(['#E6EAFF'])
                      Text('打开 Vault').fontSize(29).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    }.width('100%')
                    Text('在本设备打开笔记库').fontSize(14).fontColor('#D6DCFF').width('100%')
                  }.width('100%').alignItems(HorizontalAlign.Start)
                  .padding({ left: 24, right: 24 })
                  .justifyContent(FlexAlign.Center)
                  .height('100%')
                }
                // 显式高度：Button 的默认高度不会随内部 padding 自动长高。
                .width('100%').height(184).padding(0).backgroundColor(Color.Transparent)
                .enabled(!this.serviceBusy && this.selectedCard === '')
                .onClick(() => {
                  this.selectCard('local', 'local', 'pages/NodeTest');
                })

                Row({ space: 10 }) {
                  Button({ type: ButtonType.Normal, stateEffect: false }) {
                    Row({ space: 4 }) {
                      Text(this.remoteVaultLabel !== '' ? '远程库 · ' + this.remoteVaultLabel : '配置远程库')
                        .constraintSize({ maxWidth: 110 }).fontSize(12).fontColor('#C3CBF5').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(9).fontColor(['#A3AEDF'])
                    }
                    .padding({ left: 11, right: 9, top: 6, bottom: 6 })
                    .border({ width: 1, color: 'rgba(198,206,255,0.38)' })
                    .borderRadius(14)
                  }
                  .height(44).padding(0).backgroundColor(Color.Transparent)
                  .enabled(!this.serviceBusy && this.selectedCard === '')
                  .onClick(() => {
                    hapticLight();
                    router.pushUrl({ url: 'pages/WebDavSettingsPage' });
                  })

                  Blank()

                  Button({ type: ButtonType.Normal, stateEffect: false }) {
                    Row({ space: 6 }) {
                      Text('开始使用').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White)
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([Color.White])
                    }
                  }
                  .height(44).padding({ left: 12, right: 0 }).backgroundColor(Color.Transparent)
                  .enabled(!this.serviceBusy && this.selectedCard === '')
                  .onClick(() => { this.selectCard('local', 'local', 'pages/NodeTest'); })
                }.width('100%').alignItems(VerticalAlign.Center)
                .padding({ left: 22, right: 22, top: 8, bottom: 22 })
              }
              .width('100%')
              .linearGradient({ angle: 135, colors: [['rgba(182,193,255,0.62)', 0], ['rgba(124,138,248,0.46)', 0.42], ['rgba(88,100,216,0.34)', 1]] })
              .border({ width: this.selectedCard === 'local' ? 1.6 : 1, color: 'rgba(204,212,255,0.70)', radius: 24 })
              .borderRadius(24).clip(true)
              .shadow({ radius: 32, color: 'rgba(104,117,232,0.50)', offsetY: 12 })
              .enabled(!this.serviceBusy && this.selectedCard === '')
              .onClick(() => { this.selectCard('local', 'local', 'pages/NodeTest'); })
              .scale(this.pressedLocal ? { x: 0.985, y: 0.985 } : { x: 1, y: 1 })
              .animation({ duration: 160, curve: Curve.EaseOut })
              .onTouch((e: TouchEvent) => { this.pressedLocal = e.type === TouchType.Down; })

              Row({ space: 8 }) {
                Button({ stateEffect: true }) {
                  Column({ space: 6 }) {
                    Row({ space: 8 }) {
                      Text('连接已有服务器').fontSize(15).fontColor('#D3D9FA')
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor(['#A5AFDF'])
                    }
                    Text('已部署 Ignis？连接服务器使用笔记').fontSize(12).fontColor('#9EA9D9')
                      .width('100%')
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }.layoutWeight(1).type(ButtonType.Normal).height(80)
                  .padding({ top: 18, bottom: 18, left: 4, right: 4 })
                  .backgroundColor(Color.Transparent).borderRadius(12)
                  .enabled(!this.serviceBusy && this.selectedCard === '')
                  .onClick(() => {
                    this.selectCard('remote', 'remote', String(AppStorage.get('serverUrl') ?? '').trim() === ''
                      ? 'pages/IgnisSettingsPage' : 'pages/Index');
                  })
                if (this.serverConfigured) {
                  this.configAction('配置', 'pages/IgnisSettingsPage')
                }
              }.width('100%').margin({ top: 6, bottom: 24 })

              Text('与其他设备连接').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#C9D0F2')
                .width('100%').margin({ bottom: 12 })
              Column() {
                Row({ space: 16 }) {
                  Button({ stateEffect: true }) {
                    Column({ space: 6 }) {
                      Row({ space: 6 }) {
                        Text('浏览器访问本设备笔记').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                      }.width('100%')
                      Text(this.srvRunning
                        ? (this.lanAddr !== '' ? '已开启 · ' + this.lanAddr : '已开启 · 同一局域网内可访问')
                        : '让同一局域网的电脑、平板访问')
                        .fontSize(12).fontColor(this.srvRunning ? Theme.SUCCESS : Theme.TEXT_SECONDARY).lineHeight(18)
                      Text('地址与访问设置 ›').fontSize(11).fontColor('#A8B4EB')
                    }.width('100%').alignItems(HorizontalAlign.Start)
                  }.layoutWeight(1).type(ButtonType.Normal).height(94)
                    .padding(0).backgroundColor(Color.Transparent).borderRadius(8)
                    .enabled(!this.serviceBusy && this.selectedCard === '')
                    .onClick(() => {
                      this.selectCard('srv', 'srv', 'pages/NodeTest');
                    })
                  ServiceSwitch({ isOn: this.srvRunning, interactive: !this.serviceBusy && this.selectedCard === '',
                    label: '浏览器访问本设备笔记', onChange: (value: boolean) => { this.changeService('srv', value); } })
                }.width('100%').alignItems(VerticalAlign.Center).padding(20)
                Divider().color('rgba(255,255,255,0.12)').width('88%')
                Row({ space: 16 }) {
                  Button({ stateEffect: true }) {
                    Column({ space: 6 }) {
                      Row({ space: 6 }) {
                        Text('AI 访问本设备笔记').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                      }.width('100%')
                      Text(this.aiRunning
                        ? (this.pairedClients >= 0 ? '已开启 · 已配对 ' + this.pairedClients.toString() + ' 台设备' : '已开启 · 电脑 AI 可访问授权笔记')
                        : '让电脑上的 AI 搜索和处理授权笔记')
                        .fontSize(12).fontColor(this.aiRunning ? Theme.SUCCESS : Theme.TEXT_SECONDARY).lineHeight(18)
                      Text('配对与授权设置 ›').fontSize(11).fontColor('#A8B4EB')
                    }.width('100%').alignItems(HorizontalAlign.Start)
                  }.layoutWeight(1).type(ButtonType.Normal).height(94)
                    .padding(0).backgroundColor(Color.Transparent).borderRadius(8)
                    .enabled(!this.serviceBusy && this.selectedCard === '')
                    .onClick(() => {
                      this.selectCard('ai', 'ai', 'pages/NodeTest');
                    })
                  ServiceSwitch({ isOn: this.aiRunning, interactive: !this.serviceBusy && this.selectedCard === '',
                    label: 'AI 访问本设备笔记', onChange: (value: boolean) => { this.changeService('ai', value); } })
                }.width('100%').alignItems(VerticalAlign.Center).padding(20)
              }.width('100%')
                .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
                .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
                .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
                .borderRadius(20).clip(true)
                .border({ width: 1, color: 'rgba(255,255,255,0.32)' }).margin({ bottom: 32 })
            }.width('100%').transition(this.enterFx())
          }

          if (this.t3) {
            Row({ space: 10 }) {
              this.entryPill('其他配置', false, () => { router.pushUrl({ url: 'pages/CaptureSettings' }); })
              this.entryPill('会员', this.isVipNow, () => { router.pushUrl({ url: 'pages/VipPanelPage' }); })
              this.entryPill('关于', false, () => { router.pushUrl({ url: 'pages/About' }); })
            }.width('100%').justifyContent(FlexAlign.Center).transition(this.enterFx())
          }
        }.width('86%').padding({ bottom: 36 }).alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%')
      if (this.showUpdateNotice) {
        UpdateNoticeDialog({ onClose: () => { hapticLight(); this.closeUpdateNotice(); } })
      }
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  entryPill(label: string, gold: boolean, onTap: () => void) {
    Row({ space: 6 }) {
      if (gold) {
        Circle({ width: 6, height: 6 }).fill(Theme.WARN)
      }
      Text(label)
        .fontSize(13)
        .fontColor(gold ? Theme.WARN : '#C7CDF0')
    }
    .padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .backgroundColor('rgba(255,255,255,0.07)')
    .borderRadius(18)
    .border({ width: 1, color: 'rgba(255,255,255,0.16)' })
    .stateStyles({
      pressed: { .scale({ x: 0.95, y: 0.95 }) }
    })
    .onClick(() => {
      hapticLight();
      onTap();
    })
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
