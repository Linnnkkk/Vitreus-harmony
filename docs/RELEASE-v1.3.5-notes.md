# Vitreus 1.3.5 — 剪贴板读取与权限按需申请

**Vitreus 1.3.5**（versionCode 1000014）让笔记里的脚本和插件可以读取系统剪贴板，相机/定位/剪贴板权限改为用到时才申请，并修复跨域跳转时认证信息丢失的问题。

| Item | Version |
|---|---|
| HarmonyOS | 6.0.2(22)+ · phone / tablet / 2in1 |
| Embedded server | ignis 0.8.16-mod.5（bundle v27） |
| Obsidian components | 1.12.7 / 1.13.7（均支持） |
| Vitreus | 1.3.5 / versionCode 1000014 |

> Obsidian 组件包由用户自备。Vitreus 不包含、不分发 Obsidian 受版权保护的内容。

## 变更

- **脚本与插件可读取当前设备剪贴板（本地 / 远程模式）** —— `navigator.clipboard.readText()` 此前恒返回空；现由应用申请 `ohos.permission.READ_PASTEBOARD` 后用系统接口读取并交还脚本，仅在脚本主动读取时触发，不后台读取、不上传。首次使用时系统弹出授权框。
- **权限按需申请** —— 不再在启动/进入网页时一次性弹出相机、定位授权；网页请求相机（VIDEO_CAPTURE）、定位或脚本读取剪贴板时才弹出对应系统授权框，已授权的不再重复弹。本地模式页面补上了网页定位请求的处理。
- **修复跨域重定向丢失认证信息** —— 内嵌服务的代理此前在跨域 3xx 跳转时主动丢弃 `Authorization` / `Cookie`，与 Obsidian 原生（Electron `net.request`，`redirect: "follow"`）保留调用方请求头的行为不一致，可能让需要认证的插件请求在服务器跳转后返回 401；现已对齐，每一跳的内网地址校验保留。新增回归测试。
- **鸿蒙电脑端 Copilot 启动兼容** —— 修复 Copilot 4.0.14 的桌面初始化失败。依赖外部 CLI / 子进程的 Agent 功能不在本次验收范围。
- **快捷捕获待办格式** —— 时间移到任务标记之后，生成的条目可被识别为待办。
- **伺服器认证** —— 修复认证 nonce 过期时未标记 stale 的问题；本地认证检查通过，频繁登录反馈仍待实际浏览器验证。
- **内嵌服务** —— ignis 版本串 `0.8.16-mod.5`（bundle v27）。
