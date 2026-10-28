import { router } from '@kit.ArkUI';

// 兼容旧启动路径及远程网页的返回入口，服务器信息统一在配置页维护。
@Entry
@Component
struct Login {
  aboutToAppear(): void {
    router.replaceUrl({ url: 'pages/IgnisSettingsPage' });
  }

  build() {
    Column() {}.width('100%').height('100%').backgroundColor('#1E2150')
  }
}
