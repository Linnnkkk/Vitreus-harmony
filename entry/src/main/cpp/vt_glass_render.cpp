/*
 * vt_glass_render.cpp
 *
 * 光效层渲染实现：全屏 quad + 光效着色器 + 透明清屏。
 * 渲染线程按 ~60fps 上限步进（条件变量节流，空转不烧 CPU）。
 */

#include "vt_glass_render.h"
#include "vt_glass_shader.h"
#include "vt_egl_manager.h"

#include <hilog/log.h>
#include <chrono>
#include <cstring>
#include <cmath>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x3200
#undef LOG_TAG
#define LOG_TAG "VtGlass"

VtGlassRender::VtGlassRender(const std::string& id) : m_id(id), m_egl(nullptr)
{
    memset(m_ripplePool, 0, sizeof(m_ripplePool));
}

VtGlassRender::~VtGlassRender()
{
    StopRenderLoop();
    Destroy();
}

bool VtGlassRender::Initialize(NativeWindow* window)
{
    if (m_initialized.load()) {
        return true;
    }
    std::lock_guard<std::mutex> lk(m_initMutex);
    if (m_initialized.load()) {
        return true;
    }
    if (!window) {
        OH_LOG_ERROR(LOG_APP, "VtGlass [%{public}s]: window null", m_id.c_str());
        return false;
    }
    m_window = window;

    EglManager* egl = new (std::nothrow) EglManager();
    if (!egl || !egl->Initialize(window)) {
        OH_LOG_ERROR(LOG_APP, "VtGlass [%{public}s]: egl init failed", m_id.c_str());
        delete egl;
        return false;
    }
    m_egl = egl;
    m_width = egl->GetWidth();
    m_height = egl->GetHeight();

    if (!InitShaders() || !InitGeometry()) {
        Destroy();
        return false;
    }

    m_initialized.store(true);
    OH_LOG_INFO(LOG_APP, "VtGlass [%{public}s]: init ok %{public}ux%{public}u", m_id.c_str(), m_width, m_height);
    return true;
}

void VtGlassRender::OnSurfaceChanged(NativeWindow* window)
{
    // surface 重建：停渲染、拆 EGL、按新 window 重来
    StopRenderLoop();
    Destroy();
    if (Initialize(window)) {
        StartRenderLoop();
    }
}

void VtGlassRender::OnSurfaceDestroyed()
{
    StopRenderLoop();
    Destroy();
}

bool VtGlassRender::InitShaders()
{
    auto compile = [](GLenum type, const char* src) -> GLuint {
        GLuint sh = glCreateShader(type);
        glShaderSource(sh, 1, &src, nullptr);
        glCompileShader(sh);
        GLint ok = GL_FALSE;
        glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[512] = {0};
            glGetShaderInfoLog(sh, sizeof(log), nullptr, log);
            OH_LOG_ERROR(LOG_APP, "VtGlass shader compile fail: %{public}s", log);
            glDeleteShader(sh);
            return 0;
        }
        return sh;
    };

    GLuint vs = compile(GL_VERTEX_SHADER, VT_VERTEX_SHADER);
    GLuint fs = compile(GL_FRAGMENT_SHADER, VT_FRAGMENT_SHADER);
    if (!vs || !fs) {
        return false;
    }
    m_program = glCreateProgram();
    glAttachShader(m_program, vs);
    glAttachShader(m_program, fs);
    glLinkProgram(m_program);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = GL_FALSE;
    glGetProgramiv(m_program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512] = {0};
        glGetProgramInfoLog(m_program, sizeof(log), nullptr, log);
        OH_LOG_ERROR(LOG_APP, "VtGlass program link fail: %{public}s", log);
        return false;
    }

    m_uTime = glGetUniformLocation(m_program, "uTime");
    m_uTouchPos = glGetUniformLocation(m_program, "uTouchPos");
    m_uIntensity = glGetUniformLocation(m_program, "uIntensity");
    m_uWaveSpeed = glGetUniformLocation(m_program, "uWaveSpeed");
    m_uAspect = glGetUniformLocation(m_program, "uAspect");
    m_uRipples = glGetUniformLocation(m_program, "uRipples");
    return true;
}

bool VtGlassRender::InitGeometry()
{
    // 全屏三角带 quad（clip space）
    const float verts[] = {
        -1.f, -1.f,
         1.f, -1.f,
        -1.f,  1.f,
         1.f,  1.f,
    };
    glGenVertexArrays(1, &m_vao);
    glGenBuffers(1, &m_vbo);
    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, (void*)0);
    glBindVertexArray(0);
    return true;
}

void VtGlassRender::SetParams(float intensity, float waveSpeed)
{
    std::lock_guard<std::mutex> lk(m_paramsMutex);
    m_intensity = intensity;
    m_waveSpeed = waveSpeed;
    m_paramsDirty = true;
}

void VtGlassRender::SetTouchPosition(float nx, float ny)
{
    std::lock_guard<std::mutex> lk(m_paramsMutex);
    m_touchX = nx;
    m_touchY = ny;
}

void VtGlassRender::TriggerRipple(float nx, float ny, float force)
{
    std::lock_guard<std::mutex> lk(m_rippleMutex);
    Ripple& r = m_ripplePool[m_rippleHead];
    r.x = nx; r.y = ny;
    r.radius = 0.02f;
    r.strength = force;
    m_rippleHead = (m_rippleHead + 1) % MAX_RIPPLES;
}

void VtGlassRender::UpdateRipples(double dt)
{
    std::lock_guard<std::mutex> lk(m_rippleMutex);
    for (int i = 0; i < MAX_RIPPLES; i++) {
        Ripple& r = m_ripplePool[i];
        if (r.strength <= 0.f) {
            continue;
        }
        r.radius += (float)dt * 0.55f;             // 扩散速度
        r.strength -= (float)dt * 1.1f;            // 衰减
        if (r.radius > 1.4f || r.strength <= 0.f) {
            r.strength = 0.f;                       // 哨兵空槽
        }
    }
}

void VtGlassRender::RenderFrame(double dt)
{
    UpdateRipples(dt);

    glViewport(0, 0, (GLsizei)m_width, (GLsizei)m_height);
    glClearColor(0.f, 0.f, 0.f, 0.f);
    glClear(GL_COLOR_BUFFER_BIT);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(m_program);

    m_timeAccum += dt;
    glUniform1f(m_uTime, (GLfloat)m_timeAccum);

    float intensity, waveSpeed, tx, ty;
    {
        std::lock_guard<std::mutex> lk(m_paramsMutex);
        intensity = m_intensity;
        waveSpeed = m_waveSpeed;
        tx = m_touchX;
        ty = m_touchY;
    }
    glUniform1f(m_uIntensity, intensity);
    glUniform1f(m_uWaveSpeed, waveSpeed);
    glUniform2f(m_uTouchPos, tx, ty);
    glUniform1f(m_uAspect, m_height > 0 ? (float)m_width / (float)m_height : 1.f);

    {
        std::lock_guard<std::mutex> lk(m_rippleMutex);
        float pool[MAX_RIPPLES][4];
        for (int i = 0; i < MAX_RIPPLES; i++) {
            pool[i][0] = m_ripplePool[i].x;
            pool[i][1] = m_ripplePool[i].y;
            pool[i][2] = m_ripplePool[i].radius;
            pool[i][3] = m_ripplePool[i].strength;
        }
        glUniform4fv(m_uRipples, MAX_RIPPLES, &pool[0][0]);
    }

    glBindVertexArray(m_vao);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0);

    EglManager* egl = (EglManager*)m_egl;
    if (egl) {
        egl->SwapBuffers();
    }
}

void VtGlassRender::StartRenderLoop()
{
    if (m_running.exchange(true)) {
        return;  // 已在跑
    }
    m_thread = std::thread([this]() {
        // EGL context 必须绑定到使用它的线程——渲染线程开头 MakeCurrent
        EglManager* egl = (EglManager*)m_egl;
        if (!egl || !egl->MakeCurrent()) {
            OH_LOG_ERROR(LOG_APP, "VtGlass [%{public}s]: render thread MakeCurrent failed", m_id.c_str());
            m_running.store(false);
            return;
        }
        auto last = std::chrono::steady_clock::now();
        const auto frameMin = std::chrono::microseconds(16667);  // 60fps 上限
        while (m_running.load()) {
            auto now = std::chrono::steady_clock::now();
            std::chrono::duration<double> dd = now - last;
            double dt = dd.count();
            last = now;

            RenderFrame(dt);

            // 帧节流（不追 vsync，光效层对相位不敏感）
            std::this_thread::sleep_until(now + frameMin);
        }
    });
}

void VtGlassRender::StopRenderLoop()
{
    if (!m_running.exchange(false)) {
        return;
    }
    if (m_thread.joinable()) {
        m_thread.join();
    }
}

void VtGlassRender::Destroy()
{
    StopRenderLoop();
    if (m_program) { glDeleteProgram(m_program); m_program = 0; }
    if (m_vbo) { glDeleteBuffers(1, &m_vbo); m_vbo = 0; }
    if (m_vao) { glDeleteVertexArrays(1, &m_vao); m_vao = 0; }
    if (m_egl) {
        EglManager* egl = (EglManager*)m_egl;
        egl->Destroy();
        delete egl;
        m_egl = nullptr;
    }
    m_window = nullptr;
    m_initialized.store(false);
}
