/*
 * egl_manager.cpp
 *
 * Implementation of EGL context management.
 */

#include "vt_egl_manager.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0x3200
#undef LOG_TAG
#define LOG_TAG "EglManager"

EglManager::EglManager()
    : m_display(EGL_NO_DISPLAY)
    , m_context(EGL_NO_CONTEXT)
    , m_surface(EGL_NO_SURFACE)
    , m_config(nullptr)
    , m_width(0)
    , m_height(0)
    , m_initialized(false)
{
}

EglManager::~EglManager()
{
    Destroy();
}

bool EglManager::Initialize(NativeWindow* nativeWindow)
{
    if (m_initialized) {
        OH_LOG_INFO(LOG_APP, "EglManager already initialized");
        return true;
    }

    if (!nativeWindow) {
        OH_LOG_ERROR(LOG_APP, "NativeWindow is null");
        return false;
    }

    // 1. Get EGL display
    m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (m_display == EGL_NO_DISPLAY) {
        OH_LOG_ERROR(LOG_APP, "eglGetDisplay failed");
        return false;
    }

    // 2. Initialize EGL
    EGLint majorVersion = 0;
    EGLint minorVersion = 0;
    if (!eglInitialize(m_display, &majorVersion, &minorVersion)) {
        OH_LOG_ERROR(LOG_APP, "eglInitialize failed");
        m_display = EGL_NO_DISPLAY;
        return false;
    }
    OH_LOG_INFO(LOG_APP, "EGL initialized: v%d.%d", majorVersion, minorVersion);

    // 3. Choose EGL config
    if (!ChooseConfig(m_config)) {
        OH_LOG_ERROR(LOG_APP, "Failed to choose EGL config");
        Destroy();
        return false;
    }

    // 4. Create EGL context
    if (!CreateContext(m_config)) {
        OH_LOG_ERROR(LOG_APP, "Failed to create EGL context");
        Destroy();
        return false;
    }

    // 5. Create EGL surface from NativeWindow
    if (!CreateSurface(m_config, nativeWindow)) {
        OH_LOG_ERROR(LOG_APP, "Failed to create EGL surface");
        Destroy();
        return false;
    }

    // 5.5 Query surface dimensions（EGL 标准 API，替代本 SDK 已不存在的 OH_NativeWindow_GetWidth/Height）
    EGLint sw = 0, sh = 0;
    if (eglQuerySurface(m_display, m_surface, EGL_WIDTH, &sw) &&
        eglQuerySurface(m_display, m_surface, EGL_HEIGHT, &sh)) {
        m_width = sw;
        m_height = sh;
    }

    // 6. Make context current
    if (!MakeCurrent()) {
        OH_LOG_ERROR(LOG_APP, "Failed to make EGL context current");
        Destroy();
        return false;
    }

    m_initialized = true;
    OH_LOG_INFO(LOG_APP, "EglManager initialized: %dx%d", m_width, m_height);
    return true;
}

void EglManager::Destroy()
{
    if (!m_initialized) {
        return;
    }

    // Release context
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

    // Destroy surface
    if (m_surface != EGL_NO_SURFACE) {
        eglDestroySurface(m_display, m_surface);
        m_surface = EGL_NO_SURFACE;
    }

    // Destroy context
    if (m_context != EGL_NO_CONTEXT) {
        eglDestroyContext(m_display, m_context);
        m_context = EGL_NO_CONTEXT;
    }

    // Terminate display
    if (m_display != EGL_NO_DISPLAY) {
        eglTerminate(m_display);
        m_display = EGL_NO_DISPLAY;
    }

    m_config = nullptr;
    m_width = 0;
    m_height = 0;
    m_initialized = false;

    OH_LOG_INFO(LOG_APP, "EglManager destroyed");
}

bool EglManager::MakeCurrent()
{
    if (m_display == EGL_NO_DISPLAY || m_surface == EGL_NO_SURFACE || m_context == EGL_NO_CONTEXT) {
        return false;
    }
    return eglMakeCurrent(m_display, m_surface, m_surface, m_context) == EGL_TRUE;
}

bool EglManager::SwapBuffers()
{
    if (m_display == EGL_NO_DISPLAY || m_surface == EGL_NO_SURFACE) {
        return false;
    }
    return eglSwapBuffers(m_display, m_surface) == EGL_TRUE;
}

bool EglManager::ChooseConfig(EGLConfig& config)
{
    // Configure for OpenGL ES 3.0 with alpha (needed for glass transparency)
    const EGLint configAttribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_ALPHA_SIZE,      8,
        EGL_DEPTH_SIZE,      0,
        EGL_STENCIL_SIZE,    0,
        EGL_NONE
    };

    EGLint numConfigs = 0;
    if (!eglChooseConfig(m_display, configAttribs, nullptr, 0, &numConfigs) || numConfigs == 0) {
        OH_LOG_ERROR(LOG_APP, "eglChooseConfig query failed, numConfigs=%{public}d", numConfigs);
        return false;
    }

    if (!eglChooseConfig(m_display, configAttribs, &config, 1, &numConfigs) || numConfigs != 1) {
        OH_LOG_ERROR(LOG_APP, "eglChooseConfig select failed");
        return false;
    }

    return true;
}

bool EglManager::CreateContext(EGLConfig config)
{
    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };

    m_context = eglCreateContext(m_display, config, EGL_NO_CONTEXT, contextAttribs);
    if (m_context == EGL_NO_CONTEXT) {
        OH_LOG_ERROR(LOG_APP, "eglCreateContext failed, error=0x%{public}x", eglGetError());
        return false;
    }

    return true;
}

bool EglManager::CreateSurface(EGLConfig config, NativeWindow* nativeWindow)
{
    m_surface = eglCreateWindowSurface(m_display, config, (EGLNativeWindowType)nativeWindow, nullptr);
    if (m_surface == EGL_NO_SURFACE) {
        OH_LOG_ERROR(LOG_APP, "eglCreateWindowSurface failed, error=0x%{public}x", eglGetError());
        return false;
    }

    return true;
}
