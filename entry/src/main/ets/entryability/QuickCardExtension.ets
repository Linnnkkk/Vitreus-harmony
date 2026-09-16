import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'QuickCardExt';

// 速记卡片 FormExtensionAbility：v1 纯静态卡（无动态数据更新），
// router 事件由卡片 onClick 的 postCardAction 直达 ShareAbility，不经此处
export default class QuickCardExtension extends FormExtensionAbility {
  onAddForm(want: Want) {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    const formData: Record<string, string> = {};
    return formBindingData.createFormBindingData(formData);
  }

  onRemoveForm(formId: string) {
    hilog.info(DOMAIN, TAG, 'onRemoveForm: %{public}s', formId);
  }
}
