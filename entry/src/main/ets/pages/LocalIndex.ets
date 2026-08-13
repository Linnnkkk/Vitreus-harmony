import { webview } from '@kit.ArkWeb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

/**
 * JS Bridge 对象：暴露文件读写能力给前端网页（ignis 本地模式的核心链路）
 * 前端通过 window.vitreus.readFile / writeFile / listDir 调用，同步返回结果
 */
class VitreusBridge {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  // 读文件（前端：window.vitreus.readFile('test.txt')）
  readFile(name: string): string {
    try {
      const path = this.ctx.filesDir + '/' + name;
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      return '[读失败] ' + JSON.stringify(e);
    }
  }

  // 写文件（前端：window.vitreus.writeFile('test.txt', '内容')）
  writeFile(name: string, content: string): string {
    try {
      const path = this.ctx.filesDir + '/' + name;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      return '[写成功] ' + name + ' (' + content.length + ' 字符)';
    } catch (e) {
      return '[写失败] ' + JSON.stringify(e);
    }
  }

  // 列目录（前端：window.vitreus.listDir()）
  listDir(): string {
    try {
      const names = fs.listFileSync(this.ctx.filesDir);
      return names.length ? names.join(', ') : '(空)';
    } catch (e) {
      return '[列目录失败] ' + JSON.stringify(e);
    }
  }

  toString(): string {
    return 'VitreusBridge';
  }
}

@Entry
@Component
struct LocalIndex {
  private webController: webview.WebviewController = new webview.WebviewController();
  private bridge: VitreusBridge = new VitreusBridge(getContext(this) as common.UIAbilityContext);

  build() {
    Column() {
      Web({ src: $rawfile('local.html'), controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'vitreus',
          methodList: ['readFile', 'writeFile', 'listDir', 'toString'],
          controller: this.webController
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
