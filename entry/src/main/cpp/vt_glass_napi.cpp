/*
 * vt_glass_napi.cpp
 *
 * 液态玻璃光效层 NAPI 桥（合并进 entry 模块，不建独立 so）
 * 导出：vtGlassRegister / vtGlassUnregister / vtGlassSetParams /
 *       vtGlassStart / vtGlassStop / vtGlassTouch / vtGlassRipple
 * napi_init.cpp 的 Init 里调用 VtGlassRegisterNapi() 完成挂载。
 */

#include "vt_glass_render.h"
#include <hilog/log.h>
#include <string>
#include <unordered_map>
#include <mutex>
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <ace/xcomponent/native_interface_xcomponent.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x3200
#undef LOG_TAG
#define LOG_TAG "VtGlassNapi"

static std::unordered_map<std::string, VtGlassRender*> g_renderers;
static std::mutex g_mutex;

static VtGlassRender* Get(const std::string& id);

// napi_init.cpp Init 里 napi_unwrap(exports) 解出的 XComponent（本 so 被 XComponent 加载时注入）
static OH_NativeXComponent* g_component = nullptr;
void VtGlassSetComponent(OH_NativeXComponent* c) { g_component = c; }

// ── XComponent NDK 回调（API 12 模型：surface 事件里拿 window）──
static void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window)
{
    char idBuf[256] = {0};
    uint64_t len = sizeof(idBuf) - 1;
    if (OH_NativeXComponent_GetXComponentId(component, idBuf, &len) != 0) {
        return;
    }
    VtGlassRender* r = Get(idBuf);
    if (r && r->Initialize((NativeWindow*)window)) {
        r->StartRenderLoop();
    }
}

static void OnSurfaceChangedCB(OH_NativeXComponent* component, void* window)
{
    char idBuf[256] = {0};
    uint64_t len = sizeof(idBuf) - 1;
    if (OH_NativeXComponent_GetXComponentId(component, idBuf, &len) != 0) {
        return;
    }
    VtGlassRender* r = Get(idBuf);
    if (r) {
        r->OnSurfaceChanged((NativeWindow*)window);
    }
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window)
{
    char idBuf[256] = {0};
    uint64_t len = sizeof(idBuf) - 1;
    if (OH_NativeXComponent_GetXComponentId(component, idBuf, &len) != 0) {
        return;
    }
    VtGlassRender* r = Get(idBuf);
    if (r) {
        r->OnSurfaceDestroyed();
    }
}

static void OnDispatchTouchEventCB(OH_NativeXComponent* component, void* window) {}

static VtGlassRender* Get(const std::string& id)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto it = g_renderers.find(id);
    return it != g_renderers.end() ? it->second : nullptr;
}

static bool ReadId(napi_env env, size_t argc, napi_value* argv, std::string& out)
{
    if (argc < 1) {
        return false;
    }
    char buf[256] = {0};
    size_t len = 0;
    if (napi_get_value_string_utf8(env, argv[0], buf, sizeof(buf), &len) != napi_ok) {
        return false;
    }
    out.assign(buf, len);
    return true;
}

static napi_value VTGlassRegister(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (!ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassRegister requires id");
        return nullptr;
    }
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        if (g_renderers.count(id) == 0) {
            g_renderers[id] = new (std::nothrow) VtGlassRender(id);
        }
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassUnregister(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (!ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassUnregister requires id");
        return nullptr;
    }
    VtGlassRender* renderer = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        auto it = g_renderers.find(id);
        if (it != g_renderers.end()) {
            renderer = it->second;
            g_renderers.erase(it);
        }
    }
    if (renderer) {
        delete renderer;   // 析构里 StopRenderLoop + Destroy
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassSetParams(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (argc < 3 || !ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassSetParams requires id, intensity, waveSpeed");
        return nullptr;
    }
    double intensity = 1.0, waveSpeed = 1.2;
    napi_get_value_double(env, argv[1], &intensity);
    napi_get_value_double(env, argv[2], &waveSpeed);
    VtGlassRender* renderer = Get(id);
    if (renderer) {
        renderer->SetParams((float)intensity, (float)waveSpeed);
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassStart(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (!ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassStart requires id");
        return nullptr;
    }
    VtGlassRender* renderer = Get(id);
    if (!renderer) {
        napi_throw_error(env, nullptr, "renderer not registered");
        return nullptr;
    }
    OH_NativeXComponent* component = g_component;
    if (!component) {
        napi_throw_error(env, nullptr, "no XComponent attached (so not loaded by XComponent?)");
        return nullptr;
    }
    // API 12 模型：注册 surface 回调，window 由 OnSurfaceCreated 递进来
    static OH_NativeXComponent_Callback cb;
    cb.OnSurfaceCreated = OnSurfaceCreatedCB;
    cb.OnSurfaceChanged = OnSurfaceChangedCB;
    cb.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
    cb.DispatchTouchEvent = OnDispatchTouchEventCB;
    OH_NativeXComponent_RegisterCallback(component, &cb);
    // 若 surface 已存在（注册晚于创建），直接初始化启动
    if (renderer->IsInitialized()) {
        renderer->StartRenderLoop();
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassStop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (!ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassStop requires id");
        return nullptr;
    }
    VtGlassRender* renderer = Get(id);
    if (renderer) {
        renderer->StopRenderLoop();
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassTouch(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (argc < 3 || !ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassTouch requires id, x, y");
        return nullptr;
    }
    double x = -1, y = -1;
    napi_get_value_double(env, argv[1], &x);
    napi_get_value_double(env, argv[2], &y);
    VtGlassRender* renderer = Get(id);
    if (renderer) {
        renderer->SetTouchPosition((float)x, (float)y);
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

static napi_value VTGlassRipple(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string id;
    if (argc < 4 || !ReadId(env, argc, argv, id)) {
        napi_throw_error(env, nullptr, "vtGlassRipple requires id, x, y, force");
        return nullptr;
    }
    double x = 0, y = 0, force = 1;
    napi_get_value_double(env, argv[1], &x);
    napi_get_value_double(env, argv[2], &y);
    napi_get_value_double(env, argv[3], &force);
    VtGlassRender* renderer = Get(id);
    if (renderer) {
        renderer->TriggerRipple((float)x, (float)y, (float)force);
    }
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

// napi_init.cpp 的 Init() 调用本函数挂载 glass 接口
void VtGlassRegisterNapi(napi_env env, napi_value exports)
{
    napi_property_descriptor props[] = {
        {"vtGlassRegister",     nullptr, VTGlassRegister,     nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassUnregister",   nullptr, VTGlassUnregister,   nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassSetParams",    nullptr, VTGlassSetParams,    nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassStart",        nullptr, VTGlassStart,        nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassStop",         nullptr, VTGlassStop,         nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassTouch",        nullptr, VTGlassTouch,        nullptr, nullptr, nullptr, napi_default, nullptr},
        {"vtGlassRipple",       nullptr, VTGlassRipple,       nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
}
