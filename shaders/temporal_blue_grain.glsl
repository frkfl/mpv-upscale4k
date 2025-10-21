//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Temporal blue-noise grain (filmic, luma-biased)
//!PARAM float strength = 0.03      // 0.02–0.05 typical
//!PARAM float chroma = 0.5         // 0 = luma-only, 1 = full RGB
//!PARAM float grain_size = 1.0     // 1.0=fine, 2.0–3.0=coarser

// Simple frame-evolving blue-noise using hash; stable enough for 24 fps,
// avoids static speckle and "FMV" look.

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec3 blueNoise(vec2 uv, float t, float gsize) {
    // warp uv a bit for blue-ish spectrum and animate slowly
    vec2 u = uv * (160.0 / gsize);
    float n  = hash13(vec3(floor(u), t * 0.61));
    float n2 = hash13(vec3(floor(u + vec2(17.7, 9.3)), t * 0.37));
    float n3 = hash13(vec3(floor(u + vec2(3.1, 27.5)), t * 0.19));
    // combine & high-pass
    float v = (n + 0.7 * n2 + 0.5 * n3) / 2.2;
    v = v * 2.0 - 1.0; // [-1,1]
    return vec3(v);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec4 src = HOOKED_tex(uv);

    // luma weighting so grain is stronger on midtones, weaker on shadows/highlights
    float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    float tone = smoothstep(0.08, 0.92, luma);              // avoid deep blacks/whites
    float roll = mix(0.75, 1.00, smoothstep(0.2, 0.7, luma)); // midtone bias

    // time seed from frame count (libplacebo provides HOOKED_tex_ts if available; fallback to iTime-like)
    float t = float(int(HOOKED_size.z)) + 0.123; // z carries frame idx in many builds
    vec3 gn = blueNoise(uv, t, grain_size) * strength * roll;

    // mix luma/chroma
    float gY = dot(gn, vec3(0.299, 0.587, 0.114));
    vec3 add = mix(vec3(gY), gn, chroma);

    // apply gently
    vec3 outc = src.rgb + add;
    return vec4(outc, src.a);
}
