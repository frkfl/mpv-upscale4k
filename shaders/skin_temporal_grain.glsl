//!PARAM stg_grain
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 100.0
5.0

//!PARAM stg_motion
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM stg_skin_boost
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 5.0
1.5

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV1
//!DESC [Custom] Skin temporal luma grain
//!SAVE MAIN

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec3 blueNoise(vec2 uv, float seed) {
    vec2 u = uv * 160.0;
    float n1 = hash13(vec3(floor(u), seed * 0.61));
    float n2 = hash13(vec3(floor(u + vec2(17.7, 9.3)), seed * 0.37));
    float n3 = hash13(vec3(floor(u + vec2(3.1, 27.5)), seed * 0.19));
    float v = (n1 + 0.7 * n2 + 0.5 * n3) / 2.2;
    return vec3(v * 2.0 - 1.0);
}

vec4 hook() {
    vec4 src = HOOKED_tex(HOOKED_pos);
    ivec2 pos = ivec2(HOOKED_pos * HOOKED_size);
    if (stg_grain <= 0.0) {
        imageStore(PREV1, pos, vec4(src.rgb, 1.0));
        return src;
    }
    // Inline skin detection (self-contained, no external texture)
    // Computes probability [0,1] that pixel is skin
    // - Cb/Cr distance from skin centroid (BT.709-ish typical values)
    // - Luma gating to reduce false positives on dark/bright areas
    // Tune constants here if needed for your footage (e.g., widen ranges for tolerance)
    const float skinCb = 0.30;
    const float skinCr = 0.35;
    const float skinCbR = 0.10;
    const float skinCrR = 0.12;
    float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    float Cb = (src.b - luma) * 0.5 / 0.877 + 0.5;
    float Cr = (src.r - luma) * 0.5 / 0.701 + 0.5;
    float dCb = (Cb - skinCb) / skinCbR;
    float dCr = (Cr - skinCr) / skinCrR;
    float skin_prob = exp(-0.5 * (dCb * dCb + dCr * dCr));
    skin_prob *= smoothstep(0.05, 0.35, luma) * (1.0 - smoothstep(0.85, 1.0, luma));
    vec4 hist = imageLoad(PREV1, pos);
    float seed = dot(hist.rgb, vec3(0.3183, 0.1736, 0.4081)) * 4096.0;
    seed += random * 4096.0 * stg_motion;
    float roll = mix(0.75, 1.0, smoothstep(0.2, 0.7, luma));
    float s = pow(1.0, 1.5);
    vec3 gn = blueNoise(HOOKED_pos, seed) * s * roll;
    float gY = dot(gn, vec3(0.299, 0.587, 0.114));
    vec3 add_full = mix(vec3(gY), gn, 0.5);
    // Grain strength scaled by overall grain param + skin probability * boost
    // At stg_grain=100 and stg_skin_boost=5: heavy skin-focused destruction
    // At stg_skin_boost=1: uniform grain (no skin preference)
    float mix_factor = (stg_grain / 100.0) * (1.0 + skin_prob * (stg_skin_boost - 1.0)) * 0.1;
    vec3 add = add_full * mix_factor;
    vec3 outc = src.rgb + add;
    imageStore(PREV1, pos, vec4(outc, 1.0));
    return vec4(outc, src.a);
}

//!TEXTURE PREV1
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE