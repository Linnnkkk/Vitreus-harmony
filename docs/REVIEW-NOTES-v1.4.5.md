# Vitreus 1.4.5 审核说明

## 新增系统「打开方式」入口

新增了 .md 的系统「打开方式」入口。

- 仅声明 Markdown：`ohos.want.action.viewData`，`scheme: file`，类型为 `general.markdown` 与 `text/markdown`，`linkFeature: FileOpen`。其他文件类型的「打开方式」列表中不会出现 Vitreus。
- 用户在文件管理器里选择 Vitreus 打开 .md 文件后，应用弹出浮层，由用户选择要放入的笔记库（本地库、已配置的 WebDAV 远程库或 ignis 服务器上的库）；确认后才把该文件复制或上传到所选库的根目录，并打开这篇笔记。用户取消则不写入任何内容。
- 同名文件不会被覆盖：内容相同则直接打开已有文件，内容不同则另存为「名称 (2).md」等。
- 没有任何笔记库时只提示先新建笔记库，不做任何写入。
- 不新增任何权限申请；文件内容仅通过系统传入的文件 URI 读取，不上传到 Vitreus 托管服务。
- WebDAV 远程库作为目标需要会员权益，与既有 WebDAV 功能一致；其余目标不受会员限制。
