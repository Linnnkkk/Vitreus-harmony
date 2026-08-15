cmake_minimum_required(VERSION 3.5.0)
project(vitreus_native)

set(NATIVERENDER_ROOT_PATH ${OHOS_SDK_NATIVE}/sysroot/usr/lib/aarch64-linux-ohos)

# ⚠️ node-headers 的 include 路径绝不能加全局（include_directories）——
# 鸿蒙 native_api.h 内部 #include "js_native_api.h" 会被 -I 解析到 node-headers
# 里 Node 版的同名文件，两套 NAPI 声明打架（17 个 conflicting types 错）。
# 所以只挂在 node_embed.cpp 自己的编译选项里，napi_init.cpp 完全看不到这些路径。
set(NODE_HEADER_FLAGS
    "-I${CMAKE_CURRENT_SOURCE_DIR}/node-headers/node \
     -I${CMAKE_CURRENT_SOURCE_DIR}/node-headers/deps/v8/include \
     -I${CMAKE_CURRENT_SOURCE_DIR}/node-headers/deps/uv/include \
     -std=gnu++20")
set_source_files_properties(node_embed.cpp PROPERTIES COMPILE_FLAGS "${NODE_HEADER_FLAGS}")

# 导入编好的 libnode.so.137（Node.js v24.2.0 OpenHarmony arm64）
# 文件名必须带 .137 后缀 —— .so 内部 SONAME 是 libnode.so.137，改文件名会加载失败
add_library(libnode SHARED IMPORTED)
set_target_properties(libnode PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libnode.so.137)

# 两个编译单元：napi_init 只碰鸿蒙 NAPI，node_embed 只碰 Node 头
add_library(entry SHARED
    napi_init.cpp
    node_embed.cpp)

target_link_libraries(entry PUBLIC libace_napi.z.so libnode)
