// Node 嵌入实现 —— 只 include Node 头（node.h 会拉进 Node 版 NAPI 声明），
// 绝不 include 鸿蒙 native_api.h（两者都声明 napi_* 会签名冲突，所以拆两个编译单元）
#include "node.h"
#include "uv.h"
#include <cstdio>
#include <string>
#include <vector>
#include <memory>
#include <atomic>

// 供 napi_init.cpp 调用（那里只碰鸿蒙 NAPI）
void vitreusNodeMain(const char *scriptC, const char *statusC) {
    std::string script(scriptC);
    std::string statusPath(statusC);

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

            // ⚠️ LoadEnvironment 的第二个参数是【JS 源码字符串】不是文件路径（node.h:784）
            // 之前把路径传进去被当 JS 解析 → "Invalid regular expression flags"
            std::FILE *sf = std::fopen(script.c_str(), "rb");
            if (!sf) {
                log("cannot open script file: " + script);
                return;
            }
            std::string source;
            char buf[4096];
            size_t n;
            while ((n = std::fread(buf, 1, sizeof(buf), sf)) > 0) {
                source.append(buf, n);
            }
            std::fclose(sf);
            log("script loaded, " + std::to_string(source.size()) + " bytes");

            v8::MaybeLocal<v8::Value> loadResult = node::LoadEnvironment(envPtr, source);
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
