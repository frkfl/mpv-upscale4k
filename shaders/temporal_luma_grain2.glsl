//!PARAM tlg2_grain
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 100.0
3.0

//!PARAM tlg2_motion
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.3

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV1
//!DESC [Custom] Temporal luma grain 2 (final pass, luma only)
//!SAVE MAIN

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float blueNoiseLuma(vec2 uv, float seed) {
    vec2 u = uv * 160.0;
    float n1 = hash13(vec3(floor(u), seed * 0.61));
    float n2 = hash13(vec3(floor(u + vec2(17.7, 9.3)), seed * 0.37));
    float n3 = hash13(vec3(floor(u + vec2(3.1, 27.5)), seed * 0.19));
    float v = (n1 + 0.7 * n2 + 0.5 * n3) / 2.2;
    return v * 2.0 - 1.0;
}

vec4 hook() {
    vec4 src = HOOKED_tex(HOOKED_pos);
    ivec2 pos = ivec2(HOOKED_pos * HOOKED_size);
    if (tlg2_grain <= 0.0) {
        imageStore(PREV1, pos, vec4(src.rgb, 1.0));
        return src;
    }
    vec4 hist = imageLoad(PREV1, pos);
    float seed = dot(hist.rgb, vec3(0.3183, 0.1736, 0.4081)) * 4096.0;
    seed += random * 4096.0 * tlg2_motion;
    float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));

    // Midtone-biased: no grain in deep blacks or bright highlights
    float roll = smoothstep(0.05, 0.25, luma) * (1.0 - smoothstep(0.75, 0.95, luma));

    float g = blueNoiseLuma(HOOKED_pos, seed) * roll * (tlg2_grain / 100.0) * 0.1;

    // Luma-only: add same value to all channels to avoid color shift
    vec3 outc = src.rgb + vec3(g);
    imageStore(PREV1, pos, vec4(outc, 1.0));
    return vec4(outc, src.a);
}

//!TEXTURE PREV1
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE
