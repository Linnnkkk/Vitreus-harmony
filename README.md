# Vitreus 🪟

> **A HarmonyOS client for accessing your self-hosted Obsidian environment.**
> 一款鸿蒙应用，用于访问你**自己部署的** Obsidian 运行环境（通过 [ignis](https://github.com/Nystik-gh/ignis)）。

Vitreus 让你在鸿蒙手机 / 平板 / 2in1 设备上，连接你自己搭建的 ignis 服务，从而在移动端使用 Obsidian 管理笔记。

---

> ⚠️ **免责声明 / Disclaimer**
>
> Vitreus 是**第三方独立工具**，**非官方 Obsidian 产品**，与 Obsidian / Dynalist Inc. 及 ignis 项目**无任何隶属、合作或背书关系**。
>
> "Obsidian" 是 Dynalist Inc. 的商标，"ignis" 为其各自所有者的项目名。本项目仅在描述兼容性时使用这些名称，不主张任何商标权利。
>
> Vitreus is an independent third-party tool. It is NOT affiliated with, endorsed by, or sponsored by Obsidian / Dynalist Inc. or the ignis project. All product names and trademarks are property of their respective owners, used here for compatibility description only.

---

## ✨ 功能 Features

- **VPS 模式**：填写你自己的 ignis 服务器地址 + Basic Auth 凭证，连接远程服务
- **模式选择**：首次启动选择 VPS / 本地（本地模式开发中）
- **HTTP Basic Auth**：自动处理 nginx 等反向代理的 Basic Auth 认证，401 自动跳回重输
- **密码保险箱**：集成系统 AutoFill，凭证保存更安全
- **沉浸式状态栏**：全屏沉浸体验，状态栏透明适配
- **智能左滑返回**：识别弹窗 / 命令面板 / 菜单，模拟 Esc 关闭；主页双击退出
- **定位权限**：支持笔记模板（如 Templater 天气脚本）通过浏览器 Geolocation 获取设备位置
- **暗黑模式适配**
- **多设备**：phone / tablet / 2in1

## 📱 截图 Screenshots

（待补充 / TODO）

## 🔧 编译 Build

1. 安装 [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio/)（HarmonyOS 6.0.2 / API 22）
2. 打开本项目目录，等待依赖同步
3. 在 `build-profile.json5` 中配置**你自己的签名材料**（本仓库不含任何签名证书）
4. 连接鸿蒙设备或模拟器，编译运行

## 🚀 使用 Usage（VPS 模式）

1. 自行部署 [ignis](https://github.com/Nystik-gh/ignis) 服务（Docker），建议配置反向代理 + Basic Auth
2. 打开 Vitreus → 选择「连接远程服务器」
3. 填写你的 ignis 服务器地址（如 `https://your.server.com:6080/`）+ 账号 + 密码
4. 连接成功，开始使用

## 🛠️ 技术栈 Tech Stack

- **HarmonyOS 6.0.2**（API 22）
- **ArkTS** + **ArkUI** 声明式 UI
- **ArkWeb** WebView 组件

## 📦 项目结构 Structure

```
entry/src/main/ets/pages/
├── Splash.ets        # 启动页（2s → 模式选择）
├── ModeSelect.ets    # 模式选择（VPS / 本地）
├── Login.ets         # 服务器地址 + Basic Auth 登录
└── Index.ets         # WebView 主页（认证 / 左滑返回 / 定位）
```

## 🧩 本地模式（规划中）

本地模式目标：在设备本机运行 ignis 服务，由用户**自备** Obsidian 程序文件加载。该模式仍在技术攻关中。

> 本应用不包含、不分发、不自动下载 Obsidian 或 ignis 的任何程序文件。用户需自行合法获取并部署相关软件。

## 🙏 致谢 Acknowledgements

- [HarmonyOS6-WebView-Shell](https://github.com/ZhaoYuLiOfficial/HarmonyOS6-WebView-Shell) — 上游 WebView 壳项目（MIT）
- [ignis](https://github.com/Nystik-gh/ignis) — Self-hosted Obsidian Web Access（AGPL-3.0）
- [Obsidian](https://obsidian.md) — A knowledge base that works on local Markdown files

## 📄 许可证 License

[MIT](LICENSE)

本项目代码基于 MIT 协议开源。本项目**不包含、不分发** Obsidian 或 ignis 的任何专有代码。
