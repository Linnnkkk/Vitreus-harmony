import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import common from '@ohos.app.ability.common';
import { TypeWriter } from '../components/TypeWriter';
import { NetworkBackground } from '../components/AmbientBackground';
import { BackButton } from '../components/BackButton';

import { RemoteCredentialStore, RemoteCredential } from '../common/RemoteCredentialStore';
import { RemoteServerSettings } from '../common/RemoteServerSettings';

// 远程模式登录页：地址和凭据，密码仅在页面内存及系统保险箱中保存。
@Entry
@Component
struct Login {
  // 背景动效联通：页面隐藏停表
  @State private bgVisible: boolean = true;
  @State private pressedConnect: boolean = false;
  @State private inputUrl: string = '';
  @State private connecting: boolean = false;
  @State private inputUser: string = '';
  @State private inputPwd: string = '';
  @State private credentialLoading: boolean = false;
  private credentialEpoch: number = 0;
  private editEpoch: number = 0;

  aboutToAppear() {
    this.inputUrl = AppStorage.get<string>('serverUrl') ?? '';
    this.loadCredential();
  }

  private async loadCredential(): Promise<void> {
    const epoch = ++this.credentialEpoch;
    const edited = this.editEpoch;
    const server = this.inputUrl.trim();
    this.credentialLoading = server !== '';
    if (server === '') { return; }
    try {
      const credential: RemoteCredential | undefined = await RemoteCredentialStore.load(server);
      if (epoch !== this.credentialEpoch || edited !== this.editEpoch || server !== this.inputUrl.trim()) { return; }
      this.inputUser = credential?.user ?? '';
      this.inputPwd = credential?.pwd ?? '';
    } catch (e) {
      // 读取失败不修改用户正在编辑的内容。
    } finally {
      if (epoch === this.credentialEpoch) { this.credentialLoading = false; }
    }
  }

  private async saveServer(connect: boolean): Promise<void> {
    if (this.connecting || this.credentialLoading) { return; }
    const server = this.inputUrl.trim().replace(/\/+$/, '');
    // 保留原有子路径部署能力；捕获目前只支持根地址，在表单中明确提示。
    if (!/^https?:\/\/(?:\[[0-9a-f:]+\]|[^/:?#@]+)(?::\d{1,5})?(?:\/[^?#]*)?$/i.test(server) || /[\s\\]/.test(server)) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写有效的 HTTP(S) 地址，不含账号、查询参数或片段' });
      return;
    }
    const url = server + '/';
    const user = this.inputUser.trim();
    const pwd = this.inputPwd;
    this.connecting = true;
    ++this.credentialEpoch;
    try {
      const saved = await RemoteCredentialStore.save(url, user, pwd);
      if (!this.bgVisible) { return; }
      if (!saved) {
        this.getUIContext().getPromptAction().showToast({ message: '凭据保存失败，未更新服务器配置，请重试' });
        return;
      }
      AppStorage.setOrCreate('serverUrl', url);
      // 文件落盘：分享/速记独立冷启动只靠 PersistentStorage 会读不到地址
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!RemoteServerSettings.save(context, url)) {
        this.getUIContext().getPromptAction().showToast({ message: '服务器配置写入失败，请重试' });
        return;
      }
      if (!connect) {
        const hasPath = server.replace(/^https?:\/\/[^/]+/i, '') !== '';
        this.getUIContext().getPromptAction().showToast({ message: hasPath ? '配置已保存；远程捕获请改用服务器根地址' : '服务器和凭据已保存，可用于远程捕获' });
        return;
      }
      AppStorage.setOrCreate('appMode', 'remote');
      try { webview.WebviewController.prepareForPageLoad(url, true, 2); } catch (e) { /* 正常加载兜底 */ }
      await router.pushUrl({ url: 'pages/Index' }, router.RouterMode.Single);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存或打开服务器失败，请重试' });
    } finally {
      this.connecting = false;
    }
  }

  // 左滑/系统返回：与左上角 BackButton 同目标。
  // 正常栈为 ModeSelect → Login → Index，返回到地址页后再侧滑应回模式选择。
  onBackPress(): boolean {
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/ModeSelect' });
    }
    return true;
  }

  onPageShow() {
    this.bgVisible = true;
    this.connecting = false;
    this.loadCredential();
  }

  onPageHide() {
    this.bgVisible = false;
    this.credentialEpoch += 1;
    this.inputPwd = '';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底层：深靛蓝纵向渐变
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]]
      })

      // 子页环境动效（与主页面波浪不同款）
      NetworkBackground({ visible: this.bgVisible })

      Scroll() {
        Column() {
        Text('远程服务器')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 110, bottom: 8 })
        TypeWriter({ text: '输入你的服务器地址', fontSize: 13, speed: 20 })
          .margin({ bottom: 56 })

        // ── 输入卡片 ──
        Column() {
          Text('服务器地址')
            .fontSize(12)
            .fontColor('#7A85C4')
            .margin({ bottom: 8 })
          TextInput({ placeholder: 'https://your.server.com', text: this.inputUrl })
            .width('100%')
            .height(50)
            .type(InputType.Normal)
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#B9C0E3')
            .placeholderFont({ size: 14 })
            .borderRadius(12)
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
            .padding({ left: 16, right: 16 })
            .enabled(!this.connecting)
            .onChange((v: string) => {
              this.inputUrl = v;
              this.editEpoch += 1;
              this.inputUser = '';
              this.inputPwd = '';
              this.loadCredential();
            })

          TextInput({ placeholder: '账号（无认证可留空）', text: this.inputUser })
            .height(50)
            .margin({ top: 16 })
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#B9C0E3')
            .borderRadius(12)
            .enabled(!this.connecting)
            .onChange((v: string) => { this.editEpoch += 1; this.inputUser = v; })
          TextInput({ placeholder: '密码（无认证可留空）', text: this.inputPwd })
            .height(50)
            .type(InputType.Password)
            .margin({ top: 16 })
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#B9C0E3')
            .borderRadius(12)
            .enabled(!this.connecting)
            .onChange((v: string) => { this.editEpoch += 1; this.inputPwd = v; })

          Text('密码加密保存在本机。远程捕获目前仅支持服务器根地址；子路径地址仍可连接网页。')
            .fontSize(12)
            .fontColor('#5A649E')
            .margin({ top: 14 })
        }
        .width('86%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 22, right: 22, top: 26, bottom: 26 })
        .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
        .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
        .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255,255,255,0.32)' })

        // ── 连接按钮 ──
        Button(this.connecting ? '保存中…' : '保存并连接')
          .width('86%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
          .fontColor(Color.White)
          .borderRadius(16)
          .margin({ top: 28 })
          .scale(this.pressedConnect ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
          .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.pressedConnect = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.pressedConnect = false;
            }
          })
          .enabled(!this.connecting && !this.credentialLoading)
          .onClick(() => { this.saveServer(true); })
        Button('只保存，不连接')
          .width('86%')
          .height(48)
          .margin({ top: 12 })
          .backgroundColor('rgba(255,255,255,0.08)')
          .fontColor(Color.White)
          .enabled(!this.connecting && !this.credentialLoading)
          .onClick(() => { this.saveServer(false); })
        }
        .width('100%')
        .padding({ bottom: 40 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)

      // 左上角常驻返回（回模式选择）
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
