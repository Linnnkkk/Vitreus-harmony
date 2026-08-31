import { router } from '@kit.ArkUI';
import { TypeWriter } from '../components/TypeWriter';
import { StarfieldBackground } from '../components/AmbientBackground';
import { BackButton } from '../components/BackButton';

// 服务器认证页：账号密码输入（密码靠保险箱记住，不落盘）。设计语言同 Login
@Entry
@Component
struct AuthPage {
  // 背景动效联通：页面隐藏停表
  @State private transiting: boolean = true; // 转场期间玻璃降级实底(GPU零模糊)：转场结束320ms后恢复玻璃
  @State private bgVisible: boolean = true;
  @State private pressedLogin: boolean = false;
  @State private inputUser: string = '';
  @State private inputPwd: string = '';

  aboutToAppear() {
    // 回填账号（持久化）；密码不回填，靠保险箱 AutoFill 填
    this.inputUser = AppStorage.get<string>('authUser') ?? '';
  }

  // 左滑/系统返回：与左上角 BackButton 同目标。
  // 全 app 用 replaceUrl 导航，路由栈只有 1 层，系统默认返回无处可 pop——必须显式指路
  onBackPress(): boolean {
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/Login' });
    }
    return true;
  }

  onPageShow() {
    setTimeout(() => { this.transiting = false; }, 320); // 转场结束恢复玻璃
    this.bgVisible = true;
  }

  onPageHide() {
    this.transiting = true; // 转场开始：玻璃降级
    this.bgVisible = false;
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
      StarfieldBackground({ visible: this.bgVisible })

      Column() {
        Text('服务器登录')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 110, bottom: 8 })
        TypeWriter({ text: AppStorage.get<string>('serverUrl') ?? '', fontSize: 12, color: '#5A649E', speed: 16 })
          .margin({ bottom: 56 })

        // ── 输入卡片 ──
        Column() {
          Text('账号')
            .fontSize(12)
            .fontColor('#7A85C4')
            .margin({ bottom: 8 })
          TextInput({ placeholder: '账号', text: this.inputUser })
            .width('100%')
            .height(50)
            .type(InputType.USER_NAME)
            .enableAutoFill(true)
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#4A5290')
            .borderRadius(12)
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
            .padding({ left: 16, right: 16 })
            .margin({ bottom: 18 })
            .onChange((v: string) => { this.inputUser = v; })

          Text('密码')
            .fontSize(12)
            .fontColor('#7A85C4')
            .margin({ bottom: 8 })
          TextInput({ placeholder: '密码' })
            .width('100%')
            .height(50)
            .type(InputType.Password)
            .enableAutoFill(true)
            .backgroundColor('rgba(255,255,255,0.04)')
            .fontColor(Color.White)
            .placeholderColor('#4A5290')
            .borderRadius(12)
            .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
            .padding({ left: 16, right: 16 })
            .onChange((v: string) => { this.inputPwd = v; })
        }
        .width('86%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 22, right: 22, top: 26, bottom: 30 })
        .backgroundEffect(this.transiting ? { radius: 0.01, saturation: 1.0, brightness: 1.0, color: 'rgba(24,28,58,0.92)', adaptiveColor: AdaptiveColor.AVERAGE } : { radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
        .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
        .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255,255,255,0.32)' })

        // ── 登录按钮 ──
        Button('登 录')
          .width('86%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
          .fontColor(Color.White)
          .borderRadius(16)
          .margin({ top: 28 })
          .scale(this.pressedLogin ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
          .animation({ duration: 150, curve: 'springMotion(0.3, 0.8)' })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.pressedLogin = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.pressedLogin = false;
            }
          })
          .onClick(() => {
            if (this.inputUser === '' || this.inputPwd === '') {
              this.getUIContext().getPromptAction().showToast({ message: '请输入账号和密码' });
              return;
            }
            // 账号存 AppStorage（会持久化）；密码只存内存（保险箱记住，不持久化磁盘）
            AppStorage.setOrCreate('authUser', this.inputUser.trim());
            AppStorage.setOrCreate('authPwd', this.inputPwd);
            // router 跳转 = 密码保险箱「保存提示」触发信号
            router.replaceUrl({ url: 'pages/Index' });
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      // 左上角常驻返回（回登录页换地址）
      BackButton({ target: 'pages/Login' })
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
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 200, curve: Curve.EaseOut })
      .translate({ x: -36 })
    PageTransitionExit({ type: RouteType.Push, duration: 160, curve: Curve.EaseIn })
      .translate({ x: -110 })
    PageTransitionExit({ type: RouteType.Pop, duration: 160, curve: Curve.EaseIn })
      .translate({ x: 320 })
  }
}
