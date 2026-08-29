// VIP 状态服务 —— 华为 IAP Kit 纯客户端模式（无服务端验签，购买结果本地信任）
// 商品：premium_monthly / premium_yearly（自动续订）+ premium_permanent（非消耗型）
// 红线：核心离线免费 / 付费代码开源 / IAP 仅做激活开关
// 注意：沙盒环境下非消耗品 finishPurchase 后 queryPurchases 可能查不到（华为沙盒机制，正式无此问题）
import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'VipService';
const DOMAIN = 0x0F10;

// ── 商品常量（AGC 已配置，散落硬编码禁止）──
export class VipProduct {
  static readonly MONTHLY: string = 'premium_monthly';
  static readonly YEARLY: string = 'premium_yearly';
  static readonly PERMANENT: string = 'premium_permanent';
}

export interface VipProductInfo {
  productId: string;
  title: string;
  priceText: string;
}

export interface PurchaseOutcome {
  ok: boolean;
  message: string;
}

export class VipService {
  // 持久化键（PersistentStorage）
  private static readonly PERM_KEY = 'vipPermanent';
  private static readonly UNTIL_KEY = 'vipUntil'; // 订阅到期时间戳(ms)；永久会员不看此键

  // ── 状态判定（本地缓存，restore/purchase 后更新）──
  static isVip(): boolean {
    const permanent = AppStorage.get<boolean>(VipService.PERM_KEY) === true;
    if (permanent) {
      return true;
    }
    const until = AppStorage.get<number>(VipService.UNTIL_KEY) ?? 0;
    return until > Date.now();
  }

  static vipStatusText(): string {
    if (AppStorage.get<boolean>(VipService.PERM_KEY) === true) {
      return '永久会员';
    }
    const until = AppStorage.get<number>(VipService.UNTIL_KEY) ?? 0;
    if (until > Date.now()) {
      const d = new Date(until);
      return '会员有效期至 ' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
    }
    return '';
  }

  // ── 商品查询（queryProducts 每次只能查一种类型 → 分两查合并）──
  static async queryProducts(ctx: common.UIAbilityContext): Promise<VipProductInfo[]> {
    const out: VipProductInfo[] = [];
    try {
      const subRes = await iap.queryProducts(ctx, {
        productIds: [VipProduct.MONTHLY, VipProduct.YEARLY],
        productType: iap.ProductType.AUTORENEWABLE
      });
      VipService.collect(subRes, out);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `queryProducts(sub) failed: ${err.code} ${err.message}`);
    }
    try {
      const permRes = await iap.queryProducts(ctx, {
        productIds: [VipProduct.PERMANENT],
        productType: iap.ProductType.NONCONSUMABLE
      });
      VipService.collect(permRes, out);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `queryProducts(nonc) failed: ${err.code} ${err.message}`);
    }
    // 固定展示顺序：月 → 年 → 永久
    const order: string[] = [VipProduct.MONTHLY, VipProduct.YEARLY, VipProduct.PERMANENT];
    out.sort((a: VipProductInfo, b: VipProductInfo) => order.indexOf(a.productId) - order.indexOf(b.productId));
    return out;
  }

  private static collect(res: Object, out: VipProductInfo[]): void {
    const products = (res as Record<string, Object>)['products'] as Object[] | undefined;
    if (!Array.isArray(products)) {
      hilog.warn(DOMAIN, TAG, 'queryProducts: no products array, keys=' + JSON.stringify(Object.keys(res)));
      return;
    }
    for (const p0 of products) {
      const rec = p0 as Record<string, Object>;
      hilog.info(DOMAIN, TAG, 'product raw: ' + JSON.stringify(rec).slice(0, 400));
      // 价格字段名按华为文档为 formattedPrice；旧字段 priceFormatted 兜底（真机日志校准）
      const price = (rec['formattedPrice'] ?? rec['priceFormatted'] ?? '') as string;
      const title = (rec['title'] ?? rec['name'] ?? rec['productId']) as string;
      out.push({ productId: rec['productId'] as string, title: title, priceText: price !== '' ? price : '--' });
    }
  }

  // ── 发起购买：createPurchase → 先发权益 → 再 finishPurchase（发货确认）──
  static async purchase(ctx: common.UIAbilityContext, productId: string, productType: iap.ProductType): Promise<PurchaseOutcome> {
    try {
      const param: iap.PurchaseParameter = {
        productId: productId,
        productType: productType
      };
      const result = await iap.createPurchase(ctx, param);
      const data = result.purchaseData;
      hilog.info(DOMAIN, TAG, 'createPurchase ok, purchaseData: ' + JSON.stringify(data).slice(0, 600));

      // ① 先发放权益（本地标记）
      VipService.grant(productId, data);

      // ② 再确认发货
      await VipService.finish(ctx, data);

      return { ok: true, message: '开通成功' };
    } catch (e) {
      const err = e as BusinessError;
      // 用户主动取消收银台不是错误提示场景（华为 IAP 用户取消码 100186）
      if (err.code === 100186) {
        return { ok: false, message: '' };
      }
      hilog.error(DOMAIN, TAG, `createPurchase failed: ${err.code} ${err.message}`);
      return { ok: false, message: '支付未完成（' + err.code + '），请稍后重试' };
    }
  }

  // ArkTS 不支持 Array.isArray 类型窄化：显式转换避免 any/unknown
  private static toArr(data: Object | Object[] | undefined): Object[] {
    if (data === undefined || data === null) {
      return [];
    }
    if (Array.isArray(data)) {
      return data as Object[];
    }
    return [data as Object];
  }

  private static grant(productId: string, purchaseData: Object | Object[] | undefined): void {
    if (productId === VipProduct.PERMANENT) {
      AppStorage.setOrCreate(VipService.PERM_KEY, true);
      return;
    }
    // 订阅：从购买数据解析到期时间（字段名按文档 + 多名兜底，真机日志校准）
    let until = 0;
    try {
      const arr: Object[] = VipService.toArr(purchaseData);
      for (const item of arr) {
        const rec = item as Record<string, Object>;
        const appex = rec['appexPayload'] as string | undefined;
        if (appex) {
          const info = JSON.parse(appex) as Record<string, Object>;
          const exp = (info['expirationDate'] ?? info['expireDate'] ?? info['subscriptionExpirationDate']) as number | undefined;
          if (typeof exp === 'number' && exp > until) {
            until = exp;
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'grant: parse appexPayload failed');
    }
    if (until <= 0) {
      until = Date.now() + 31 * 24 * 3600 * 1000; // 解析不到时按周期兜底（月/年至少 31 天权益，宁多勿少）
    }
    AppStorage.setOrCreate(VipService.UNTIL_KEY, until);
    AppStorage.setOrCreate(VipService.PERM_KEY, false);
  }

  private static async finish(ctx: common.UIAbilityContext, purchaseData: Object | Object[] | undefined): Promise<void> {
    try {
      const arr: Object[] = VipService.toArr(purchaseData);
      for (const item of arr) {
        const rec = item as Record<string, Object>;
        const token = rec['purchaseToken'] as string | undefined;
        const orderId = rec['purchaseOrderId'] as string | undefined;
        const typeNum = Number(rec['productType']);
        if (token && orderId && typeNum > 0) {
          const finishParam: iap.FinishPurchaseParameter = {
            productType: typeNum,
            purchaseToken: token,
            purchaseOrderId: orderId
          };
          await iap.finishPurchase(ctx, finishParam);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `finishPurchase failed: ${err.code} ${err.message}`);
    }
  }

  // ── 启动恢复：queryPurchases 两类各查一次，重建权益状态 ──
  // 策略：查询成功 → 如实写入（正式行为正确）；查询失败（网络等）→ 保留旧值不动。
  // 沙盒注意：非消耗品 finishPurchase 后 queryPurchases 可能查不到（华为沙盒机制），
  // 沙盒测试看到权益被清属正常现象，正式环境无此问题，无需特判。
  static async restore(ctx: common.UIAbilityContext): Promise<void> {
    let permanent = false;
    let until = 0;
    let noncOk = false;
    let subOk = false;

    try {
      const nonc = await iap.queryPurchases(ctx, { productType: iap.ProductType.NONCONSUMABLE });
      const noncList = VipService.pickPurchases(nonc);
      for (const rec of noncList) {
        if (rec['productId'] === VipProduct.PERMANENT) {
          permanent = true;
        }
      }
      noncOk = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `queryPurchases(nonc) failed: ${err.code} ${err.message}`);
    }

    try {
      const sub = await iap.queryPurchases(ctx, { productType: iap.ProductType.AUTORENEWABLE });
      const subList = VipService.pickPurchases(sub);
      for (const rec of subList) {
        // 订阅状态判断：取 appexPayload 到期时间（自动续订中的记录到期时间在未来）
        try {
          const appex = rec['appexPayload'] as string | undefined;
          if (appex) {
            const info = JSON.parse(appex) as Record<string, Object>;
            const exp = (info['expirationDate'] ?? info['expireDate'] ?? info['subscriptionExpirationDate']) as number | undefined;
            if (typeof exp === 'number' && exp > until) {
              until = exp;
            }
          }
        } catch (e) {
          // 单条解析失败继续下一条
        }
      }
      subOk = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `queryPurchases(sub) failed: ${err.code} ${err.message}`);
    }

    if (noncOk) {
      AppStorage.setOrCreate(VipService.PERM_KEY, permanent);
    }
    if (subOk) {
      AppStorage.setOrCreate(VipService.UNTIL_KEY, until);
    }
    hilog.info(DOMAIN, TAG, `restore done: noncOk=${noncOk} permanent=${permanent} subOk=${subOk} until=${until} isVip=${VipService.isVip()}`);
  }

  private static pickPurchases(res: Object): Record<string, Object>[] {
    const rec = res as Record<string, Object>;
    const listName = ['purchaseDatas', 'purchaseData', 'purchases'].find((k: string) => Array.isArray(rec[k]));
    if (!listName) {
      hilog.warn(DOMAIN, TAG, 'queryPurchases: unknown list field, keys=' + JSON.stringify(Object.keys(rec)));
      return [];
    }
    return rec[listName] as Record<string, Object>[];
  }
}
