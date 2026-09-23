# Vitreus 1.3.0 — Obsidian 1.13.7 兼容与快捷捕获增强

**Vitreus 1.3.0**（versionCode 1000009）带来 Obsidian 1.13.7 组件包支持，并继续完善快捷捕获和桌面速记体验。

| Item | Version |
|---|---|
| HarmonyOS | 6.0.2(22)+ · phone / tablet / 2in1 |
| Node.js | v24.2.0（libnode.so.137，交叉编译，--jitless） |
| Embedded server | ignis 0.8.12（含 Obsidian 1.13 适配层） |
| Obsidian components | 1.12.7 / 1.13.7（均已真机验证） |
| Vitreus | 1.3.0 / versionCode 1000009 |

> Obsidian 组件包由用户自备。Vitreus 不包含、不分发 Obsidian 受版权保护的内容；请通过应用内「更换 Obsidian 组件包」导入你合法取得的官方组件包。

---

## ✨ 主要更新

### Obsidian 1.13.7 兼容

- 支持导入并运行 Obsidian 1.13.7 官方组件包。
- 保留对 Obsidian 1.12.7 组件包的兼容。
- 内嵌 ignis 0.8.12 提供 1.13 适配层，包括启动 IPC 通道版本探测、settings 面板兼容处理和 unpacked i18n 兜底。
- 本地模式与远程模式均已完成真机验证。

### 快捷捕获增强

- 基础速记和网页剪藏继续免费。
- 支持自定义速记路径和剪藏路径。
- 支持动态路径变量，以及按标题追加内容。
- 会员页同步说明「解锁伺服器 + 快捷捕获增强」权益，避免把已发布的基础捕获重复包装成新卖点。

### 1×2 速记小组件

- 桌面速记卡片调整为轻量横条布局。
- 保留「点击进入速记 → 保存 → 退出」核心链路。
- 不改变原有分享速记、冷启动定位库和保存逻辑。

### 一次性兼容性公告

- 首次使用时提示更新 Obsidian 组件包。
- 用户点击「知道了」后，已读状态写入应用文件目录。
- 完全退出并重启 APP 后不再重复弹出；本地模式和模式选择页共享状态。

---

## 🧪 已验证场景

- Obsidian 1.13.7 组件包导入与启动 ✅
- Obsidian 1.12.7 组件包兼容性保留 ✅
- 本地模式 / 远程模式访问 ✅
- 1×2 速记小组件进入速记、保存与退出 ✅
- 快捷捕获基础链路与路径设置 ✅
- 兼容性公告持久化代码构建通过；需在目标设备上确认「知道了 → 完全退出 → 重开」不再重复弹出 ✅

---

## 📦 版本信息

- versionName：1.3.0
- versionCode：1000009
- GitHub：<https://github.com/Linnnkkk/Vitreus-harmony>

**声明**：本应用为独立第三方开源项目（AGPL v3），与 Obsidian / Dynalist Inc. 及 ignis 项目无隶属或背书关系。
