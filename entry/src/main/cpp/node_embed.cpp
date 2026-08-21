// Node 嵌入实现 —— 只 include Node 头（node.h 会拉进 Node 版 NAPI 声明），
// 绝不 include 鸿蒙 native_api.h（两者都声明 napi_* 会签名冲突，所以拆两个编译单元）
#include "node.h"
#include "uv.h"
#include <cstdio>
#include <string>
#include <cstring>
#include <vector>
#include <memory>
#include <atomic>
#include <unistd.h>

// 供 napi_init.cpp 调用（那里只碰鸿蒙 NAPI）
void vitreusNodeMain(const char *scriptC, const char *statusC, const char *vaultOverrideC) {
    std::string script(scriptC);
    std::string statusPath(statusC);
    std::string vaultOverride(vaultOverrideC != nullptr ? vaultOverrideC : "");

    // JS 字符串字面量包装（路径进 require('...') 用）
    auto jsonQuote = [](const std::string &s) {
        std::string out = "\"";
        for (char c : s) {
            if (c == '"' || c == '\\') out += '\\';
            out += c;
        }
        return out + "\"";
    };

    auto log = [&statusPath](const std::string &msg) {
        FILE *f = fopen(statusPath.c_str(), "a");
        if (f) {
            fprintf(f, "[cpp] %s\n", msg.c_str());
            fclose(f);
        }
    };

    // 防重入：InitializeNodeWithArgs 全进程只能调一次，重试按钮再点直接拒绝
    static std::atomic<bool> s_nodeStarted{false};
    if (s_nodeStarted.exchange(true)) {
        log("Node already started, ignore duplicate call");
        return;
    }

    // ⚠️ 鸿蒙沙箱 seccomp 不放行 io_uring（syscall 425）→ libuv 补丁版已禁用
    setenv("UV_USE_IO_URING", "0", 1);
    // status 文件路径走环境变量（不占 argv 位置，避免 process.argv 错位）
    setenv("VITREUS_STATUS_FILE", statusPath.c_str(), 1);

    // ignis server 环境变量（sandbox 布局）：
    // script = filesDir/ignis/apps/ignis-server/server/index.js
    // VAULT_ROOT = 用户笔记库（filesDir/vaults，config.js 会自动建）
    // DATA_ROOT = ignis 数据（filesDir/ignis-data）
    // OBSIDIAN_ASSETS_PATH = 用户自备的 Obsidian 前端资源（filesDir/obsidian-assets，
    //   app 不分发受版权保护的内容；没有时 server 会 500 但 API/静态资源可用）
    {
        std::string dir(script);
        auto pos = dir.find("/apps/ignis-server/server/index.js");
        if (pos != std::string::npos) {
            // 布局：filesDir/ignis/apps/ignis-server/server/index.js
            // pos 指向 "/apps/..."，所以 substr(0,pos) 就是 ignisRoot（别再多剥！）
            std::string ignisRoot = dir.substr(0, pos);                          // filesDir/ignis
            std::string filesRoot = ignisRoot.substr(0, ignisRoot.rfind('/'));  // filesDir
            std::string serverDir = ignisRoot + "/apps/ignis-server/server";    // chdir 用
            // vault 根三级决策（黑框日志明示落点，不再猜）：
            //   1. ArkTS 传来的 override（它已试写探针成功）
            //   2. C++ 自己再验一遍（native 层 open 权限可能与 ArkTS fs 不同！）
            //   3. 都不行 → 沙箱
            std::string vaultRoot = filesRoot + "/vaults";
            if (!vaultOverride.empty()) {
                std::string probe = vaultOverride + "/.vitreus-probe";
                FILE *pf = fopen(probe.c_str(), "w");
                if (pf) {
                    fputs("ok", pf);
                    fclose(pf);
                    remove(probe.c_str());
                    vaultRoot = vaultOverride;
                    log("vault root -> " + vaultOverride + " (native probe OK)");
                } else {
                    log("vault root -> sandbox (native probe FAILED on " + vaultOverride + ")");
                }
            } else {
                log("vault root -> sandbox (no override from ArkTS — Download probe failed there)");
            }
            setenv("VAULT_ROOT", vaultRoot.c_str(), 1);
            setenv("DATA_ROOT", (filesRoot + "/ignis-data").c_str(), 1);
            setenv("PORT", "6791", 1);
            // 本地 server 只允许本机访问，禁止局域网直连
            setenv("LISTEN_HOST", "127.0.0.1", 1);
            setenv("OBSIDIAN_ASSETS_PATH", (filesRoot + "/obsidian-assets").c_str(), 1);
            if (chdir(serverDir.c_str()) != 0) {
                log("warn: chdir to server dir failed");
            } else {
                log("cwd -> " + serverDir);
            }
            log("ignis env: VAULT_ROOT=" + std::string(getenv("VAULT_ROOT")) + " PORT=6791 LISTEN_HOST=127.0.0.1");
        }
    }
    // Node 的报错（脚本异常 stack、fatal message）全走 stderr，app 里默认被丢弃。
    // 重定向到 status 文件 → 黑框直接显示死因原文
    if (!freopen(statusPath.c_str(), "a", stderr)) {
        log("warn: freopen stderr failed");
    }
    if (!freopen(statusPath.c_str(), "a", stdout)) {
        log("warn: freopen stdout failed");
    }

    try {
        log("=== embed start (io_uring=off, jitless, no-inspector) ===");
        // --jitless: W^X 策略禁 RWX，V8 走纯解释器
        std::vector<std::string> args{"node", "--jitless", script};
        std::vector<std::string> exec_args;
        std::vector<std::string> errors;
        std::unique_ptr<node::MultiIsolatePlatform> platform;

        int exitCode = node::InitializeNodeWithArgs(&args, &exec_args, &errors);
        if (exitCode != 0) {
            std::string detail = errors.empty() ? "(no detail)" : errors[0];
            log("InitializeNodeWithArgs failed: " + std::to_string(exitCode) + " " + detail);
            return;
        }
        log("InitializeNodeWithArgs OK");

        platform = node::MultiIsolatePlatform::Create(1);
        v8::V8::InitializePlatform(platform.get());
        v8::V8::Initialize();
        log("V8 init OK");

        std::unique_ptr<node::CommonEnvironmentSetup> setup(
            node::CommonEnvironmentSetup::Create(platform.get(), &errors, args, exec_args));
        if (!setup) {
            std::string detail = errors.empty() ? "(no detail)" : errors[0];
            log("CommonEnvironmentSetup failed: " + detail);
            return;
        }
        log("CommonEnvironmentSetup OK");

        v8::Isolate *isolate = setup->isolate();
        {
            v8::Locker locker(isolate);
            v8::Isolate::Scope isolate_scope(isolate);
            v8::HandleScope handle_scope(isolate);

            v8::Local<v8::Context> context = node::NewContext(isolate);
            if (context.IsEmpty()) {
                log("NewContext failed");
                return;
            }
            v8::Context::Scope context_scope(context);

            // kNoFlags（非 kDefaultFlags）：不占进程状态、不启 inspector
            // （沙箱里 InitializeInspector 必崩；嵌入式也不该动全局状态）
            node::Environment *envPtr =
                node::CreateEnvironment(setup->isolate_data(), context, args, exec_args,
                                         node::EnvironmentFlags::kNoFlags);
            if (!envPtr) {
                log("CreateEnvironment failed");
                return;
            }
            log("CreateEnvironment OK");

            // 嵌入式关键：JS 抛未捕获异常时 Node 默认 exit() 会拉崩整个 app。
            // 改写为：记日志 + 停事件循环（uv_stop），宿主进程安全。
            // 注意：Environment 在 node.h 里只是前向声明，不能调它的方法；
            // 用全局 uv_default_loop()（CommonEnvironmentSetup 用的就是 default loop）
            node::SetProcessExitHandler(envPtr, [log](node::Environment *env, int code) {
                log("JS requested exit(" + std::to_string(code) + "), stopping event loop (app stays alive)");
                (void)env;
                uv_stop(uv_default_loop());
            });

            // ⚠️ LoadEnvironment 字符串里的 require 是 embedder 专用版——只认 node:
            // 内置模块，不解析文件路径（直接 require(路径) 会 ERR_UNKNOWN_BUILTIN_MODULE）。
            // 官方姿势：require('module') 拿内置模块 → createRequire(绝对路径) 造一个
            // 真文件 require → 加载 bundle（获得正确 __filename/__dirname）。
            std::string bootstrap =
                "const createRequire = require('module').createRequire;"
                "const fileRequire = createRequire(" + jsonQuote(script) + ");"
                "fileRequire(" + jsonQuote(script) + ");";
            v8::MaybeLocal<v8::Value> loadResult = node::LoadEnvironment(envPtr, bootstrap);
            if (loadResult.IsEmpty()) {
                log("LoadEnvironment empty (script error)");
            } else {
                log("LoadEnvironment OK");
            }

            int code = node::SpinEventLoop(envPtr).FromMaybe(1);
            log("event loop exit, code=" + std::to_string(code));

            node::Stop(envPtr);
            node::FreeEnvironment(envPtr);
        }
        platform->DrainTasks(isolate);
    } catch (const std::exception &e) {
        log(std::string("C++ exception: ") + e.what());
    } catch (...) {
        log("unknown C++ exception");
    }
}
