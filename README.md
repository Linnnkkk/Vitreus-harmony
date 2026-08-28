<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" alt="Vitreus" width="120" />
</p>

<h1 align="center">Vitreus</h1>

<p align="center"><strong>非官方 Obsidian 鸿蒙端兼容工具</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-6.0.2%2822%29-blue?logo=harmonyos" alt="HarmonyOS" />
  <img src="https://img.shields.io/badge/Obsidian-1.12.7-purple?logo=obsidian" alt="Obsidian" />
  <img src="https://img.shields.io/badge/Node.js-v24.2.0-green?logo=nodedotjs" alt="Node.js" />
  <img src="https://img.shields.io/badge/license-AGPL%20v3-orange" alt="License" />
</p>

---

## 目录

- [项目简介](#项目简介)
- [技术架构](#技术架构)
- [功能特性](#功能特性)
- [动效与交互设计](#动效与交互设计)
- [本地模式技术路线](#本地模式技术路线)
- [编译与运行](#编译与运行)
- [项目结构](#项目结构)
- [许可协议](#许可协议)
- [致谢](#致谢)

---

## 项目简介

**Vitreus** 让你在鸿蒙手机、平板、PC 上获得与桌面端一致的 Obsidian 笔记体验，不依赖官方应用。

它并非 Obsidian 官方客户端，而是一个**兼容层与运行环境**：

- **远程模式** —— 直连你自建的 [ignis](https://github.com/Nystik-gh/ignis) 服务器，随时随地访问，数据不经任何第三方
- **本地模式** —— 设备内嵌完整 Node.js v24 运行时，无需服务器、完全离线，飞行模式下照样写笔记

> 🌟 **本项目在鸿蒙应用沙箱内实现了完整 Node.js 运行时支持**——交叉编译官方 Node.js v24.2.0 为 `libnode.so` 并嵌入 app 进程，趟过 seccomp 禁 io_uring、W^X 禁 JIT 等五道沙箱关卡，让任意 Node.js 服务端应用可以直接跑在鸿蒙设备上。据我们所知，这是首个在 HarmonyOS app 沙箱内嵌入完整 Node.js 的公开方案，完整踩坑路线见[本地模式技术路线](#本地模式技术路线)。

> ⚠️ **免责声明**：本应用为独立第三方开源项目，与 Obsidian / Dynalist Inc. 及 ignis 项目无任何隶属、合作或背书关系。"Obsidian" 是 Dynalist Inc. 的商标，此处仅用于描述兼容性。本应用不包含、不分发任何 Obsidian 受版权保护的内容——本地模式所需组件由用户自备导入，类比游戏模拟器的合法先例：模拟器分发运行环境，用户自备游戏 ROM。

---

## 技术架构

```
┌─────────────────────────────────────────────────┐
│                  ArkWeb 浏览器层                  │
│    Obsidian 前端 ←→ ignis shim · Electron API 仿真 │
├─────────────────────────────────────────────────┤
│                ignis server · 双模式复用           │
│  远程：你的 VPS ──────────┐                       │
│  本地：沙箱内 ↓            │                      │
├───────────────────────── ▼ ─────────────────────┤
│              Node.js v24 · libnode.so.137        │
│               --jitless · 单进程嵌入               │
├─────────────────────────────────────────────────┤
│            C++ 嵌入层 · node_embed.cpp            │
│   环境变量注入 · 单次防重入 · exit 兜底 · 双编译单元  │
├─────────────────────────────────────────────────┤
│              ArkTS 壳层 · 页面与交互               │
│   双模式路由 · 悬浮球 · 权限收口 · 导入向导 · 看门狗   │
├─────────────────────────────────────────────────┤
│               HarmonyOS App 沙箱                  │
│      seccomp 禁 io_uring · W^X 禁 JIT 页面        │
└─────────────────────────────────────────────────┘
```

**分层说明：**

- **ArkWeb 层** —— Obsidian 前端跑在系统 WebView 里；ignis 的 shim 把 Electron API 仿真为浏览器与 HTTP 调用，Obsidian 无感运行
- **ignis server** —— express + ws + chokidar，纯 JS 无 native addon；远程模式跑在你的服务器，本地模式跑在沙箱，业务代码同一份
- **Node.js 运行时** —— libnode.so.137 交叉编译自官方源码，`--jitless` 规避沙箱 W^X 限制
- **C++ 嵌入层** —— 注入 VAULT_ROOT / PORT 等环境变量后启动 Node；与鸿蒙 NAPI 的头文件冲突靠双编译单元隔离
- **ArkTS 壳层** —— 页面路由、交互与系统集成
- **HarmonyOS 沙箱** —— 最底层的两道硬约束，也是本项目要趟过的核心关卡，见下文

**数据流：**

```
远程模式  ArkWeb ──HTTPS──▶ 你的 ignis 服务器 ──▶ vault
本地模式  ArkWeb ──127.0.0.1:6791──▶ 沙箱内 ignis ──▶ 沙箱 vault
```

---

## 功能特性

**双模式架构**

- **本地模式** —— 设备内嵌完整 Node.js v24 运行时，无需服务器、完全离线，飞行模式下照样写笔记
- **远程模式** —— 直连你自建的 ignis 服务器，随时随地访问，数据不经任何第三方

**开箱即用**

- **库直接用** —— 现有 Obsidian 库原封不动打开即用，零迁移零转换，插件与主题随库走

**隐私与开放**

- **数据自主** —— 笔记始终在你的设备或你的服务器上，本应用不收集任何数据
- **完全开源** —— AGPL v3，无广告、无内购、无遥测
- **多端适配** —— phone / tablet / 2in1 同一体验，窗口自适应

---

## 动效与交互设计

动效不是装饰，是这个产品的语气。全部动效遵循同一套原则：**有出处（致敬经典或源自品牌几何）、不抢戏、可感知但不拖沓**。

**开场 · 开屏光路**

- 按 logo 生成脚本（三棱镜光路图）的原始几何 1:1 复现：一束光沿光轴射入棱镜，折射面闪光后散射出六色光谱扇，同时 logo 由 55% 亮度充能至全亮
- 全程约 1.7s（色散先以六段光谱展开，再收敛为与静态 logo 同款色板后无缝归位），页面分发在动画内完成，启动零延迟

**页面 · 四页四款经典背景**

| 页面 | 背景 | 出处 |
|:--|:--|:--|
| 模式选择 | 多重正弦波带 | PPSSPP XMB 开机波浪（Background.cpp 移植） |
| 登录 | 粒子网络（plexus） | 经典科技感粒联网 |
| 授权页 | 呼吸星野 + 流星 | 星空夜幕 |
| 本地运行 | 符号雨 | Matrix 数字雨（15fps 跳格更地道） |

- 全部 Canvas 逐帧绘制，页面隐藏自动停表省电（pushUrl 后父页不销毁，靠 onPageHide 联动停绘）

**导航 · 方向感转场**

- 真栈导航（pushUrl 入栈 / back 出栈）：前进新页从右滑入，返回下层从左回位——空间记忆与实际栈结构一致
- 入页 200ms / 出页 160ms，利落不拖沓；同级换页（网页互切）不带转场，避免栈感错乱

**微交互**

- 涟漪跟手（从触点位置扩散）、卡片按压 springMotion 弹性
- 触觉三档：轻点 12ms / 选中 24ms / 成功双脉冲（导入完成时刻）
- 导入成功：Canvas 描边式生长对勾（先短边后长边）→ 1.2s 后才弹重启确认，让成功先被看见
- 打字机只用于副标题与动态状态（16-22ms/字），标题与正文永不用——有明确的组件使用规则注释

---

## 本地模式技术路线

把 Node.js 跑进鸿蒙沙箱是本项目最硬核的部分——**全网没有现成方案**，以下是完整路线：

### 1. 交叉编译 libnode.so

基于 [nodejs/node PR #58350](https://github.com/nodejs/node/pull/58350) 官方 OpenHarmony 支持，OHOS SDK + LLVM-19 交叉编译 Node.js v24.2.0，`configure --shared` 产出 `libnode.so.137`，146MB，含 V8 全量符号 6.6 万个。

### 2. 五道沙箱关卡

| # | 关卡 | 现象 | 解法 |
|---|------|------|------|
| 1 | **SONAME** | 模块加载失败变空 stub | 文件名必须精确 `libnode.so.137`，SONAME 带 ABI 版本号 |
| 2 | **seccomp 拦 io_uring** | `SIGSYS syscall 425` 崩在 `uv_loop_init` | libuv 源码补丁：`uv__use_io_uring()` 加 `__OHOS__` 短路，需重编 libuv |
| 3 | **W^X 禁 JIT** | `V8_Fatal` 崩在 `SetPermissions` | 启动参数 `--jitless`，纯 Ignition 解释器，无需可执行内存 |
| 4 | **Inspector 初始化崩** | `InitializeInspector` 内部 assert | `CreateEnvironment` 传 `kNoFlags`，不带 `kOwnsInspector` |
| 5 | **JS 异常拉崩宿主** | 未捕获异常触发 `exit()` 拉死整个 app | `SetProcessExitHandler` 改写为记日志 + `uv_stop` |

### 3. 嵌入式调用要点

- `LoadEnvironment` 第二参数是 **JS 源码字符串**而非文件路径，传路径会报 `Invalid regular expression flags`
- `InitializeNodeWithArgs` 全进程只能调一次，重复调用 abort，需防重入
- 鸿蒙 NAPI 与 Node 头文件的 `napi_*` 声明冲突 → 拆两个编译单元，且 node-headers 的 include 路径绝不能加全局
- v8 头要求 C++20

### 4. ignis server 集成

ignis server 打成**单 bundle** 部署进 app：

```
打包   esbuild --bundle → 3.3MB，node_modules 全内联，对比 318MB 直搬缩小 100 倍
部署   ignis-server.zip 进 rawfile → 首启解压到沙箱 filesDir/ignis/
运行   C++ 嵌入层注入环境变量后启动，监听 127.0.0.1:6791
访问   ArkWeb 连接，Obsidian 界面完整可用
```

**Obsidian 前端资源由用户自备**：支持 `obsidian.asar` 与 `obsidian.asar.gz` 两种官方发布格式，app 内直接导入，内嵌 Node 自动解包——含 unpacked 目录处理，无需电脑端工具。

> 兼容性：与官方 Docker 一致，Obsidian 组件当前 pin 在 1.12.7；1.13+ 的 Settings 重构尚未适配，跟进中。

**内嵌 ignis 版本对照 / Embedded ignis version map**（issue 分诊用 / for triage）：

| Vitreus 版本 | 内嵌 ignis（bundle） |
|:---|:---|
| 1.0.0（AppGallery） | 0.8.10（bundle v16） |

> App 内 shim 会将 ignis 版本串注入 `window.__ignis`，Obsidian 界面控制台可直接查看；此后每个 Vitreus release 的说明都会标注对应 ignis 版本。

**代价说明**：`--jitless` 下 JS 执行约为 JIT 版 30-50%，IO 密集场景无感；libuv 补丁导致文件 IO 走线程池而非 io_uring，功能无损。

---

## 编译与运行

1. 安装 [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio/)，HarmonyOS 6.0.2 / API 22
2. 打开本项目目录，等待依赖同步
3. 在 `build-profile.json5` 中配置你自己的签名材料，本仓库不含任何签名证书
4. 本地模式需要 `libnode.so.137`，146MB 超出 git 容量限制，从 [Releases](../../releases) 下载后放到 `entry/libs/arm64-v8a/`
5. Build → Run

---

## 项目结构

```
entry/src/main/
├── cpp/
│   ├── napi_init.cpp      # 鸿蒙 NAPI 桥，只碰鸿蒙头文件
│   ├── node_embed.cpp     # Node 嵌入，只碰 Node 头文件
│   ├── node-headers/      # Node v24.2.0 官方头文件
│   └── CMakeLists.txt     # 双编译单元隔离 + 头文件路径控制
├── ets/
│   ├── pages/
│   │   ├── Splash.ets     # 启动分发，记住上次模式
│   │   ├── ModeSelect.ets # 远程 / 本地双入口
│   │   ├── Login.ets      # 远程模式服务器地址
│   │   ├── AuthPage.ets   # Basic Auth 凭证
│   │   ├── Index.ets      # 远程模式主页，ArkWeb + 悬浮球 + 看门狗
│   │   ├── NodeTest.ets   # 本地模式部署与导入向导
│   │   ├── LocalWeb.ets   # 本地模式主页，连 127.0.0.1:6791
│   │   └── About.ets      # 关于、协议、免责、反馈
│   ├── components/BackButton.ets
│   └── common/AppPermissions.ets   # 权限申请统一收口
└── resources/rawfile/
    ├── ignis-server.zip   # ignis server bundle，首启解压
    └── node-runtime/test-server.js # 自检脚本
```

---

## 许可协议

[AGPL-3.0](LICENSE)

本应用内嵌 [ignis](https://github.com/Nystik-gh/ignis) 并基于其构建，故整体以 AGPL v3 开源。

---

## 致谢

- [ignis](https://github.com/Nystik-gh/ignis) — self-hosted Obsidian 环境，本项目内嵌其 server
- [ZhaoYuLiOfficial/HarmonyOS6-WebView-Shell](https://github.com/ZhaYuLiOfficial/HarmonyOS6-WebView-Shell) — WebView 套壳起点，本项目由其改造而来
- [nodejs/node](https://github.com/nodejs/node) — Node.js，PR #58350 OpenHarmony 支持
- [hqzing/ohos-node](https://github.com/hqzing/ohos-node) — 交叉编译工具链参考

---

<p align="center">
  <sub>Vitreus 是一个社区项目，与 Obsidian 官方无关。</sub>
</p>
