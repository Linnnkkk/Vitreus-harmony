// x86_64 模拟器 UI 验证桩：libnode 无 x86_64 版本，Node 启动空转。
// 真机（arm64-v8a）走 node_embed.cpp 真实现，CMake 按 OHOS_ARCH 分流。
#include <string>

void vitreusNodeMain(const char *script, const char *statusPath, const char *vaultOverride) {
    (void)script;
    (void)statusPath;
    (void)vaultOverride;
    // 空实现：模拟器变体仅验证 UI 流转，不启动 Node
}
