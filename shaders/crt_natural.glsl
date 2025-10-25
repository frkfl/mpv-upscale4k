//!PARAM scan_amp
//!TYPE float
0.28

//!PARAM scan_curve
//!TYPE float
1.35

//!PARAM bloom_strength
//!TYPE float
0.06

//!PARAM bloom_radius
//!TYPE float
1.25

//!PARAM mask_strength
//!TYPE float
0.18

//!PARAM mask_soft
//!TYPE float
0.25

//!PARAM chroma_preserve
//!TYPE float
0.85

//!PARAM sat_boost
//!TYPE float
1.08

//!PARAM black_lift
//!TYPE float
0.012

//!PARAM gamma_in
//!TYPE float
2.20

//!PARAM gamma_out
//!TYPE float
2.20

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Natural CRT (scanline + triad mask) with color-preserving compensation

// Luma (BT.709)
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// sRGB<->linear helpers
vec3 toLinear(vec3 c, float g) { return pow(max(c, 0.0), vec3(g > 0.0 ? 1.0 / g : 1.0)); }
vec3 toGamma (vec3 c, float g) { return pow(max(c, 0.0), vec3(g > 0.0 ? g : 1.0)); }

// Smooth step for triad softening
float smoothMaskStep(float x, float w) {
    float a = clamp((x - 0.5 * (1.0 - w)) / max(w, 1e-6), 0.0, 1.0);
    return a * a * (3.0 - 2.0 * a);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // 1) Linearize and measure original luma
    vec3 rgb = HOOKED_tex(uv).rgb;
    vec3 lin = toLinear(rgb, gamma_in);
    float Y0 = max(1e-6, luma(lin));

    // 2) Scanlines via sin^2 profile
    float yPix  = uv.y * HOOKED_size.y;
    float fracY = fract(yPix);
    float wave  = sin(3.14159265 * fracY);
    float scanW = 1.0 - scan_amp * pow(wave * wave, max(scan_curve, 1.0));
    vec3 sl_col = lin * scanW;

    // 3) Local bloom (5-tap, linear domain)
    float r = bloom_radius;
    vec3 s1 = toLinear(HOOKED_tex(uv + vec2( px.x * r, 0.0)).rgb, gamma_in);
    vec3 s2 = toLinear(HOOKED_tex(uv + vec2(-px.x * r, 0.0)).rgb, gamma_in);
    vec3 s3 = toLinear(HOOKED_tex(uv + vec2(0.0,  px.y * r)).rgb, gamma_in);
    vec3 s4 = toLinear(HOOKED_tex(uv + vec2(0.0, -px.y * r)).rgb, gamma_in);
    vec3 avg = (sl_col * 2.0 + s1 + s2 + s3 + s4) / 6.0;
    vec3 withBloom = mix(sl_col, avg, clamp(bloom_strength, 0.0, 1.0));

    // 4) RGB triad mask with soft transitions
    float triad = mod(floor(uv.x * HOOKED_size.x), 3.0);
    vec3 m = (triad < 0.5)      ? vec3(1.0, 0.65, 0.65)
           : (triad < 1.5)      ? vec3(0.65, 1.0, 0.65)
                                 : vec3(0.65, 0.65, 1.0);
    float fx = fract(uv.x * HOOKED_size.x * (1.0 / 3.0));
    float soft = mix(1.0, smoothMaskStep(fx, clamp(mask_soft, 0.0, 1.0)), clamp(mask_soft, 0.0, 1.0));
    vec3 mask = mix(vec3(1.0), m, clamp(mask_strength, 0.0, 1.0) * soft);
    vec3 masked = withBloom * mask;

    // 5) Luma compensation to preserve colorfulness
    float Y1 = max(1e-6, luma(masked));
    float gain = mix(1.0, Y0 / Y1, clamp(chroma_preserve, 0.0, 1.0));
    vec3 comp = masked * gain;

    // 6) Gentle saturation boost (luma-preserving)
    float Yc = luma(comp);
    vec3 satCol = mix(vec3(Yc), comp, sat_boost);

    // 7) Slight black lift to avoid crush
    satCol = max(satCol, vec3(black_lift));

    // 8) Back to display gamma
    vec3 outc = toGamma(satCol, gamma_out);
    return vec4(clamp(outc, 0.0, 1.0), 1.0);
}
