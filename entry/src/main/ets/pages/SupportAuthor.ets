import { router, promptAction } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { BackButton } from '../components/BackButton';
import { WaveBackground } from '../components/WaveBackground';
import { hapticLight } from '../common/Haptics';
import { Theme } from '../common/Theme';

interface AuthorApp {
  name: string;
  description: string;
  category: string;
  icon: Resource;
  url: string;
}

@Entry
@Component
struct SupportAuthor {
  @State private bgVisible: boolean = true;
  private apps: AuthorApp[] = [
    {
      name: '每日道德经', description: '读一段经典，给忙碌的生活留一点思考。', category: '经典阅读',
      icon: $r('app.media.author_daodejing'),
      url: 'https://appgallery.huawei.com/app/detail?id=com.link.dailydaodejing&channelId=SHARE&source=appshare'
    },
    {
      name: '每日易经', description: '从日常阅读开始，慢慢走近易经。', category: '传统文化',
      icon: $r('app.media.author_yijing'),
      url: 'https://appgallery.huawei.com/app/detail?id=com.link.dailyyijing&channelId=SHARE&source=appshare'
    },
    {
      name: '旅途手账', description: '规划下一站，也记下旅途里的小美好。', category: '旅行记录',
      icon: $r('app.media.author_triplog'),
      url: 'https://appgallery.huawei.com/app/detail?id=com.link.triplog&channelId=SHARE&source=appshare'
    },
    {
      name: '云朵生活', description: '从一个小习惯开始，积攒生活的改变。', category: '习惯打卡',
      icon: $r('app.media.author_dailyhabit'),
      url: 'https://appgallery.huawei.com/app/detail?id=com.link.dailyhabit&channelId=SHARE&source=appshare'
    },
    {
      name: '公考计时器', description: '给备考留一段专注时间，把练习安排得更从容。', category: '备考工具',
      icon: $r('app.media.author_gongkaotimer'),
      url: 'https://appgallery.huawei.com/app/detail?id=com.link.gongkaotimer&channelId=SHARE&source=appshare'
    }
  ];

  private goBack(): void {
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      router.replaceUrl({ url: 'pages/About' });
    }
  }

  onBackPress(): boolean {
    this.goBack();
    return true;
  }

  onPageShow(): void {
    this.bgVisible = true;
  }

  onPageHide(): void {
    this.bgVisible = false;
  }

  private openApp(app: AuthorApp): void {
    hapticLight();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: app.url
    };
    try {
      ctx.startAbility(want).catch(() => {
        promptAction.showToast({ message: '暂时无法打开应用市场，请稍后再试' });
      });
    } catch (e) {
      promptAction.showToast({ message: '暂时无法打开应用市场，请稍后再试' });
    }
  }

  @Builder
  appCard(app: AuthorApp) {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        Image(app.icon)
          .width(58)
          .height(58)
          .objectFit(ImageFit.Contain)
          .borderRadius(15)
          .accessibilityText(app.name + '图标')
        Column({ space: 5 }) {
          Text(app.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(app.category)
            .fontSize(11)
            .fontColor('#BFC7FF')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Text(app.description)
        .width('100%')
        .fontSize(13)
        .lineHeight(21)
        .fontColor(Theme.TEXT_SECONDARY)
      Button('去应用市场')
        .width('100%')
        .height(40)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E0E4FF')
        .backgroundColor('rgba(122,136,232,0.20)')
        .borderRadius(12)
        .onClick(() => { this.openApp(app); })
    }
    .width('100%')
    .padding(20)
    .backgroundColor('rgba(23,26,51,0.65)')
    .borderRadius(22)
    .border({ width: 1, color: 'rgba(255,255,255,0.16)' })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 160, colors: [['#1E2150', 0], ['#2A2D6E', 0.55], ['#23265C', 1]] })
      WaveBackground({ visible: this.bgVisible })
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 10 }) {
            Text('支持作者')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('喜欢 Vitreus？也来看看这些小作品。')
              .fontSize(14)
              .lineHeight(23)
              .fontColor('#C5CDEF')
            Text('试用、分享，或留下一条真实的建议，都是支持。')
              .fontSize(12)
              .lineHeight(20)
              .fontColor('#A5AFDD')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 12 })
          ForEach(this.apps, (app: AuthorApp) => {
            this.appCard(app)
          }, (app: AuthorApp) => app.url)
          Text('点击后打开华为应用市场页面，是否安装由你决定。')
            .fontSize(11)
            .lineHeight(19)
            .fontColor('#A5AFDD')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('86%')
        .constraintSize({ maxWidth: 560 })
        .padding({ top: 110, bottom: 48 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      BackButton({ target: 'pages/About' })
    }
    .width('100%')
    .height('100%')
  }
}
