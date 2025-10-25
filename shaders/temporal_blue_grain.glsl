//!PARAM strength
//!TYPE float
0.03

//!PARAM chroma
//!TYPE float
0.5

//!PARAM grain_size
//!TYPE float
1.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Temporal blue-noise grain (filmic, luma-biased)

// Pseudo blue-noise-ish hash
float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// Evolving blue noise: seed changes per frame via PREV
vec3 blueNoise(vec2 uv, float seed, float gsize) {
    vec2 u = uv * (160.0 / max(gsize, 1e-3)); // scale with grain size
    float n1 = hash13(vec3(floor(u), seed * 0.61));
    float n2 = hash13(vec3(floor(u + vec2(17.7, 9.3)), seed * 0.37));
    float n3 = hash13(vec3(floor(u + vec2(3.1, 27.5)), seed * 0.19));
    float v = (n1 + 0.7 * n2 + 0.5 * n3) / 2.2;
    v = v * 2.0 - 1.0; // [-1, 1]
    return vec3(v);
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;
    vec4 src = HOOKED_tex(uv);
    vec3 prv = PREV_tex(uv).rgb;

    // Luma shaping: stronger on midtones, less on deep shadows/highlights
    float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    float roll = mix(0.75, 1.0, smoothstep(0.2, 0.7, luma)); // midtone bias

    // Temporal seed from previous frame: stable but changes frame-to-frame
    float seed = dot(prv, vec3(0.3183, 0.1736, 0.4081)) * 4096.0;

    // Generate grain
    vec3 gn = blueNoise(uv, seed, grain_size) * strength * roll;

    // Mix luma/chroma grain
    float gY = dot(gn, vec3(0.299, 0.587, 0.114));
    vec3 add = mix(vec3(gY), gn, chroma);

    // Apply
    vec3 outc = src.rgb + add;
    return vec4(outc, src.a);
}
