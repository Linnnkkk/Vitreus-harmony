// VIP 状态服务 —— 开发期 Mock，IAP 签约后切换真实现（USE_MOCK=false + 接 @kit.IapKit）
// 红线不变：核心离线免费 / 付费代码开源 / IAP 仅做激活开关
import { persistentStorage } from '@kit.ArkUI';

const USE_MOCK = true; // TODO(IAP)：签约后置 false，接 queryProduct/purchase/obtainOwnedPurchases

export class VipService {
  private static KEY = 'vipActive';

  static isVip(): boolean {
    if (USE_MOCK) {
      // 开发期：读 mock 开关（持久），默认 false 走购买引导流程；调试时在面板里可开
      return persistentStorage.get<boolean>(VipService.KEY) === true;
    }
    // 真实判定（IAP 接入后）：永久购买记录 || 订阅有效期 > now
    return false; // 占位
  }

  // ---- Mock 通道（仅 USE_MOCK 时有效，用于真机调试全链路）----
  static setMockVip(on: boolean): void {
    persistentStorage.setOrCreate(VipService.KEY, on);
  }
}
