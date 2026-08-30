/*
 * egl_manager.h
 *
 * EGL context management for the glass renderer.
 * Handles EGL Display, Config, Context, and Surface lifecycle.
 */

#ifndef EGL_MANAGER_H
#define EGL_MANAGER_H

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#include <string>

class EglManager {
public:
    EglManager();
    ~EglManager();

    // Initialize EGL with a NativeWindow
    bool Initialize(NativeWindow* nativeWindow);

    // Destroy EGL resources
    void Destroy();

    // Make the EGL context current
    bool MakeCurrent();

    // Swap buffers to present frame
    bool SwapBuffers();

    // Get the EGL display
    EGLDisplay GetDisplay() const { return m_display; }

    // Get the EGL context
    EGLContext GetContext() const { return m_context; }

    // Get viewport dimensions
    int GetWidth() const { return m_width; }
    int GetHeight() const { return m_height; }

    // Check if EGL is initialized
    bool IsInitialized() const { return m_initialized; }

private:
    bool ChooseConfig(EGLConfig& config);
    bool CreateSurface(EGLConfig config, NativeWindow* nativeWindow);
    bool CreateContext(EGLConfig config);

    // EGL objects
    EGLDisplay m_display;
    EGLContext m_context;
    EGLSurface m_surface;
    EGLConfig m_config;

    // Viewport
    int m_width;
    int m_height;

    // State
    bool m_initialized;
};

#endif // EGL_MANAGER_H
