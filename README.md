# Vitreus 🪟

> **A HarmonyOS client for accessing your self-hosted Obsidian environment.**
> 一款**非官方的** Obsidian 鸿蒙端兼容工具——帮助鸿蒙设备用户（手机/平板/PC）在**不依赖官方应用**的情况下，访问和管理本地或远程的 Obsidian 环境（通过 [ignis](https://github.com/Nystik-gh/ignis)）。

Vitreus 并非 Obsidian 官方客户端，而是一个**兼容层 / 运行环境**：它让你在鸿蒙手机 / 平板 / 2in1 设备上获得与桌面端一致的 Obsidian 笔记体验。两种使用方式——**远程模式**直连你自建的 ignis 服务器；**本地模式**在本机内嵌 Node.js 运行时完全离线使用（所需的 Obsidian 核心组件 .asar 由用户自行获取导入，本应用不分发任何受版权保护的内容）。

---

> ⚠️ **免责声明 / Disclaimer**
>
> 本应用为**独立第三方开源项目**，与 Obsidian / Dynalist Inc. 及 ignis 项目**无任何隶属、合作或背书关系**。
>
> "Obsidian" 是 Dynalist Inc. 的商标，"ignis" 为其各自所有者的项目名，此处仅用于描述兼容性，不主张任何商标权利。用户需自行承担使用第三方组件（.asar / ignis 服务）的风险。
>
> Vitreus is an independent third-party open-source tool. It is NOT affiliated with, endorsed by, or sponsored by Obsidian / Dynalist Inc. or the ignis project. All product names and trademarks are property of their respective owners, used here for compatibility description only. Users assume all risks arising from the use of third-party components.

---

## ✨ 功能 Features

- **远程模式（VPS）**：填写你自己的 ignis 服务器地址 + Basic Auth 凭证，连接远程服务
- **本地模式**：设备内嵌完整 Node.js v24 运行时（libnode.so），无需服务器，完全离线（Obsidian 组件用户自备导入）
- **HTTP Basic Auth**：自动处理 nginx 等反向代理的 Basic Auth 认证，401 自动跳回重输
- **密码保险箱**：集成系统 AutoFill，凭证保存更安全（密码不落盘）
- **沉浸式状态栏**：全屏沉浸体验，状态栏透明适配
- **智能左滑返回**：识别弹窗 / 命令面板 / 菜单，模拟 Esc 关闭；主页双击退出
- **定位权限**：支持笔记模板（如 Templater 天气脚本）通过浏览器 Geolocation 获取设备位置
- **暗黑模式适配**
- **多设备**：phone / tablet / 2in1

## 🧪 本地模式：把 Node.js 跑进鸿蒙沙箱（技术路线）

这是本项目最硬核的部分：**在 HarmonyOS app 沙箱内嵌入完整 Node.js 运行时**。全网没有现成方案，以下是我们趟出来的完整路线（Issue/PR 欢迎交流）：

### 1. 交叉编译 libnode.so（Node.js v24.2.0 → OpenHarmony arm64）

基于 [nodejs/node PR #58350](https://github.com/nodejs/node/pull/58350)（官方 OpenHarmony 支持，2025-05 merged）+ OHOS SDK/LLVM-19 交叉编译，`configure --shared` 直接产出 `libnode.so.137`（146MB，含 V8 全量符号 6.6 万个）。

### 2. 五道沙箱关卡（每道都有解法）

| # | 关卡 | 现象 | 解法 |
|---|------|------|------|
| 1 | **SONAME** | 模块加载失败变空 stub | 文件名必须精确 `libnode.so.137`（SONAME 带 ABI 版本号）|
| 2 | **seccomp 拦 io_uring** | `SIGSYS syscall 425` 崩在 `uv_loop_init` | libuv 源码补丁：`uv__use_io_uring()` 加 `__OHOS__` 短路（Android 同款先例），**需重编 libuv** |
| 3 | **W^X 禁 JIT** | `V8_Fatal` 崩在 `SetPermissions`（mprotect RWX 被拒）| 启动参数 `--jitless`（纯 Ignition 解释器，无需可执行内存）|
| 4 | **Inspector 初始化崩** | `InitializeInspector` 内部 assert | `CreateEnvironment` 传 `kNoFlags`（不带 `kOwnsInspector`）|
| 5 | **JS 异常拉崩宿主** | 未捕获异常 → `exit()` → 整个 app 死 | `SetProcessExitHandler` 改写为记日志 + `uv_stop` |

### 3. 嵌入式调用要点（node.h API 的坑）

- `LoadEnvironment(env, ...)` 第二参数是 **JS 源码字符串**，不是文件路径（传路径会报 `Invalid regular expression flags`）
- `InitializeNodeWithArgs` 全进程只能调一次（重复调用 abort，需防重入）
- 鸿蒙 NAPI 与 Node 头文件的 `napi_*` 声明冲突 → **拆两个编译单元**（桥文件 vs 嵌入文件），且 node-headers 的 include 路径绝不能加全局
- v8 头要求 C++20

### 4. 验证结果

```
[js] === Node 进程已启动 ===
[js] node v24.2.0 | arm64 | openharmony
[js] require http OK
[js] http server 已监听 127.0.0.1:6790
```

Node.js 在鸿蒙手机上完整可用：fs 读写、模块加载、http server 全部正常（自检脚本监听 6790，实际运行 6791）。本地模式完整形态已落地：打包 ignis server → Node 跑 localhost → ArkWeb 连接 → Obsidian 界面完整可用。

> 代价说明：`--jitless` 下 JS 执行约为 JIT 版 30-50%（IO 密集场景无感）。libuv 补丁导致文件 IO 走线程池而非 io_uring（功能无损）。

### 5. ignis server 集成（本地模式完整形态）

ignis server（express + ws + chokidar，纯 JS 无 native addon）被打成**单 bundle** 部署进 app：

```
打包：esbuild --bundle → 3.3MB 目录（node_modules 全内联，对比 318MB 直搬缩小 100 倍）
部署：ignis-server.zip (745KB) 进 rawfile → 首启解压到沙箱 filesDir/ignis/
运行：C++ 嵌入层设 VAULT_ROOT/DATA_ROOT/PORT/OBSIDIAN_ASSETS_PATH 环境变量后启动
访问：ArkWeb 连 http://127.0.0.1:6791
```

**Obsidian 前端资源（用户自备，法律合规设计）**：ignis 需要 Obsidian 的前端资源，出于版权考虑 app 不分发。用户从自己的渠道获取 `obsidian.asar` / `obsidian.asar.gz`（官方 releases 的自备格式），在 app 内直接导入——server 启动时由内嵌 Node 自动解包（含 unpacked 目录处理），无需电脑端工具。`scripts/pack-obsidian-assets.py` 为早期的电脑端打包脚本，保留作参考。类比游戏模拟器的合法先例：**模拟器分发运行环境，用户自备游戏 ROM**。

> 兼容性提示：与官方 Docker 一致，Obsidian 组件当前 pin 在 1.12.7（1.13+ 的 Settings 重构尚未适配，跟进中）。

## 📱 截图 Screenshots

（待补充 / TODO）

## 🔧 编译 Build

1. 安装 [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio/)（HarmonyOS 6.0.2 / API 22）
2. 打开本项目目录，等待依赖同步
3. 在 `build-profile.json5` 中配置**你自己的签名材料**（本仓库不含任何签名证书）
4. **本地模式需要 libnode.so.137**（146MB，超出 git 容量限制）：从 [Releases](../../releases) 下载，放到 `entry/libs/arm64-v8a/`
5. Build → Run

## 📂 项目结构 Structure

```
entry/src/main/
├── cpp/
│   ├── napi_init.cpp      # 鸿蒙 NAPI 桥（只碰鸿蒙头文件）
│   ├── node_embed.cpp     # Node 嵌入（只碰 Node 头文件，--jitless）
│   ├── node-headers/      # Node v24.2.0 官方头文件
│   └── CMakeLists.txt     # 双编译单元隔离 + 头文件路径控制
├── ets/pages/
│   ├── Splash.ets         # 启动分发（记住上次模式）
│   ├── ModeSelect.ets     # 远程 / 本地 双入口
│   ├── Login.ets          # 远程模式：服务器地址
│   ├── AuthPage.ets       # Basic Auth 凭证
│   ├── Index.ets          # 远程模式主页面（ArkWeb + 悬浮球 + 看门狗）
│   ├── NodeTest.ets       # 本地模式（部署/导入向导 + 诊断日志）
│   ├── LocalWeb.ets       # 本地模式主页面（ArkWeb，连 127.0.0.1:6791）
│   └── About.ets          # 关于（协议/免责/反馈入口）
├── components/BackButton.ets
├── common/AppPermissions.ets  # 权限申请统一收口
└── resources/rawfile/
    ├── ignis-server.zip   # ignis server bundle（首启解压）
    └── node-runtime/test-server.js  # 自检脚本
```

## 📄 许可 License

[AGPL-3.0](LICENSE)

本应用内嵌 [ignis](https://github.com/Nystik-gh/ignis)（AGPL v3）并基于其构建，故整体以 **AGPL v3** 开源。

## 🙏 致谢 Credits

- [ignis](https://github.com/Nystik-gh/ignis) — self-hosted Obsidian 环境
- [nodejs/node](https://github.com/nodejs/node) — Node.js（PR #58350 OpenHarmony 支持）
- [hqzing/ohos-node](https://github.com/hqzing/ohos-node) — 交叉编译工具链参考
