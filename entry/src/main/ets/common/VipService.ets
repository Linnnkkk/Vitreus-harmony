// VIP 状态服务 —— 华为 IAP Kit 纯客户端模式（无服务端验签，购买结果本地信任）
// 商品：premium_monthly / premium_yearly（自动续订）+ premium_permanent（非消耗型）
// 红线：核心离线免费 / 付费代码开源 / IAP 仅做激活开关
// 注意：沙盒环境下非消耗品 finishPurchase 后 queryPurchases 可能查不到（华为沙盒机制，正式无此问题）
import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

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
  // 最近一次 IAP 环境错误（UI 透出，帮定位：未登录华为账号/debug指纹未登AGC/未签约）
  static lastEnvError: string = '';

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
      const days = Math.ceil((until - Date.now()) / 86400000);
      const base = '会员有效期至 ' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
      if (days <= 7) {
        return base + '（剩 ' + days + ' 天，自动续费中，可在华为订阅管理取消）';
      }
      return base + '（剩 ' + days + ' 天）';
    }
    return '';
  }

  // ── 商品查询（queryProducts 每次只能查一种类型 → 分两查合并）──
  static async queryProducts(ctx: common.UIAbilityContext): Promise<VipProductInfo[]> {
    const out: VipProductInfo[] = [];
    VipService.lastEnvError = '';
    // 环境诊断先行（官方 queryEnvironmentStatus：区分 账号未登录/服务未开通/签名问题）
    try {
      const env = await iap.queryEnvironmentStatus(ctx);
      hilog.info(DOMAIN, TAG, 'queryEnvironmentStatus ok: ' + JSON.stringify(env).slice(0, 200));
    } catch (e) {
      const err = e as BusinessError;
      VipService.lastEnvError = 'IAP环境未就绪（' + err.code + '）：' + err.message + ' — 逐项排查：①真机华为账号已登录 ②AGC沙盒测试已添加该账号 ③应用内购买服务已开通';
      hilog.error(DOMAIN, TAG, `queryEnvironmentStatus failed: ${err.code} ${err.message}`);
      return out;
    }
    try {
      const subRes = await iap.queryProducts(ctx, {
        productIds: [VipProduct.MONTHLY, VipProduct.YEARLY],
        productType: iap.ProductType.AUTORENEWABLE
      });
      VipService.collect(subRes, out);
    } catch (e) {
      const err = e as BusinessError;
      VipService.lastEnvError = 'IAP 查询失败（错误 ' + err.code + '）：请确认已登录华为账号/AGC指纹';
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

      // ② 确认发货放后台：grant 已写本地权益，finish 仅华为侧记账——不阻塞返回（省 1-2s 网络往返）
      VipService.finish(ctx, data);

      return { ok: true, message: '开通成功' };
    } catch (e) {
      const err = e as BusinessError;
      // 用户主动取消收银台不是错误提示场景（华为 IAP 用户取消码 100186）
      if (err.code === 100186) {
        return { ok: false, message: '' };
      }
      hilog.error(DOMAIN, TAG, `createPurchase failed: ${err.code} ${err.message}`);
      // 1001860004 在"已有生效订阅再买订阅"场景=华为拒绝重复订阅（错误码表义"频繁"，实为重复购买被拒）
      if (err.code === 1001860004) {
        return { ok: false, message: '你已有生效中的订阅，请勿重复购买。如需切换方案，请先在 华为账号-付款与购买-订阅 中取消当前订阅' };
      }
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

  // ── 统一购买记录解析（购买 grant 与查询 restore 共用——杜绝两套解析不一致的 bug）──
  // 兼容形态：①裸 productId 字符串包装 ②JSON 直取 ③appexPayload ④jwsSubscriptionStatus/jwsPurchaseOrder
  private static extractExp(rec: Record<string, Object>): number {
    // appexPayload 直取（createPurchase 返回的形态之一）
    const appex = rec['appexPayload'] as string | undefined;
    if (appex) {
      try {
        const info = JSON.parse(appex) as Record<string, Object>;
        const n = VipService.toNum(info['expiresTime'] ?? info['expirationDate'] ?? info['expireDate'] ?? info['subscriptionExpirationDate']);
        if (!isNaN(n)) {
          return n;
        }
      } catch (e) {
        // 落到 JWS 分支
      }
    }
    // JWS 订阅状态容器（查询/部分购买返回的形态）
    const jwsSub = rec['jwsSubscriptionStatus'] as string | undefined;
    if (jwsSub) {
      const payload = VipService.decodeJwsPayload(jwsSub);
      if (payload !== null) {
        const last = (payload['lastSubscriptionStatus'] ?? payload['subscriptionStatus']) as Record<string, Object> | undefined;
        const src = last ?? payload;
        // expiresTime 必须首位（日志6实锤真名；此前漏列导致 grant 走 JWS 形态时解析失败落兜底——与 restore 分支对齐）
        const n = VipService.toNum(src['expiresTime'] ?? src['expirationDate'] ?? src['expireDate'] ?? src['subscriptionExpirationDate'] ?? src['expirationTime']);
        if (!isNaN(n)) {
          return n;
        }
      }
    }
    return 0;
  }

  private static toNum(v: Object | undefined): number {
    if (typeof v === 'number') {
      return v;
    }
    if (typeof v === 'string' && v !== '') {
      const n = Number(v);
      if (!isNaN(n)) {
        return n;
      }
    }
    return NaN;
  }

  private static grant(productId: string, purchaseData: Object | Object[] | undefined): void {
    if (productId === VipProduct.PERMANENT) {
      AppStorage.setOrCreate(VipService.PERM_KEY, true);
      AppStorage.setOrCreate('vipSubProduct', ''); // 永久在手，订阅档标记清空
      return;
    }
    AppStorage.setOrCreate('vipSubProduct', productId); // 记录当前订阅档（月/年），UI 判定"当前方案"用
    // 到期解析：与 restore 同源的统一解析器（appexPayload/JWS 双形态），杜绝两套解析不一致
    let until = 0;
    const arr: Object[] = VipService.toArr(purchaseData);
    for (const item of arr) {
      const rec = item as Record<string, Object>;
      const exp = VipService.extractExp(rec);
      if (exp > until) {
        until = exp;
      }
    }
    if (until <= 0) {
      // 兜底按档位分周期（此前写死 31 天导致包年买完只显示 31 天的恶性体验 bug）
      const fallbackDays = productId === VipProduct.YEARLY ? 366 : 31;
      until = Date.now() + fallbackDays * 24 * 3600 * 1000;
      hilog.warn(DOMAIN, TAG, `grant: exp parse missed, fallback ${fallbackDays}d for ${productId}`);
    } else {
      hilog.info(DOMAIN, TAG, `grant: exp parsed = ${until}`);
    }
    // 叠加语义：与现有权益期取最大（买月后再买年/已订中途再买，权益只增不回退）
    const curUntil = AppStorage.get<number>(VipService.UNTIL_KEY) ?? 0;
    if (curUntil > until) {
      until = curUntil;
    }
    AppStorage.setOrCreate(VipService.UNTIL_KEY, until);
    // PERM 只增不减守卫：永久一旦在手，订阅补单/购买路径不得清除（2026-08-30 日志5实锤：owned兜底补月单时把已恢复的永久覆盖成false导致重启掉永久）
    // 唯一清除途径 = 未来感知到华为侧退款状态时的显式回收
    if (AppStorage.get<boolean>(VipService.PERM_KEY) !== true) {
      AppStorage.setOrCreate(VipService.PERM_KEY, false);
    }
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
  // 策略（2026-08-30 修正）：只增不减——查到有效权益才写入。
  // 原"如实写入"在沙盒/查询时序下会把已购权益清空（finish 后沙盒订单不持久，
  // 冷启动 restore 得到空结果覆盖本地 → 用户实测"会员突然没了"）。
  // 订阅到期由 until 时间戳自然失效；永久型 once granted（退款白嫖风险个人开发者可接受）。
  static async restore(ctx: common.UIAbilityContext): Promise<void> {
    let permanent = false;
    let until = 0;
    let noncOk = false;
    let subOk = false;

    try {
      const nonc = await iap.queryPurchases(ctx, { productType: iap.ProductType.NONCONSUMABLE });
      const noncList = VipService.pickPurchases(nonc);
      for (const rec of noncList) {
        const pid = rec['productId'] as string | undefined;
        if (pid === VipProduct.PERMANENT) {
          permanent = true;
        } else {
          // 真机日志实锤：非消耗记录形态 {type, jwsPurchaseOrder}——productId 在 JWS payload 里
          const jws = rec['jwsPurchaseOrder'] as string | undefined;
          const payload = jws ? VipService.decodeJwsPayload(jws) : null;
          if (payload !== null) {
            // 退款感知埋点：全量 dump 字段——真实退款案例出现时，日志直接暴露状态字段名（如 purchaseState/orderStatus），届时精确回收
            hilog.info(DOMAIN, TAG, 'restore nonc jws keys=' + JSON.stringify(Object.keys(payload)).slice(0, 250) + ' raw=' + JSON.stringify(payload).slice(0, 400));
            const jwsPid = payload['productId'] as string | undefined;
            if (jwsPid === VipProduct.PERMANENT || jwsPid === VipProduct.MONTHLY || jwsPid === VipProduct.YEARLY) {
              if (jwsPid === VipProduct.PERMANENT) {
                permanent = true;
              }
            } else {
              hilog.warn(DOMAIN, TAG, 'restore nonc: jws productId unrecognized, keys=' + JSON.stringify(Object.keys(payload)).slice(0, 200));
            }
          } else {
            hilog.warn(DOMAIN, TAG, 'restore nonc: no productId/jws, keys=' + JSON.stringify(Object.keys(rec)).slice(0, 200));
          }
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
            const exp = VipService.extractExp(rec);
            if (exp > until) {
              until = exp;
              const subPid = rec['productId'] as string | undefined;
              if (subPid === VipProduct.MONTHLY || subPid === VipProduct.YEARLY) {
                AppStorage.setOrCreate('vipSubProduct', subPid);
              }
            }
          } else {
            // 真机日志实锤：订阅记录形态 {type, jwsSubscriptionStatus}——到期在 JWS payload 里
            const jws = rec['jwsSubscriptionStatus'] as string | undefined;
            if (jws) {
              const payload = VipService.decodeJwsPayload(jws);
              if (payload !== null) {
                // 订阅状态容器：lastSubscriptionStatus.expiresTime（官方字段，文档+日志6双实锤；多字段兼容 + 字符串数字兼容）
                const last = (payload['lastSubscriptionStatus'] ?? payload['subscriptionStatus']) as Record<string, Object> | undefined;
                const src = last ?? payload;
                hilog.info(DOMAIN, TAG, 'restore sub: jws lastSubscriptionStatus full=' + JSON.stringify(last).slice(0, 1200));
                const expRaw = src['expiresTime'] ?? src['expirationDate'] ?? src['expireDate'] ?? src['subscriptionExpirationDate'] ?? src['expirationTime'];
                const expNum = typeof expRaw === 'number' ? expRaw as number : (typeof expRaw === 'string' && expRaw !== '' ? Number(expRaw) : NaN);
                // 官方 status 枚举(iap-data-model)：1=生效中 2=已到期 3=尝试扣费 5=撤销
                // 仅生效/尝试扣费(宽限期)贡献权益——撤销(5)的订阅 expiresTime 可能仍是未来值，不过滤=白嫖漏洞
                const stActive = String(src['status'] ?? '1') === '1' || String(src['status'] ?? '1') === '3';
                if (stActive && !isNaN(expNum) && expNum > until) {
                  until = expNum;
                }
                // productId 不在 lastSubscriptionStatus 顶层——在嵌套的 lastPurchaseOrder 里（2026-08-30 日志6 完整dump实锤）
                const order = src['lastPurchaseOrder'] as Record<string, Object> | undefined;
                const jwsPid = (src['productId'] ?? (order !== undefined ? order['productId'] : undefined)) as string | undefined;
                if (stActive && (jwsPid === VipProduct.MONTHLY || jwsPid === VipProduct.YEARLY)) {
                  AppStorage.setOrCreate('vipSubProduct', jwsPid);
                }
              }
            } else {
              hilog.warn(DOMAIN, TAG, 'restore sub: no appexPayload/jws, keys=' + JSON.stringify(Object.keys(rec)).slice(0, 200));
            }
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'restore sub: parse appexPayload failed, keys=' + JSON.stringify(Object.keys(rec)).slice(0, 200));
        }
      }
      subOk = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `queryPurchases(sub) failed: ${err.code} ${err.message}`);
    }

    // 只增不减：仅在查到有效权益时写入，查询空结果不触碰本地状态
    if (noncOk && permanent) {
      AppStorage.setOrCreate(VipService.PERM_KEY, true);
    }
    if (subOk && until > Date.now()) {
      // 写入与本地取 max（与 grant 同语义——防华为侧记录回退覆盖掉更长的本地权益，如退订年只剩月记录）
      const curUntil = AppStorage.get<number>(VipService.UNTIL_KEY) ?? 0;
      if (curUntil > until) {
        until = curUntil;
      }
      AppStorage.setOrCreate(VipService.UNTIL_KEY, until);
    }
    // 永久掉单兜底（仅永久类——2026-08-30 日志6：沙盒 queryPurchases(nonc) 订单时隐时现 total=0 导致永久丢失）
    // 订阅不走此兜底（expiresTime 真值已可解析；owned 返回"所有已订购"含过期记录，兜底订阅会造成无限续命）
    if (!permanent) {
      try {
        const noncOwned = await iap.queryOwnedPurchases(ctx, { productType: iap.ProductType.NONCONSUMABLE });
        const ownedList = VipService.pickPurchases(noncOwned as Object);
        for (const rec of ownedList) {
          let pid = rec['productId'] as string | undefined;
          if (pid !== VipProduct.PERMANENT) {
            const jws = rec['jwsPurchaseOrder'] as string | undefined;
            const payload = jws ? VipService.decodeJwsPayload(jws) : null;
            if (payload !== null) {
              const p = payload['productId'] as string | undefined;
              if (p === VipProduct.PERMANENT) {
                pid = VipProduct.PERMANENT;
              }
            }
          }
          if (pid === VipProduct.PERMANENT) {
            AppStorage.setOrCreate(VipService.PERM_KEY, true);
            hilog.info(DOMAIN, TAG, 'restore: permanent recovered from owned');
            break;
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'owned permanent fallback failed');
      }
    }
    // 写入后回读验证：区分 解析失败(没查到) / 写入失败 / 持久化未生效 三种情况
    const permAfter = AppStorage.get<boolean>(VipService.PERM_KEY);
    const untilAfter = AppStorage.get<number>(VipService.UNTIL_KEY) ?? 0;
    hilog.info(DOMAIN, TAG, `restore done: noncOk=${noncOk} permanent=${permanent} subOk=${subOk} until=${until} | after-read: perm=${permAfter} until=${untilAfter} isVip=${VipService.isVip()}`);
  }

  // JWS payload 解码（订阅状态容器：jwsSubscriptionStatus = header.payload.signature 的 base64url）
  // 纯客户端模式不验签，只解 payload 取订阅状态（华为 SubGroupStatusPayload）
  private static decodeJwsPayload(jws: string): Record<string, Object> | null {
    try {
      const parts = jws.split('.');
      if (parts.length < 2) {
        return null;
      }
      let b = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      while (b.length % 4 !== 0) {
        b += '=';
      }
      const u8 = new util.Base64Helper().decodeSync(b);
      let raw = '';
      for (let i = 0; i < u8.length; i++) {
        raw += String.fromCharCode(u8[i]);
      }
      return JSON.parse(raw) as Record<string, Object>;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'decodeJwsPayload failed');
      return null;
    }
  }

  private static pickPurchases(res: Object): Record<string, Object>[] {
    const rec = res as Record<string, Object>;
    // 真机日志实锤：华为 queryPurchases 返回的列表字段名是 purchaseDataList（2026-08-30 日志 keys=["purchaseDataList"]）
    const listName = ['purchaseDataList', 'purchaseDatas', 'purchaseData', 'purchases', 'productList'].find((k: string) => Array.isArray(rec[k]));
    if (!listName) {
      hilog.warn(DOMAIN, TAG, 'queryPurchases: unknown list field, keys=' + JSON.stringify(Object.keys(rec)));
      return [];
    }
    // 华为返回的列表元素可能是 JSON 字符串而非对象（purchaseDataList:["{...}"]）——统一 parse 成对象
    const rawList = rec[listName] as Object[];
    const out: Record<string, Object>[] = [];
    let strCnt = 0;
    for (const item of rawList) {
      if (typeof item === 'string') {
        strCnt++;
        try {
          out.push(JSON.parse(item) as Record<string, Object>);
        } catch (e) {
          // 裸 productId 字符串（非消耗类返回 ["premium_permanent"] 形态——真机日志实锤）——构造成记录
          if (item === VipProduct.PERMANENT || item === VipProduct.MONTHLY || item === VipProduct.YEARLY) {
            const wrap: Record<string, Object> = {};
            wrap['productId'] = item;
            out.push(wrap);
          } else {
            hilog.warn(DOMAIN, TAG, 'pickPurchases: unrecognized string element: ' + String(item).slice(0, 120));
          }
        }
      } else {
        out.push(item as Record<string, Object>);
      }
    }
    hilog.info(DOMAIN, TAG, `pickPurchases: total=${rawList.length} parsed=${out.length} strElems=${strCnt}`);
    return out;
  }
}
