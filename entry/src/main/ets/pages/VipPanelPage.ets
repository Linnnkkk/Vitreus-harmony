// 会员购买页（VipPanelPage）—— 伺服器模式的付费入口
// 入口路径（审核用）：首页 → 伺服器模式 → 打开伺服器开关（非会员时自动进入本页）
// 商品：月度/年度自动续订 + 永久买断，价格由 queryProducts 实时拉取（AGC 配置为准，不适配币种硬编码）
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BackButton } from '../components/BackButton';
import { hapticLight, hapticSuccess } from '../common/Haptics';
import { VipService, VipProduct, VipProductInfo } from '../common/VipService';
import { iap } from '@kit.IAPKit';

const TAG = 'VipPanelPage';
const DOMAIN = 0x0F11;

interface PlanCard {
  productId: string;
  name: string;
  desc: string;
  priceText: string;
  highlight: boolean; // 永久档标「最划算」
}

@Entry
@Component
struct VipPanelPage {
  @State private plans: PlanCard[] = [];
  @State private selected: string = VipProduct.PERMANENT; // 默认选永久（1.67年回本锚点）
  @State private loading: boolean = true;
  @State private buying: boolean = false;
  @State private isVipNow: boolean = false;
  @State private statusText: string = '';
  @State private hasPermanent: boolean = false; // 永久会员：月/年档置灰（不需要再买订阅）
  @State private activeSub: string = ''; // 生效中的订阅档（月/年）：当前档置灰"使用中"，另一档提示先取消

  aboutToAppear() {
    // VIP 权益键持久化（幂等；EntryAbility 已注册，此处双保险防时序）
    PersistentStorage.persistProp('vipPermanent', false);
    PersistentStorage.persistProp('vipUntil', 0);
    PersistentStorage.persistProp('vipSubProduct', '');
    this.refreshVipState();
    this.loadProducts();
  }

  onPageShow() {
    this.refreshVipState(); // 购买返回/页面重现时刷新（含新买永久后月/年档即时置灰）
  }

  private refreshVipState(): void {
    this.isVipNow = VipService.isVip();
    this.statusText = VipService.vipStatusText();
    this.hasPermanent = AppStorage.get<boolean>('vipPermanent') === true;
    const sub = AppStorage.get<string>('vipSubProduct') ?? '';
    this.activeSub = (!this.hasPermanent && VipService.isVip() && (sub === VipProduct.MONTHLY || sub === VipProduct.YEARLY)) ? sub : '';
    if (this.hasPermanent && this.selected !== VipProduct.PERMANENT) {
      this.selected = VipProduct.PERMANENT; // 永久在手，选中态强制归位
    }
    if (this.activeSub !== '' && this.selected !== VipProduct.PERMANENT && this.selected === this.activeSub) {
      this.selected = VipProduct.PERMANENT; // 当前订阅档已置灰，选中态归位（唯一可买的订阅外选项）
    }
  }

  private loadProducts(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    VipService.queryProducts(ctx).then((list: VipProductInfo[]) => {
      const cards: PlanCard[] = [];
      for (const p of list) {
        if (p.productId === VipProduct.MONTHLY) {
          cards.push({ productId: p.productId, name: '包月', desc: '自动续订 · 可随时取消', priceText: p.priceText + '/月', highlight: false });
        } else if (p.productId === VipProduct.YEARLY) {
          cards.push({ productId: p.productId, name: '包年', desc: '自动续订 · 合包月约 5 折', priceText: p.priceText + '/年', highlight: false });
        } else if (p.productId === VipProduct.PERMANENT) {
          cards.push({ productId: p.productId, name: '永久', desc: '一次买断 · 永不过期', priceText: p.priceText, highlight: true });
        }
      }
      // 空列表兜底：沙盒下 queryProducts 查草稿商品恒空，但 createPurchase 可直接购买（华为官方问答实证）
      // 仅查询成功且零错误时兜底（环境错误仍走失败提示块）；价格以收银台实时为准
      if (cards.length === 0 && VipService.lastEnvError === '') {
        // 本地兜底用 AGC 配置的真实价（改价生效后 queryProducts 自动覆盖为实时值）
        cards.push({ productId: VipProduct.MONTHLY, name: '包月', desc: '自动续订 · 可随时取消', priceText: '¥9.9/月', highlight: false });
        cards.push({ productId: VipProduct.YEARLY, name: '包年', desc: '自动续订 · 合包月约 5 折', priceText: '¥59.9/年', highlight: false });
        cards.push({ productId: VipProduct.PERMANENT, name: '永久', desc: '一次买断 · 永不过期', priceText: '¥99.9', highlight: true });
      }
      this.plans = cards;
      this.loading = false;
      if (cards.length === 0) {
        this.selected = '';
      } else if (this.selected === '') {
        this.selected = VipProduct.PERMANENT;
      }
    });
  }

  private productTypeOf(productId: string): iap.ProductType {
    return productId === VipProduct.PERMANENT ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE;
  }

  private buy(): void {
    if (this.buying || this.selected === '') {
      return;
    }
    hapticLight();
    this.buying = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    VipService.purchase(ctx, this.selected, this.productTypeOf(this.selected)).then((outcome) => {
      this.buying = false;
      if (outcome.ok) {
        hapticSuccess();
        this.isVipNow = true;
        this.statusText = VipService.vipStatusText();
        this.getUIContext().getPromptAction().showToast({ message: '开通成功，即将返回伺服器页', duration: 1800 });
        setTimeout(() => {
          router.back();
        }, 800); // 快速返回：权益已写本地（grant 瞬时完成），finish 记账在后台——toast 跨页继续飘
      } else if (outcome.message !== '') {
        this.getUIContext().getPromptAction().showToast({ message: outcome.message, duration: 2500 });
      }
    });
  }

  private restore(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    VipService.restore(ctx).then(() => {
      this.isVipNow = VipService.isVip();
      this.statusText = VipService.vipStatusText();
      if (this.isVipNow) {
        this.getUIContext().getPromptAction().showToast({ message: '已恢复会员权益', duration: 2200 });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '未找到可恢复的购买记录', duration: 2200 });
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 160, colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]] })

      Scroll() {
        Column({ space: 14 }) {
          Text('Vitreus 会员')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ top: 96 })
          Text('解锁伺服器模式 · 让手机成为你的笔记中枢')
            .fontSize(12.5)
            .fontColor('#8F9BD8')
            .letterSpacing(0.5)

          // ── 已是会员状态条 ──
          if (this.isVipNow) {
            Text('当前状态：' + (this.statusText !== '' ? this.statusText : '会员生效中'))
              .fontSize(13)
              .fontColor('#9BE8B4')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor('#16351F')
              .borderRadius(12)
              .border({ width: 1, color: '#2E6B45' })
          }

          // ── 功能介绍 ──
          Column({ space: 7 }) {
            Text('解锁「伺服器模式」')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E2E6F8')
            Text('熄屏锁屏持续在线，局域网设备浏览器直连，Digest 加密认证保护。本地与远程模式始终免费。')
              .fontSize(12.5)
              .fontColor('#8F9BD8')
              .lineHeight(19)
          }
          .width('86%')
          .padding({ left: 22, right: 22, top: 18, bottom: 18 })
          .backgroundColor('#1A1E4A')
          .borderRadius(18)
          .border({ width: 1, color: '#3A4078' })
          .alignItems(HorizontalAlign.Start)

          // ── 三档价格卡 ──
          if (this.loading) {
            Text('正在获取商品信息…')
              .fontSize(13)
              .fontColor('#8F9BD8')
              .margin({ top: 20, bottom: 20 })
          } else if (this.plans.length === 0) {
            Column({ space: 10 }) {
              Text('商品信息获取失败')
                .fontSize(14)
                .fontColor('#B8C0E4')
              Text(VipService.lastEnvError !== ''
                ? VipService.lastEnvError + ' · 请确认已登录华为账号，或证书指纹已登记 AGC'
                : '暂无在售商品：AGC 后台的商品可能仍为草稿或审核中，需提交审核并生效后才会在客户端展示')
                .fontSize(11.5)
                .fontColor('#6A74A8')
              Button('重新获取')
                .fontSize(13)
                .fontColor('#FFFFFF')
                .backgroundColor('#5F6BD8')
                .borderRadius(12)
                .height(36)
                .padding({ left: 22, right: 22 })
                .margin({ top: 4 })
                .onClick(() => {
                  this.loading = true;
                  this.loadProducts();
                })
            }
            .width('86%')
            .padding({ top: 18, bottom: 18 })
            .backgroundColor('#1A1E4A')
            .borderRadius(16)
            .border({ width: 1, color: '#3A4078' })
          } else {
            ForEach(this.plans, (p: PlanCard) => {
              // 已有生效订阅防呆：当前档"使用中"置灰；另一档提示先取消（华为无订阅组时重复订阅必被拒）
              if (this.activeSub !== '' && p.productId !== VipProduct.PERMANENT) {
                Row({ space: 12 }) {
                  Radio({ value: p.productId, group: 'plan' })
                    .checked(false)
                    .enabled(false)
                  Column({ space: 3 }) {
                    Text(p.name)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#5A649E')
                    Text(p.productId === this.activeSub ? '当前方案 · 自动续费中' : '需先在华为订阅管理取消当前方案')
                      .fontSize(11.5)
                      .fontColor('#5A649E')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(p.priceText)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#5A649E')
                }
                .width('86%')
                .padding({ left: 20, right: 20, top: 16, bottom: 16 })
                .backgroundColor('#161A3E')
                .borderRadius(16)
                .border({ width: 1, color: p.productId === this.activeSub ? '#3A4A7E' : '#2A2F5E' })
                .opacity(0.55)
              } else if (this.hasPermanent && p.productId !== VipProduct.PERMANENT) {
                Row({ space: 12 }) {
                  Radio({ value: p.productId, group: 'plan' })
                    .checked(false)
                    .enabled(false)
                  Column({ space: 3 }) {
                    Text(p.name)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#5A649E')
                    Text('已拥有永久会员，无需订阅')
                      .fontSize(11.5)
                      .fontColor('#5A649E')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(p.priceText)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#5A649E')
                }
                .width('86%')
                .padding({ left: 20, right: 20, top: 16, bottom: 16 })
                .backgroundColor('#161A3E')
                .borderRadius(16)
                .border({ width: 1, color: '#2A2F5E' })
                .opacity(0.55)
              } else {
              Row({ space: 12 }) {
                Radio({ value: p.productId, group: 'plan' })
                  .checked(this.selected === p.productId)
                  .onChange((on: boolean) => {
                    if (on) {
                      hapticLight();
                      this.selected = p.productId;
                    }
                  })
                  .radioStyle({ checkedBackgroundColor: '#5F6BD8' })
                Column({ space: 3 }) {
                  Row({ space: 8 }) {
                    Text(p.name)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                    if (p.highlight) {
                      Text('最划算')
                        .fontSize(10)
                        .fontColor('#FFFFFF')
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                        .backgroundColor('#5F6BD8')
                        .linearGradient({ angle: 90, colors: [['#8A98F0', 0], ['#5F6BD8', 1]] })
                        .borderRadius(8)
                    }
                  }
                  Text(p.desc)
                    .fontSize(11.5)
                    .fontColor('#8F9BD8')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text(p.priceText)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#E2E6F8')
              }
              .width('86%')
              .padding({ left: 20, right: 20, top: 16, bottom: 16 })
              .backgroundColor(this.selected === p.productId ? '#252E5E' : '#1A1E4A')
              .linearGradient(this.selected === p.productId ? { angle: 135, colors: [['#2E3A78', 0], ['#242C5C', 1]] } : { angle: 135, colors: [['#1A1E4A', 0], ['#1A1E4A', 1]] })
              .borderRadius(16)
              .border({
                width: this.selected === p.productId ? 1.5 : 1,
                color: this.selected === p.productId ? '#8A98F0' : '#3A4078'
              })
              .shadow(this.selected === p.productId ? { radius: 14, color: '#5F6BD840', offsetY: 4 } : { radius: 0, color: 'transparent' })
              .onClick(() => {
                hapticLight();
                this.selected = p.productId;
              })
              }
            }, (p: PlanCard) => p.productId)
          }

          // ── 立即开通 ──
          Button(this.buying ? '正在拉起支付…' : '立即开通')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .width('86%')
            .height(50)
            .backgroundColor('#5F6BD8')
            .linearGradient({ angle: 90, colors: [['#7A88E8', 0], ['#5F6BD8', 1]] })
            .borderRadius(25)
            .shadow({ radius: 16, color: '#5F6BD855', offsetY: 6 })
            .enabled(!this.buying && this.selected !== '' && this.plans.length > 0)
            .margin({ top: 8 })
            .onClick(() => { this.buy(); })

          // ── 恢复购买 ──
          Text('恢复购买')
            .fontSize(13)
            .fontColor('#8F9BD8')
            .padding({ top: 10, bottom: 10, left: 20, right: 20 })
            .onClick(() => { this.restore(); })

          // ── 订阅协议说明（华为审核要求：自动续订商品须显著说明）──
          Column({ space: 4 }) {
            Text('· 包月/包年为自动续订订阅，到期自动扣费续期，可随时在「设置 → 华为账号 → 付款与购买 » 订阅」中取消。')
              .fontSize(11)
              .fontColor('#6A74A8')
            Text('· 永久会员一次买断，无任何后续费用。未开通会员不影响本地与远程模式的完整免费使用。')
              .fontSize(11)
              .fontColor('#6A74A8')
            Text('· 付款扣至华为账号，具体资费以收银台页面为准。')
              .fontSize(11)
              .fontColor('#6A74A8')
          }
          .width('86%')
          .margin({ top: 6, bottom: 44 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      BackButton({ target: 'pages/LanServerPage' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  onBackPress(): boolean {
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
