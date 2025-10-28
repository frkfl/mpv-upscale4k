// mpv user shader: hardware-agnostic mild cleanup (wide-gamut safe)

//!PARAM luma_radius
//!TYPE float
1.0
//!PARAM sigma_s
//!TYPE float
1.25
//!PARAM sigma_r
//!TYPE float
0.06
//!PARAM chroma_radius
//!TYPE float
1.0
//!PARAM chroma_strength
//!TYPE float
0.6
//!PARAM deblock_strength
//!TYPE float
0.2
//!PARAM grain_strength
//!TYPE float
0.004
//!PARAM seed
//!TYPE float
1337.0
//!HOOK LUMA
//!BIND HOOKED
//!SAVE luma_denoised
//!DESC Luma bilateral denoise

float gauss(float x, float sigma) {
    return exp(-0.5 * (x * x) / max(sigma * sigma, 1e-8));
}

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;
    float center = HOOKED_tex(HOOKED_pos).r;

    int R = int(luma_radius + 0.5);
    float s_s = sigma_s;
    float s_r = sigma_r;

    float wsum = 0.0;
    float vsum = 0.0;

    for (int j = -R; j <= R; ++j) {
        for (int i = -R; i <= R; ++i) {
            vec2 off = vec2(float(i), float(j)) * px;
            float v = HOOKED_tex(HOOKED_pos + off).r;
            float ds = length(vec2(float(i), float(j)));
            float wr = gauss(v - center, s_r);
            float ws = gauss(ds, s_s);
            float w  = wr * ws;
            wsum += w;
            vsum += v * w;
        }
    }

    float outL = (wsum > 0.0) ? (vsum / wsum) : center;
    return vec4(outL, 0.0, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND HOOKED
//!SAVE chroma_clean
//!DESC Chroma gentle low-pass (edge-friendly)

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;
    int R = int(chroma_radius + 0.5);

    vec3 sum = vec3(0.0);
    float wsum = 0.0;

    for (int j = -R; j <= R; ++j) {
        for (int i = -R; i <= R; ++i) {
            vec2 off = vec2(float(i), float(j)) * px;
            float dsq = dot(vec2(float(i), float(j)), vec2(float(i), float(j)));
            float w = 1.0 / (1.0 + dsq);
            vec3 c = HOOKED_tex(HOOKED_pos + off).rgb;
            sum  += c * w;
            wsum += w;
        }
    }

    vec3 blur = sum / max(wsum, 1e-6);
    vec3 orig = HOOKED_tex(HOOKED_pos).rgb;
    vec3 outC = mix(orig, blur, clamp(chroma_strength, 0.0, 1.0));
    return vec4(outC, 1.0);
}

//!HOOK LUMA
//!BIND HOOKED
//!BIND luma_denoised
//!SAVE luma_deblock
//!DESC Luma deblocking guided by edge metric

float edgeMetric(vec2 pos, vec2 px) {
    vec2 pix = pos / px;
    float gx = step(0.5, abs(fract(pix.x * 0.125) - 0.5)); // ~8 px
    float gy = step(0.5, abs(fract(pix.y * 0.125) - 0.5));

    float l = HOOKED_tex(pos - vec2(px.x, 0.0)).r;
    float r = HOOKED_tex(pos + vec2(px.x, 0.0)).r;
    float u = HOOKED_tex(pos - vec2(0.0, px.y)).r;
    float d = HOOKED_tex(pos + vec2(0.0, px.y)).r;

    float mh = abs(r - l);
    float mv = abs(d - u);

    float wx = 1.0 - gx;
    float wy = 1.0 - gy;
    return max(mh * wx, mv * wy);
}

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;

    float den = luma_denoised_tex(HOOKED_pos).r;
    float org = HOOKED_tex(HOOKED_pos).r;

    float m = edgeMetric(HOOKED_pos, px);
    float k = clamp(deblock_strength * (m * 4.0), 0.0, 0.8);

    float outL = mix(org, den, k);
    return vec4(outL, 0.0, 0.0, 1.0);
}

//!HOOK MAIN
//!BIND HOOKED
//!BIND luma_deblock
//!BIND chroma_clean
//!DESC Recombine cleaned luma/chroma + add mild grain

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;
    vec2 res = HOOKED_size.xy;

    vec4 base = HOOKED_tex(uv);
    const vec3 kY = vec3(0.2627, 0.6780, 0.0593); // BT.2020 luma

    float Y_clean = luma_deblock_tex(uv).r;
    vec3  C_clean = chroma_clean_tex(uv).rgb;

    vec3 dir   = normalize(max(C_clean, 1e-6));
    float Ydir = max(dot(dir, kY), 1e-6);
    float scale = Y_clean / Ydir;
    vec3 rgb = dir * scale;

    rgb = mix(base.rgb, rgb, 0.6);

    if (grain_strength > 0.0) {
        vec2 ip = uv * res + vec2(seed, seed * 0.5);
        float g = (hash(ip) - 0.5) * 2.0;
        rgb += g * grain_strength;
    }

    return vec4(clamp(rgb, 0.0, 1.0), base.a);
}
