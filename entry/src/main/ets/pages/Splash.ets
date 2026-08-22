import { router, display } from '@kit.ArkUI';
import { SplashIntro } from '../components/SplashIntro';

// 启动页：免责声明（首次）→ 记住模式分发
@Entry
@Component
struct Splash {
  @State private pressedAgree: boolean = false;
  private timerId: number = 0;
  // 窄屏（手机竖屏）用 9:19.5 竖版图，宽屏/平板用方图——方图在窄屏会被
  // objectFit(Cover) 放大裁切，棱镜和字标显示不全
  private splashSrc: Resource = $r('app.media.splash');
  @State private disclaimerShow: boolean = false;
  // 开场动效：logo 图淡入时机 / 光散动画层移除时机
  @State private imgAlpha: number = 0.55;
  @State private introDone: boolean = false;
  @State private disclaimerAgreed: boolean = false;

  aboutToAppear() {
    // 按屏幕长宽比选图：>1.6 视为窄屏手机，用竖版开屏图
    try {
      const dm = display.getDefaultDisplaySync();
      if (dm.height / dm.width > 1.6) {
        this.splashSrc = $r('app.media.splash_tall');
      }
    } catch (e) {
      // 拿不到屏幕信息就默认方图
    }

    PersistentStorage.persistProp('serverUrl', '');
    PersistentStorage.persistProp('authUser', '');
    PersistentStorage.persistProp('appMode', 'remote');
    PersistentStorage.persistProp('disclaimerAccepted', false);

    // 开场动效（免责声明路径也要播——首次启动就在声明框后面开始）
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 550, curve: Curve.EaseOut }, () => {
        this.imgAlpha = 1;
      });
    }, 700);
    setTimeout(() => {
      this.introDone = true;
    }, 1750);

    // 首次启动：弹免责声明（应用市场审核要求：第三方工具显著声明 + 明示同意）
    if (AppStorage.get<boolean>('disclaimerAccepted') !== true) {
      this.disclaimerShow = true;
      return; // 未同意前不进入分发流程
    }
    this.scheduleDispatch();
  }

  // 记住上次模式直接进（远程→Index；本地→本地流程），没记录才去模式选择。
  // 悬浮球点"‹"回 ModeSelect 后走重新选择流程（选择页不跳过）。
  // 权限申请不在启动阶段：由网页页（Index/LocalWeb）加载完成后触发，
  // 启动期窗口切换会把没点完的权限弹窗序列打断。
  private scheduleDispatch() {
    this.timerId = setTimeout(() => {
      const url = AppStorage.get<string>('serverUrl') ?? '';
      const mode = AppStorage.get<string>('appMode') ?? '';
      if (mode === 'remote' && url !== '') {
        router.replaceUrl({ url: 'pages/Index' });
      } else if (mode === 'local') {
        router.replaceUrl({ url: 'pages/NodeTest' });
      } else {
        router.replaceUrl({ url: 'pages/ModeSelect' });
      }
    }, 2000);
  }

  aboutToDisappear() {
    clearTimeout(this.timerId);
  }

  build() {
    Stack() {
      // 动效垫底色（logo 淡入前页面不是黑的）
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#141736')

      Image(this.splashSrc)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.imgAlpha)

      // 开场动效层：一束光射入 → 七彩散射 → 淡出
      if (!this.introDone) {
        SplashIntro()
      }

      // ── 首次启动免责声明 ──
      if (this.disclaimerShow) {
        Column() {
          Column({ space: 14 }) {
            Text('免责声明')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .margin({ top: 4 })

            Scroll() {
              Column({ space: 10 }) {
                Text('1. 本应用为独立第三方开源工具，与 Obsidian / Dynalist Inc. 及 ignis 项目无任何隶属、合作或背书关系。')
                  .fontSize(13)
                  .fontColor('#C8CEE8')
                  .textAlign(TextAlign.Start)
                Text('2. "Obsidian" 为其权利人的商标，本应用仅在描述兼容性时使用该名称。')
                  .fontSize(13)
                  .fontColor('#C8CEE8')
                  .textAlign(TextAlign.Start)
                Text('3. 本应用不包含、不分发任何 Obsidian 受版权保护的内容。本地模式运行所需的组件（.asar）由你自行从官方渠道获取并导入。')
                  .fontSize(13)
                  .fontColor('#C8CEE8')
                  .textAlign(TextAlign.Start)
                Text('4. 您需自行承担使用第三方组件的风险；你的笔记数据始终由你自己的服务或设备保管。')
                  .fontSize(13)
                  .fontColor('#C8CEE8')
                  .textAlign(TextAlign.Start)
              }
              .alignItems(HorizontalAlign.Start)
            }
            .constraintSize({ maxHeight: 260 })
            .width('100%')

            Row({ space: 8 }) {
              Checkbox()
                .select(this.disclaimerAgreed)
                .selectedColor('#7A88D8')
                .onChange((v: boolean) => {
                  this.disclaimerAgreed = v;
                })
              Text('我已阅读并知悉上述声明')
                .fontSize(13)
                .fontColor('#C8CEE8')
                .onClick(() => {
                  this.disclaimerAgreed = !this.disclaimerAgreed;
                })
            }
            .width('100%')
            .margin({ top: 4 })

            Button(this.disclaimerAgreed ? '同意并进入' : '请先勾选知悉')
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.disclaimerAgreed ? '#4F5AC8' : '#2A2D5E')
              .fontColor(this.disclaimerAgreed ? Color.White : '#6A74A8')
              .borderRadius(12)
              .margin({ top: 8 })
              .animation({ duration: 180, curve: Curve.EaseOut })
              .scale(this.pressedAgree ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.pressedAgree = true;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.pressedAgree = false;
                }
              })
              .onClick(() => {
                if (!this.disclaimerAgreed) {
                  return;
                }
                AppStorage.setOrCreate('disclaimerAccepted', true);
                this.disclaimerShow = false;
                this.scheduleDispatch();
              })
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 26, bottom: 26 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: '#3A4078' })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
            .animation({ duration: 220, curve: Curve.EaseOut }))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(10,12,32,0.72)')
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  // 只做退出淡出（进入不做：冷启动首帧与系统启动窗直接衔接，enter 动画反而闪）
  // 方向感转场：前进从右滑入（旧页左移淡出）；返回从左回位（旧页向右滑走）
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 260, curve: Curve.EaseOut })
      .translate({ x: 320 })
      .opacity(0.3)
      .translate({ x: 320 })
      .opacity(0.3)
    PageTransitionEnter({ type: RouteType.Pop, duration: 260, curve: Curve.EaseOut })
      .translate({ x: -36 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 220, curve: Curve.EaseIn })
      .translate({ x: -110 })
      .opacity(0)
      .translate({ x: -110 })
      .opacity(0)
    PageTransitionExit({ type: RouteType.Pop, duration: 220, curve: Curve.EaseIn })
      .translate({ x: 320 })
      .opacity(0)
  }
}
