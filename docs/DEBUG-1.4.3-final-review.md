# Vitreus 1.4.3 最后一轮代码 Debug

日期：2026-10-29 21:07 北京时间。范围：应用及 ignis 当前工作树与嵌入服务 ZIP。非全仓无缺陷证明。未安装、未操作用户笔记、未推送。

## 结论

两路独立只读审查，Lead 按实际源码复核与最小复现后修复三项确定缺陷，并收紧跨文档请求顺序、移除临时调试启动入口。自动测试与干净构建通过；最终 v50 是 debug 签名检查包，未进行真机自然启动验收，不是商店发布构建。

## 范围与跟踪状态

- 应用基线 status：13 tracked 修改及5 untracked；服务基线13 tracked修改及7 untracked。EntryAbility 临时诊断两行本轮移除，恢复原实现。
- ServiceVaultApi.ets、ServiceVaultPicker.ets、service-vault-picker.test.cjs、webclip-images.test.cjs、服务 service-vaults.js、ai-lan/remote-vault.js、bridge/wechat-images.js 及其测试未被索引跟踪，只能审磁盘实现，无法据此断定是否本轮新增或已经提交。
- 应用 app.json5：versionName 1.4.3 / versionCode 1000022；NodeTest 部署戳 v50-0.8.18-mod.4-final-debug。

## 确定缺陷与修复

1. WebClip 链接包裹的微信图被当成链接文字。微信图片已转 E006/E007 占位符，链接处理只排除 ![ 与 <img，导致输出 [<img ... />](link)后文，吞掉图片后的换行。新增识别保护占位符，保留独立图片；新增 a>img 后跟段落回归通过。HTML 图片外链与普通图片原有策略一致：保留图片、去掉外链包装。
2. AI WebDAV 已写入后，缓存刷新 await 期间卸载/撤权/会话失效丢 committed 标记。先新增五场景测试（卸载、替换backend、撤权、退出会话、变只读），原代码5/5失败、其余41通过。扩大 committed catch 至全部写后处理；五场景全部通过，仍保留原权限错误，不隐藏撤权。
3. 真实 WebDAV timeout 错误无 code，只有 name=WebdavError/status=0，原远程AI映射仅按 code 导致 INTERNAL/500。增加该明确错误形状映射至 UNAVAILABLE，使用实际 WebdavError 类测试通过。未更改所有 WebDAV 路由的公共错误策略。

## 收紧项

- LocalWeb 跨文档 stop 清 pending 但不取消HTTP，可能允许新POST与旧POST并发，旧请求迟到覆盖新ACK。本轮保留跨epoch在途锁，用promise身份释放；下一tick在旧请求结束后上报新库。内存真实方法测试确认 pending共享、旧回执不ACK、新库最终上报，21项默认库测试通过。实际设备请求乱序未测。网络超时后服务端延迟提交仍不由客户端锁完全保证，不能宣称分布式顺序已绝对解决。
- EntryAbility 临时 Want 参数启用 ArkWeb debugging 的两行移除；不再保留可由导出Ability接收的诊断开关。

## 验证

- 应用+连接器 tools/*.test.cjs 与 tools/ai-connector/test/*.test.js：262/262，通过；显式 VITREUS_IGNIS_SOURCE 和 NODE_PATH。
- 服务端44文件：534/534，通过（committed修复后、timeout补丁前）；timeout补丁后受影响 remote-vault + ai-lan/index 两文件63/63通过。没有把两轮相加成“最终597项”。
- Node图片生命周期11/11，WebClip8/8，共19/19；此前把node:test混入Vitest产生No test suite found，已改用正确运行器，不是业务失败。
- 最终ZIP更新后嵌入服务协议/Request/Proxy39/39通过。
- 两仓 git diff --check通过；Request补丁 ALREADY PATCHED，代理重定向补丁 --check PASS。
- 内容哈希源码与内嵌bundle路径分别验证正确。磁盘与ZIP shim只有两处注释差异，不能用它们不同的SHA推断功能不一致。
- PC与NAS的 WebClip、LocalWeb、NodeTest、EntryAbility源文件SHA256一致；最终ZIP更新后PC哈希再次确认。
- build_app：is_clean=true、artifact_source=metadata、sign_status=signed、errors=[]，24.54秒，21:04:50完成，build_mode=debug。
- HAP回传本地解包：module.json app.debug=true/buildMode=debug、versionName=1.4.3/versionCode=1000022；resources/rawfile/ignis-server.zip SHA256与磁盘完全一致。
- ZIP SHA256：07163306ec93639c7cedb9771bc3544106f4df616ecb6d682d3c411b66782e8a。
- HAP SHA256：c64de513ced241f5492774147eafba4b7785f2cb67099edd24047e0a749a4913。
- PC产物：C:\Users\Administrator\DevEcoStudioProjects\Vitreus-harmony\entry\build\default\outputs\default\entry-default-signed.hap。

## 未验与保留风险

- 最终v50未安装；微信原图恢复已有此前CDP真实笔记尺寸与用户确认，不能替代v50自然升级、剪藏排版、默认库和真实WebDAV AI读写的真机验收。
- 最新剪藏排版仅新剪藏生效；未修改已有笔记。
- wechat-images每图12MiB校验在完整代理响应+base64解码之后，代理总上限50MiB；不能声称12MiB为峰值内存上限。
- 图片请求无专属超时/取消，四个长期挂起响应可能占满队列；本轮未以真实CDN故障复现，列为可疑，不夸大为确定内存泄漏。
- 网络失败/超时不能证明远端PUT未提交；committed只标记收到成功响应的已确认写入。
- 后续状态更新（2026-10-29 21:59）：用户已确认1.4.3最终文案，UpdateNotice标题、已读标记与内容均已更新。随后干净构建通过：metadata/signed/errors=[]，24.43秒，仍为debug检查包且未安装；上文21:04包哈希仅对应当时的审查包，不代表文案更新后的新包。
- 上架还需正式 release 构建/发布签名及最终包真机冒烟，不把本次debug HAP称为上架包。
