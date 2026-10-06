# Vitreus 1.3.3 — 伺服器加密连接（HTTPS）与官方 ignis 0.8.16

**Vitreus 1.3.3**（versionCode 1000012）新增伺服器模式的 **加密连接（HTTPS）**，并把内嵌服务从 `0.8.14-mod` 跟进到官方 ignis **`0.8.16-mod`**。

| Item | Version |
|---|---|
| HarmonyOS | 6.0.2(22)+ · phone / tablet / 2in1 |
| Node.js | v24.2.0（libnode.so.137，交叉编译，--jitless） |
| Embedded server | ignis 0.8.16-mod（bundle v22，基于官方 ignis 0.8.16 基线） |
| Obsidian components | 1.12.7 / 1.13.7（均支持） |
| Vitreus | 1.3.3 / versionCode 1000012 |

> Obsidian 组件包由用户自备。Vitreus 不包含、不分发 Obsidian 受版权保护的内容；请通过应用内「更换 Obsidian 组件包」导入你合法取得的官方组件包。

---

## 🔐 伺服器加密连接（HTTPS）

- 伺服器页新增「加密连接（HTTPS）」开关，开启后局域网访问全程 TLS 加密，同一 Wi-Fi 下的其他人无法嗅探笔记内容、账号与实时同步流量。
- **默认关闭**：家庭 Wi-Fi 保持“输入地址即用”的零门槛；在咖啡馆、机场等不信任的网络请开启。
- **证书全自动**：手机端首次开启时自动生成 ECDSA P-256 自签证书（Node 自带 `crypto`，无第三方依赖，毫秒级），写入应用私有目录。
- **指纹可比对**：运行中页面显示证书 SHA-256 指纹，浏览器首次放行时可核对。
- **证书稳定**：只在“新 IP 不在证书里”或“有效期不足 30 天”时重签，旧 IP 保留在证书里，Wi-Fi / 个人热点来回切换不必反复放行。
- **叠加保护**：与 Digest 鉴权、失败锁定叠加；实时同步自动使用 `wss`。
- **首次访问需手动放行**（自签证书的固有特点）：浏览器会提示“连接不安全 / 证书无效”，选“高级 → 继续访问”（Safari：“显示详细信息 → 访问此网站”）。页面内有同样的说明。
- 切换开关会立即以新档位重启伺服器，地址协议随之变化（`http://` ⇄ `https://`），并在页面提示。

## 🧩 内嵌服务跟进官方 ignis 0.8.16

由 `0.8.14-mod` 升至 `0.8.16-mod`（合并官方 0.8.15 / 0.8.16）：

- 服务器暂时连不上时的编辑，重连后不再被旧数据回滚。
- 保存后立刻删除的文件保持已删除；同一路径的写入 / 删除 / `utimes` 严格按序落盘。
- 文件创建时间按 birth time 上报，`ctimeMs` 更准确。
- 新开窗口的笔记改在标签页里打开；忽略规则编辑即存，已覆盖的建议自动隐藏。
- 上游移除 demo 模式，内嵌包同步去掉相关资源。
- Vitreus 定制（LanShare、鉴权、1.13 适配层、条款缓存等）全部保留。

---

## 📦 版本信息

- versionName：1.3.3
- versionCode：1000012
- 内嵌 ignis：0.8.16-mod（bundle v22）
- GitHub：<https://github.com/Linnnkkk/Vitreus-harmony>

**声明**：本应用为独立第三方开源项目（AGPL v3），与 Obsidian / Dynalist Inc. 及 ignis 项目无隶属或背书关系。
