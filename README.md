<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" alt="Vitreus" width="96" />
</p>

<h1 align="center">Vitreus</h1>
<p align="center">在鸿蒙设备上使用 Obsidian</p>
<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-6.0.2%2B-blue" alt="HarmonyOS 6.0.2+" />
  <img src="https://img.shields.io/badge/Version-1.4.1-purple" alt="1.4.1" />
  <img src="https://img.shields.io/badge/license-AGPL--3.0-orange" alt="AGPL-3.0" />
</p>

Vitreus 是非官方的 Obsidian 兼容运行环境，面向鸿蒙手机、平板和 PC。它不另做一套笔记编辑器，而是通过 [ignis](https://github.com/Nystik-gh/ignis) 运行用户自己的 Obsidian 环境。

**本地运行、远程服务器连接、基础速记和网页剪藏永久免费。** 笔记保存在你的设备或你配置的服务器上，无需经过 Vitreus 托管服务。

[应用市场](https://appgallery.huawei.com/app/detail?id=com.vitreus.app) · [使用反馈](https://github.com/Linnnkkk/Vitreus-harmony/issues) · [1.4.1 更新说明](docs/RELEASE-v1.4.1-notes.md) · [隐私政策](https://linnnkkk.github.io/Vitreus-harmony/privacy.html)

> 1.4.1 正在准备提交应用市场；商店实际可下载版本及审核进度以应用市场页面为准。

## 1.4.1 更新

- 可在配置页开关“记住上次使用的模式”
- 本地启动界面更简洁
- 记住上次选择的本地或远程保存位置，不再影响应用的启动模式
- 可清除服务器配置，修复部分情况下已保存密码丢失的问题。
- 改善启动时切到后台再返回的恢复体验，提升部分插件网络请求的兼容性。

## 功能

| 功能 | 用途 | 普通用户 | 会员用户 |
|---|---|:---:|:---:|
| 本地运行 | 在设备上离线使用自己的笔记库 | ✓ | ✓ |
| 远程服务器 | 连接已有 ignis 服务，浏览和编辑笔记 | ✓ | ✓ |
| 基础速记 | 从系统分享、桌面卡片等入口记录文字 | ✓ | ✓ |
| 网页剪藏 | 分享网页并保存为 Markdown | ✓ | ✓ |
| 伺服器模式 | 让局域网设备通过浏览器访问手机笔记 | — | ✓ |
| AI 连接 | 通过局域网 MCP 向电脑 AI 授权笔记访问 | — | ✓ |
| 自定义存储规则 | 自定义路径、日期与站点变量、按标题追加 | — | ✓ |

会员提供包月、包年和永久买断，通过华为应用内支付，支持恢复购买。未开通或到期不影响免费功能及已有笔记。Obsidian 官方 Sync、Publish、服务器费用和第三方付费服务不包含在内。

## 开始使用

### 本地运行

1. 从正规来源自行获取兼容的 Obsidian 桌面核心组件：`obsidian.asar` 或 `obsidian.asar.gz`。
2. 打开 Vitreus，选择「本地运行」，按提示导入组件。
3. 创建或导入笔记库；后续可离线使用。速记、剪藏保存规则及远程地址在「配置」中管理。

Vitreus 不包含、不分发 Obsidian 核心组件。兼容范围目前为 **1.12.7–1.14.4**；主题、插件及外部服务受版本和设备环境影响，不保证全部桌面插件可用。

### 分享内容写入今日笔记

会员可在「配置」的自定义存储规则中选择「写进日记」，再按自己笔记库的实际目录调整速记路径，例如 `日记/{{今天}}.md`，并保存规则。`{{今天}}` 展开为 `yyyy-MM-dd`；此设置不会自动读取 Obsidian 的日记目录或日期格式。

纯文字分享会追加到当天目标笔记；网页剪藏正文仍保存为独立 Markdown 文件，在目标笔记中追加链接索引，不会将整篇网页正文内嵌进日记。本地与远程库均遵循这一规则。

### 远程服务器

选择「远程服务器」，填写已有 ignis 服务的根地址和认证信息。App 直接连接你配置的服务器；目前不支持 `/ignis/` 等子路径部署。使用不受信任的网络时，应使用 HTTPS。

### 伺服器与 AI 连接

两项服务均面向**局域网**，可以同时开启。它们与免费远程模式的区别是：远程模式由手机连接服务器，这两项由手机提供服务。

- **伺服器模式**：设置访问账号密码后，其他设备通过浏览器访问页面给出的地址；可选 HTTPS。
- **AI 连接**：选择允许访问的笔记库，默认只读。19 个 MCP 工具覆盖笔记读写、标签、属性、链接、待办、大纲及备份恢复；不提供任意 Shell、插件执行或删除笔记。电脑需安装 MCP 连接器，详细教程见 App。

电脑连接器要求 Node.js 20+。当前 npm 分发版本为预发布包：

```bash
npm install --global @liiink/vitreus-ai-connector@1.3.9-beta.1
vitreus-ai pair
```

随后按对应 Agent 教程注册 `vitreus-ai serve`。配对信息只应粘贴到可信的本机终端，不要发送给 AI 对话或提交到仓库。连接器不包含模型或额度；本仓库连接器源码可能领先于 npm 分发版本，详见[连接器说明](tools/ai-connector/README.md)。

## 兼容与安全边界

- 本地环境由 ArkTS / ArkWeb、内嵌 Node.js 与 ignis 兼容层组成，并非 Obsidian 官方客户端。
- 网络隔离、防火墙和系统后台限制可能影响服务可达性；不提供内置公网隧道。
- AI 编辑需要明确授权，写入核对读取版本并备份。它不构成对外部同步程序或其他写入者的全局事务保证。
- 基础速记与网页剪藏也可选择已配置的远程库；多设备同时编辑仍需留意同步与覆盖风险。

## 源码与构建

本仓库包含 ArkTS 界面、原生 Node.js 嵌入层、内嵌服务 bundle 及电脑连接器。定制服务源码在 [Linnnkkk/ignis](https://github.com/Linnnkkk/ignis/tree/work/1.3.7-ignis-0.8.18)。

**公开仓库不包含会员购买模块、签名配置和证书，不能直接复现完整商店构建。** 本地运行还需要 `libnode.so.137`，参见 [Releases](https://github.com/Linnnkkk/Vitreus-harmony/releases) 中的运行时附件；开发工具为 DevEco Studio。请使用自己的签名材料，不要提交用户组件、笔记库或凭据。

- 应用源码：`entry/src/main/ets/`、`entry/src/main/cpp/`
- 电脑连接器：`tools/ai-connector/`
- 本地隔离回归：`node --test tools/*.test.cjs tools/ai-connector/test/*.test.js`，其中跨仓库联调需设置 `VITREUS_IGNIS_SOURCE` 指向定制 ignis 源码目录。

## 许可与致谢

开源部分遵循 [AGPL-3.0](LICENSE)，会员增值模块不包含在公开源码中。感谢 [ignis](https://github.com/Nystik-gh/ignis)、[Node.js](https://github.com/nodejs/node)、[hqzing/ohos-node](https://github.com/hqzing/ohos-node) 及 [HarmonyOS6-WebView-Shell](https://github.com/ZhaYuLiOfficial/HarmonyOS6-WebView-Shell)。

Vitreus 与 Obsidian / Dynalist Inc. 及 ignis 项目无隶属、合作或背书关系。相关名称与商标仅用于描述兼容性。
