# Mate70 Air 微信图片：ArkWeb 缓存根因与 v49 验收状态

2026-10-29 20:25（北京时间）。设备 192.168.0.33:40119，Vitreus com.vitreus.app。

## 已证实

- ArkWeb CDP 对应 Vitreus 自己的页面 http://127.0.0.1:6791/?vault=PARA，标题为“2026-10-29 175116 本周末，一大批明星要来昆山！（内含福利）”。
- 初始直连微信的四张图均解码为 140×140，占位图；不是原图。
- Bridge 通过 new IgnisBridgePlugin 单独创建，没有加入 app.plugins.plugins，故查此列表 false 不能证明 Bridge 未加载。自然启动 console 已见 Plugin loaded、bridge loaded。
- Debugger.getScriptSource(scriptId=8) 实际执行脚本 462046 字符，无 initWechatImages；同一页面新 fetch /shim-loader.js 得 469266 字符，包含 initWechatImages。说明执行代码是旧缓存。
- 旧 HTML 的 shim-loader.js?v=0.8.18-mod.4 URL 在多轮 bundle 更新中不变；静态缓存策略对有 v 的脚本设 public, max-age=31536000, immutable。
- CDP Page.reload(ignoreCache=true) 后，不注入图片逻辑，不修改笔记，真实页面四张图自然改为 blob:http://127.0.0.1:6791/...，naturalWidth×naturalHeight 分别 1080×440、246×174、1080×1439、430×430。证明此前微信代理实现可在 ArkWeb 正常显示。
- 临时隐藏 img clone 仅用于观察 MutationObserver/请求，不是成功验收依据；之后 fresh reload 已清除。

## 实现

- static/cache-headers.js 新增 contentVersionedSrc：部署资源内容 SHA256 加在版本查询串中。
- static/index-html.js 为 shim-loader.js 和 ignis-ui.js 使用内容版本；Obsidian 自身版本策略保留。
- 单次 HTML 缓存意味着每进程首次生成时只读取/哈希一次，不在每请求重复计算。
- NodeTest IGNIS_BUNDLE_VER = v49-0.8.18-mod.4-asset-content-hash。
- 内嵌 ZIP 49 成员，仅替换 server/index.js 后重跑代理补丁；原 shim 内容与 Request body 补丁保留。
- ZIP SHA256 ab1cce216ab7f422b2772ec3576f3d4bc607c93df3352ca018ab9fad5ab102cb；935428 bytes。PC Get-FileHash 与 NAS 一致。

## 检查

- 服务端全量 43 文件 527/527 通过；随后新增 index-html.test.mjs 的源代码/单文件 bundle 两种 __dirname 路径测试 2/2 通过。
- 应用与连接器 259 项：258 通过，1 项初次缺少 VITREUS_IGNIS_SOURCE；设置所需环境后该项单独重跑 1/1 通过。
- patch-ignis-proxy.py --check PASS；patch-ignis-request.py 默认只读检查 ALREADY PATCHED。
- build_app is_clean=true / artifact_source=metadata / sign_status=signed / errors=[]，24.11 秒，2026-10-29 20:24:16。
- HAP：C:\Users\Administrator\DevEcoStudioProjects\Vitreus-harmony\entry\build\default\outputs\default\entry-default-signed.hap。

## 用户最终确认（20:41）

用户明确反馈：“你不是已经覆盖安装了吗，微信图片的问题解决了”。当前已安装诊断包 + fresh reload 后的图片恢复获得用户确认；不再重复安装。微信图片显示故障按真机取证和用户实测闭环。

v49 内容哈希预防改动已完成构建但未安装，随后续版本交付；它的正常升级路径不表述为已真机验证。此前询问安装 v49 时，错误地让人以为当前图片尚未解决，已澄清这两个状态。

## 明确未验 / 后续

- v49 尚未安装：必须等待用户确认覆盖安装，再正常冷启动/刷新验证带哈希 URL 和原图，不能拿 ignoreCache 的诊断成功充当 v49 自然闭环。
- 已安装的是此前含显式 vitreusDebugWeb 参数开关的 v48 诊断包；普通启动开关为 false，当前以 true 启动进行 CDP 取证。
- 尚未声称整篇文章滚动后的全部图片验收，仅当前渲染的四张真实图片。
- 未修改用户笔记，未推送。
- 本报告与新 index-html.test.mjs 尚未跟踪，只能审磁盘实现，无法判断是否属已提交内容。
