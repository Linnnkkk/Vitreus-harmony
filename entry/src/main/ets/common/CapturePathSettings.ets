import common from '@ohos.app.ability.common';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CapturePathTemplate, CapturePathTemplates } from './CapturePathTemplate';

const DOMAIN = 0x0000;
const TAG = 'CapturePathSettings';
const VERSION = 1;

// VIP 快捷捕获模板的独立持久化层。
// 不把配置放进 PersistentStorage：模板是可选设置，且需要损坏时逐字段回退。
export class CapturePathSettings {
  static filePath(context: common.UIAbilityContext): string {
    return context.filesDir + '/capture-path-templates.json';
  }

  static init(context: common.UIAbilityContext): void {
    // 启动时预读一次，验证文件可读；实际捕获仍会通过 load 读取最新配置。
    CapturePathSettings.load(context);
  }

  static load(context: common.UIAbilityContext): CapturePathTemplates {
    const empty = CapturePathTemplate.emptyTemplates();
    try {
      const path = CapturePathSettings.filePath(context);
      if (!fs.accessSync(path)) {
        return empty;
      }
      const raw = fs.readTextSync(path);
      const rec = JSON.parse(raw) as Record<string, Object>;
      const version = rec['version'];
      if (typeof version !== 'number' || version !== VERSION) {
        return empty;
      }
      const quickRaw = rec['quickNotePath'];
      const headingRaw = rec['quickNoteHeading'];
      const clipRaw = rec['clipPath'];
      const quick = typeof quickRaw === 'string' ? quickRaw.trim() : '';
      const heading = typeof headingRaw === 'string' ? headingRaw.trim() : '';
      const clip = typeof clipRaw === 'string' ? clipRaw.trim() : '';
      const quickCheck = CapturePathTemplate.validateTemplate(quick);
      const headingCheck = CapturePathTemplate.validateHeading(heading);
      const clipCheck = CapturePathTemplate.validateTemplate(clip);
      return {
        version: VERSION,
        quickNotePath: quickCheck.empty || quickCheck.valid ? quick : '',
        quickNoteHeading: headingCheck.empty || headingCheck.valid ? heading : '',
        clipPath: clipCheck.empty || clipCheck.valid ? clip : ''
      };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load failed, use empty configuration');
      return empty;
    }
  }

  static save(context: common.UIAbilityContext, templates: CapturePathTemplates): boolean {
    const quickCheck = CapturePathTemplate.validateTemplate(templates.quickNotePath);
    const headingCheck = CapturePathTemplate.validateHeading(templates.quickNoteHeading);
    const clipCheck = CapturePathTemplate.validateTemplate(templates.clipPath);
    if ((!quickCheck.empty && !quickCheck.valid) ||
      (!headingCheck.empty && !headingCheck.valid) ||
      (!clipCheck.empty && !clipCheck.valid)) {
      return false;
    }
    const quick = quickCheck.empty ? '' : templates.quickNotePath.trim();
    const heading = headingCheck.empty ? '' : templates.quickNoteHeading.trim();
    const clip = clipCheck.empty ? '' : templates.clipPath.trim();
    const body = '{"version":' + VERSION + ',"quickNotePath":' + JSON.stringify(quick) +
      ',"quickNoteHeading":' + JSON.stringify(heading) +
      ',"clipPath":' + JSON.stringify(clip) + '}';
    const path = CapturePathSettings.filePath(context);
    const tmp = path + '.tmp';
    try {
      const f = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, body);
      fs.closeSync(f);
      fs.renameSync(tmp, path);
      return true;
    } catch (e) {
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (cleanup) {
        // 临时文件清理失败不覆盖原始保存错误。
      }
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

}
