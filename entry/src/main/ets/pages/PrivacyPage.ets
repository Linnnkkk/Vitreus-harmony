import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BackButton } from '../components/BackButton';

// 隐私政策查看页：加载包内 rawfile/privacy.html（离线可看，与线上
// docs/privacy.html 保持同一份内容——改政策时两处一起改）。
// 入口：首次启动弹窗的《隐私政策》、关于页「隐私政策」。
@Entry
@Component
struct PrivacyPage {
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      Web({ src: $rawfile('privacy.html'), controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#141736')
        // 页内外链（GitHub、备案查询等）交给系统浏览器，不在本页内跳走
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          if (url.startsWith('http://') || url.startsWith('https://')) {
            try {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              ctx.openLink(url);
            } catch (e) {
              // 打不开就静默
            }
            return true;
          }
          return url.startsWith('mailto:');
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 100 })

      BackButton({ target: 'pages/ModeSelect' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#141736')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
