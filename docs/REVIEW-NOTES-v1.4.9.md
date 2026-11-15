# Vitreus 1.4.9 审核说明

版本：1.4.9（versionCode 1000028），发布提交 `1504e98`，tag `v1.4.9`。内嵌 ignis 0.9.0-mod.4（包版本 v79）。

## 官方 QQ 群

- 「关于」页客服区新增「官方 QQ 群：301503607（点击复制）」，会员页客服区同步增加一行。
- 只复制群号到剪贴板，不跳转、不调用第三方 SDK；群号常量为 `common/OpenLink.ets` 的 `QQ_GROUP`。

## AI 连接

- 「一键复制给 AI Agent」指引重写为 6 个编号步骤：检查环境 → 安装连接器（先征求用户同意）→ 注册 MCP → 配对 → 验证 → 编辑规则，照顾理解能力较弱、没有上下文的模型。
- 配对流程改为：用户把手机生成的配对信息发给 AI，AI 写入临时文件后执行 `vitreus-ai pair --file`，完成后删除临时文件。配对信息一次性、约 2 分钟过期。应用内手动教程、README、连接器 README 的说明已统一。
- 成功判定同时兼容 npm 已发布的 1.3.9-beta.1（输出 `Paired with …` / `connected`）与仓库源码（`Paired successfully` / `authenticated`）。
- 「允许 AI 编辑」与「撤销全部设备」两个确认弹窗改为全屏居中容器，修复显示在左上角的问题（页面根 Stack 为 TopStart，子组件 `.align()` 只影响自身内容）。

## WebDAV 冲突文件夹修复

- 修复 WebDAV 远程库可能反复生成冲突文件夹的问题（内嵌包 v77，提交 `42c4d6d`）。

## Omni Viewer 插件兼容

- ignis 新增按插件生效的兼容模式（`packages/shim/src/plugin-compat.js`）：读取 `.obsidian/plugins/omni-viewer/main.js` 时在内存中包装代码，使该插件看到的 `Platform.isMobileApp = true`、`isDesktopApp = false`，从而走它自带的纯浏览器移动端实现。磁盘文件不修改，Obsidian 本体与其他插件不受影响。
- 原因：该插件桌面端实现依赖 ffmpeg、LibreOffice、7z 与 Node 二进制接口；在 ignis 上实测压缩包报 `readUInt16LE is not a function`（Buffer 垫片缺方法）。
- 实测（本地 Obsidian 1.13.7 + v79 内嵌包 + Chromium）：插件加载无报错，CSV、JSON、YAML、ZIP、DOCX 均正常显示；用户鸿蒙 PC 真机验证通过。
- 取舍：移动端实现不含 parquet、PSD、HDF5、MAT、Shapefile 及部分汽车行业格式（共 17 种视图）。
- 已知风险：若用户用同步插件同步 `.obsidian/plugins` 目录，可能把包装后的 `main.js` 同步到电脑端，电脑上的该插件也会走移动端实现，直到插件更新覆盖。

## 权限与隐私

- 未新增系统权限；未引入统计、崩溃收集、广告或推送 SDK。

## 构建与验证

- 应用测试 385 项通过；ignis Vitest 1413 项通过（bridge 下 2 个 node:test 格式文件在 vitest 下一直报错，与本版无关）。
- 内嵌 `ignis-server.zip` 59 个条目；v79 与 v77 相比仅 `shim-loader.js`、`build-info.json` 变化，代理补丁后的 `index.js` 逐字节一致；继续剔除上游 discord/kofi/githubsponsors 图标。
- 群晖 NAS 自动生成的 `@eaDir` 会导致资源打包失败，已加入 `.gitignore`、`.stignore` 和 Mac 构建同步的排除列表。
