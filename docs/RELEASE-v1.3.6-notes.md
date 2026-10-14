# Vitreus 1.3.6 — 支持 Obsidian 1.14.4，网页登录更顺手

**Vitreus 1.3.6**（versionCode 1000015）跟进官方 ignis 0.8.17，支持 Obsidian 1.14.4；插件打开的网页改为底部半屏窗口，并支持 `obsidian://` 登录回调。

| Item | Version |
|---|---|
| HarmonyOS | 6.0.2(22)+ · phone / tablet / 2in1 |
| Embedded server | ignis 0.8.17-mod（bundle v29） |
| Obsidian components | 1.14.4（已验证）；1.12.7 / 1.13.7 沿用原有兼容层，未在 0.8.17 上逐版复测 |
| Vitreus | 1.3.6 / versionCode 1000015 |

> Obsidian 组件包由用户自备。Vitreus 不包含、不分发 Obsidian 受版权保护的内容。

## 变更

- **跟进官方 ignis 0.8.17（Obsidian 1.14.4）** —— 合并上游 v0.8.17：Obsidian 固定到 1.14.4；手机端底部导航不再被截断、编辑器工具栏保持在键盘上方、长按文字显示浏览器复制粘贴菜单；新增 `fs/promises` 垫片（与此前为 Copilot 补的 `async_hooks` 并存）。上游设置页新增的 Docs / Discord / Ko-fi / Sponsors 链接在 Vitreus 中不展示。1.14.4 导入已真机验证。
- **网页弹窗改为底部半屏窗口** —— 插件通过 `window.open` / `shell.openExternal` 打开网页时，不再整屏覆盖 Obsidian：从下方滑入（约 340ms），高度为界面的 90%，右上角 ✕、下拉标题栏、返回键均可关闭；遮罩不响应点击，避免登录中途误触丢进度。本地与远程模式一致。弹窗在场时返回键不再误触发主页面的退出流程。已真机验证。
- **`obsidian://` 重定向回调** —— 弹窗内页面或主页面跳转到 `obsidian://<action>?…`，或插件 `window.open("obsidian://…")` 时，按 Obsidian 内部规则解析后调用 `window.OBS_ACT` 投递（1.12.7 / 1.13.7 / 1.14.4 的 app.js 均核对该入口），并自动收起弹窗。已真机验证。不覆盖以 `http://localhost:端口` 作回调地址的插件（需壳内监听，后续单独评估）。
- **修复伺服器浏览器端频繁弹登录框** —— Digest 认证中，过期 nonce 被首个并发请求清除后，其余在途请求会收到“非 stale”的挑战，Chrome / Edge 因此当作密码被拒而弹框；现对未知 / 过期 nonce 一律返回 `stale=true`，浏览器静默重试。新增回归测试（旧代码下失败，新代码通过）。实际浏览器长时间使用的效果仍待反馈。
- **同步类插件访问内网地址** —— 内嵌服务的 SSRF 防护此前拦截全部私有地址（如 Fast Note Sync 连 `192.168.x.x` / Tailscale `100.64.x.x` 报 “Ignis blocked a connection … (private address)”）。服务运行在用户自己的设备上，Vitreus 构建现默认放行 `10/8`、`172.16/12`、`192.168/16`、`100.64/10`，仍拦截回环与 `169.254`（云元数据）；每一跳重定向仍做校验。
- **内嵌服务** —— ignis 版本串 `0.8.17-mod`（bundle v29）。
