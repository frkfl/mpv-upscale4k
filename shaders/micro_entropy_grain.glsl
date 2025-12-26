//!PARAM strength
//!TYPE float
0.009

//!PARAM chroma
//!TYPE float
0.20

//!PARAM grain_size
//!TYPE float
1.30

//!PARAM midtone_bias
//!TYPE float
0.75

//!PARAM animate
//!TYPE float
1.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Micro entropy grain for pre-downscale (luma-biased, blue-noise-ish, ultra low energy)

float luma2020(vec3 c) { return dot(c, vec3(0.2627, 0.6780, 0.0593)); }

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// blue-ish noise with mild high-pass tilt
float bluenoise(vec2 uv, float t, float gsize, vec2 pix) {
    float scale = 180.0 / max(gsize, 1e-3);
    vec2 s = (uv / pix) * scale; // pixel-space stable
    vec2 q = floor(s);

    float n1 = hash13(vec3(q, t * 0.37));
    float n2 = hash13(vec3(q + vec2(13.7, 7.9), t * 0.61));
    float n3 = hash13(vec3(q + vec2(3.1, 27.5), t * 0.19));

    float v = (n1 + 0.75 * n2 + 0.5 * n3) / 2.25;
    v = v * 2.0 - 1.0; // [-1, 1]

    // gentle high-pass tilt
    return v * (0.85 + 0.15 * n2);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec4 src = HOOKED_tex(uv);
    vec2 pix = 1.0 / HOOKED_size;

    float s = clamp(strength, 0.0, 0.05);
    float c = clamp(chroma, 0.0, 1.0);
    float mb = clamp(midtone_bias, 0.0, 1.0);

    // temporal seed (frame/random are provided by libplacebo)
    float t = (animate > 0.5) ? (float(frame) + random * 16.0) : 0.0;

    float Y = luma2020(src.rgb);

    // weight toward midtones
    float mid = smoothstep(0.08, 0.92, Y);
    float mid2 = smoothstep(0.20, 0.70, Y);
    mid *= mix(1.0, mid2, mb);

    float g = bluenoise(uv, t, grain_size, pix) * s * mid;

    // luma-only add
    vec3 addY = vec3(g);

    // tiny chroma decorrelation to avoid pure-gray "sparkle"
    float g2 = bluenoise(uv + vec2(17.0, 9.0) * pix, t + 1.7, grain_size, pix) * s * mid;
    float g3 = bluenoise(uv + vec2(3.0, 41.0) * pix, t + 3.1, grain_size, pix) * s * mid;
    vec3 addC = vec3(g, g2, g3);

    vec3 add = mix(addY, addC, c);

    vec3 outc = src.rgb + add;
    out_color = vec4(outc, 1.0);
    return out_color;
}
