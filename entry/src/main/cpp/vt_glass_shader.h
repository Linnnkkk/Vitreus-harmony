/*
 * vt_glass_shader.h
 *
 * Vitreus 液态玻璃光效层着色器（纯叠加层版本）
 *
 * 与参考实现（JUEMING-006/Liquid-glass）的区别：
 * 参考实现采样一张程序化自绘的背景纹理做折射——玻璃里的内容是假的，
 * 与身后真实 UI 对不上。本版本砍掉背景纹理采样，只输出光效：
 *   - 中心完全透明（真实背景透出，磨砂由 ArkUI backgroundEffect 提供）
 *   - 边缘菲涅尔光 + 边缘流光（液体玻璃边缘亮线）
 *   - 触摸高光跟随（手指划过时局部泛光）
 *   - 点击涟漪（扩散光环）
 * 输出 alpha 只在光效处 > 0，标准 alpha 混合由 Surface 合成器处理。
 */

#ifndef VT_GLASS_SHADER_H
#define VT_GLASS_SHADER_H

// ---- Vertex Shader ----
const char* VT_VERTEX_SHADER = R"(
#version 300 es
layout(location = 0) in vec2 aPosition;
out vec2 vPos;
void main() {
    vPos = aPosition;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
)";

// ---- Fragment Shader（光效层）----
const char* VT_FRAGMENT_SHADER = R"(
#version 300 es
precision mediump float;
precision highp float uTime;

in vec2 vPos;                 // clip space [-1,1]
uniform float uTime;
uniform vec2 uTouchPos;       // [0,1]，(-1,-1) = 无触摸
uniform float uIntensity;     // 整体光效强度
uniform float uWaveSpeed;
uniform float uAspect;        // width/height，用于圆形涟漪矫正

// 涟漪池：xy=中心[0,1] z=当前半径 w=强度（0=空槽哨兵）
#define MAX_RIPPLES 16
uniform mediump vec4 uRipples[MAX_RIPPLES];

out vec4 fragColor;

void main() {
    // clip [-1,1] -> uv [0,1]
    vec2 uv = vPos * 0.5 + 0.5;

    // 0=中心 1≈边缘中点（轻微椭圆畸变可接受，卡片多为横条）
    float dist = distance(uv, vec2(0.5)) * 2.0;

    // 1. 边缘菲涅尔光：边缘亮、中心无，呼吸感微调
    float fresnel = clamp(1.0 - dist, 0.0, 1.0);
    fresnel = pow(fresnel, 6.0);                  // 高次幂 -> 只在边缘可见
    float breathe = 0.85 + 0.15 * sin(uTime * 0.8);
    float edgeGlow = fresnel * breathe * uIntensity;

    // 2. 边缘流光：沿边缘缓慢流动的亮带（角度+时间行波）
    float angle = atan(uv.y - 0.5, (uv.x - 0.5) * uAspect + 0.0001);
    float flow = sin(angle * 3.0 + uTime * uWaveSpeed * 2.0) * 0.5 + 0.5;
    float edgeFlow = fresnel * flow * 0.5 * uIntensity;

    // 3. 触摸高光：手指位置附近柔光，轻微脉动
    float touch = 0.0;
    if (uTouchPos.x >= 0.0) {
        vec2 td = uv - uTouchPos;
        td.x *= uAspect;
        float tdist = length(td);
        touch = smoothstep(0.25, 0.0, tdist) * 0.35 * uIntensity;
        touch *= 0.8 + 0.2 * sin(uTime * 2.0);
    }

    // 4. 涟漪光环：高斯环带扩散 + 环后拖尾微光
    float rippleGlow = 0.0;
    for (int i = 0; i < MAX_RIPPLES; i++) {
        vec4 rp = uRipples[i];
        if (rp.w <= 0.0) continue;
        vec2 rd = uv - rp.xy;
        rd.x *= uAspect;
        float rdist = length(rd);
        float band = rdist - rp.z;
        float ring = exp(-band * band * 220.0);
        float trail = smoothstep(rp.z, rp.z - 0.12, rdist) * 0.3;
        rippleGlow += (ring + trail * ring) * rp.w * uIntensity;
    }

    // 5. 合成：冷调玻璃光（偏蓝白）+ 触摸暖光，中心 alpha=0 全透
    vec3 lightColor = vec3(0.75, 0.85, 1.0);
    vec3 warmColor = vec3(1.0, 0.97, 0.90);
    vec3 col = lightColor * (edgeGlow + edgeFlow + rippleGlow)
             + warmColor * touch;
    float alpha = clamp(edgeGlow + edgeFlow + rippleGlow + touch, 0.0, 1.0);

    // 最外圈渐隐，避免圆角外溢出亮线（配 borderRadius+clip）
    float outer = smoothstep(1.02, 0.96, dist);
    col *= outer;
    alpha *= outer;

    fragColor = vec4(col, alpha);
}
)";

#endif // VT_GLASS_SHADER_H
