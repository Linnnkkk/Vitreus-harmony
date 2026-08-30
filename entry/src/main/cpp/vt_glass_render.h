/*
 * vt_glass_render.h
 *
 * Vitreus 液态玻璃光效层渲染器
 * 基于 JUEMING-006/Liquid-glass 的 glass_render 架构改造：
 *   - 砍掉背景纹理（参考实现是程序化假背景）
 *   - 保留：EGL 生命周期 / 渲染线程 / 涟漪环形缓冲 / 脏标记 uniform
 *   - 混合模式：标准 alpha blend（glBlendFunc SRC_ALPHA, ONE_MINUS_SRC_ALPHA）
 *     清屏 (0,0,0,0) —— 中心透明，只画光效
 */

#ifndef VT_GLASS_RENDER_H
#define VT_GLASS_RENDER_H

#include <string>
#include <atomic>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <cstdint>

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#include <ace/xcomponent/native_interface_xcomponent.h>

class VtGlassRender {
public:
    VtGlassRender(const std::string& id);
    ~VtGlassRender();

    // window 由 XComponent NDK 回调（OnSurfaceCreated）传入
    bool Initialize(NativeWindow* window);
    void Destroy();

    // surface 尺寸变化（OnSurfaceChanged）：重建 surface 再继续
    void OnSurfaceChanged(NativeWindow* window);
    // surface 销毁（OnSurfaceDestroyed）
    void OnSurfaceDestroyed();

    void SetParams(float intensity, float waveSpeed);
    void SetTouchPosition(float nx, float ny);   // [0,1]，(-1,-1)=无
    void TriggerRipple(float nx, float ny, float force);

    void StartRenderLoop();
    void StopRenderLoop();
    bool IsInitialized() const { return m_initialized.load(); }

private:
    bool InitShaders();
    bool InitGeometry();
    void RenderFrame(double deltaSec);
    void UpdateRipples(double deltaSec);

    // EGL（复用 vt_egl_manager）
    void* m_egl;              // EglManager*（void* 避免头文件泄漏）
    NativeWindow* m_window = nullptr;

    std::string m_id;
    GLuint m_program = 0;
    GLuint m_vbo = 0;
    GLuint m_vao = 0;

    // uniforms
    GLint m_uTime = -1;
    GLint m_uTouchPos = -1;
    GLint m_uIntensity = -1;
    GLint m_uWaveSpeed = -1;
    GLint m_uAspect = -1;
    GLint m_uRipples = -1;

    // params（脏标记）
    std::mutex m_paramsMutex;
    float m_intensity = 1.0f;
    float m_waveSpeed = 1.2f;
    float m_touchX = -1.0f;
    float m_touchY = -1.0f;
    bool m_paramsDirty = true;

    // 涟漪池（固定 16 槽环形缓冲）
    struct Ripple { float x, y, radius, strength; };
    static constexpr int MAX_RIPPLES = 16;
    Ripple m_ripplePool[MAX_RIPPLES] = {};
    int m_rippleHead = 0;
    std::mutex m_rippleMutex;

    // 渲染循环
    std::thread m_thread;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_initialized{false};
    std::mutex m_initMutex;
    std::condition_variable m_frameCV;

    uint32_t m_width = 0;
    uint32_t m_height = 0;
    double m_timeAccum = 0.0;
};

#endif // VT_GLASS_RENDER_H
