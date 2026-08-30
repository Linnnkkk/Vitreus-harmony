// 鸿蒙 NAPI 桥 —— 只 include 鸿蒙 native_api.h（不碰 node.h，
// 两者 NAPI 声明冲突，Node 侧在 node_embed.cpp）
#include "napi/native_api.h"
#include <string>
#include <thread>
#include <vector>
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// node_embed.cpp 实现（链接时合体）
void vitreusNodeMain(const char *script, const char *statusPath, const char *vaultOverride);

// 枚举本机所有网卡 IPv4（wifiManager 只报 STA 客户端 IP；热点场景 ap 网卡要靠这里）
// 返回 ["wlan0:192.168.1.5", "ap0:192.168.43.1", ...]，过滤 loopback/未配置/蜂窝(rmnet|ccmni)/usb
static napi_value GetLanIps(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value arr;
    napi_create_array(env, &arr);
    struct ifaddrs *ifs = nullptr;
    if (getifaddrs(&ifs) != 0 || !ifs) {
        return arr;
    }
    uint32_t idx = 0;
    for (struct ifaddrs *it = ifs; it != nullptr; it = it->ifa_next) {
        if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET) continue;
        std::string name = it->ifa_name ? it->ifa_name : "";
        if (name == "lo") continue;
        // 蜂窝网卡通常 rmnet/ccmni 前缀；usb 共享排除——伺服器只服务局域网
        if (name.rfind("rmnet", 0) == 0 || name.rfind("ccmni", 0) == 0 || name.rfind("usb", 0) == 0) continue;
        char buf[INET_ADDRSTRLEN] = {0};
        const char *ip = inet_ntop(AF_INET,
            &((struct sockaddr_in *)it->ifa_addr)->sin_addr, buf, sizeof(buf));
        if (!ip) continue;
        std::string val = name + ":" + ip;
        if (std::string(ip) == "0.0.0.0") continue;
        napi_value item;
        napi_create_string_utf8(env, val.c_str(), val.size(), &item);
        napi_set_element(env, arr, idx++, item);
    }
    freeifaddrs(ifs);
    return arr;
}

static napi_value StartNodeServer(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return nullptr;
    }
    auto readStr = [env](napi_value v) -> std::string {
        size_t len = 0;
        napi_get_value_string_utf8(env, v, nullptr, 0, &len);
        std::string s(len, '\0');
        napi_get_value_string_utf8(env, v, &s[0], len + 1, &len);
        return s;
    };
    std::string script = readStr(args[0]);
    std::string statusPath = readStr(args[1]);
    // 第三参数可选：用户选的 vault 专属文件夹（没传 = 空串 = 默认沙箱）
    std::string vaultOverride = (argc >= 3 && args[2] != nullptr) ? readStr(args[2]) : "";

    std::thread t([script, statusPath, vaultOverride]() {
        vitreusNodeMain(script.c_str(), statusPath.c_str(), vaultOverride.c_str());
    });
    t.detach();

    napi_value result;
    napi_get_null(env, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startNodeServer", nullptr, StartNodeServer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLanIps", nullptr, GetLanIps, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module vitreusModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&vitreusModule);
}
