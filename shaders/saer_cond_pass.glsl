//!PARAM clamp_hard
//!TYPE float
0.015
//!PARAM r_soft_base
//!TYPE float
0.003
//!PARAM r_soft_min
//!TYPE float
0.0015
//!PARAM r_soft_max
//!TYPE float
0.006
//!PARAM mrel_lo
//!TYPE float
0.015
//!PARAM mrel_hi
//!TYPE float
0.050
//!PARAM mad_lo
//!TYPE float
0.004
//!PARAM mad_hi
//!TYPE float
0.020
//!PARAM motion_lo
//!TYPE float
0.010
//!PARAM motion_hi
//!TYPE float
0.050
//!PARAM ema_alpha
//!TYPE float
0.30
//!PARAM enable_debug
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV1
//!BIND PREV2
//!DESC SAER v1 — Structure-Adaptive Edge Reinforcement (relative + variance + temporal E)

// -------- constants --------
const float EPS  = 1e-6;
const vec3  W601 = vec3(0.299, 0.587, 0.114);

// --- small Gaussian blur of Y (3x3) ---
float blur_small_Y(vec2 uv, vec2 pt) {
    float k0=0.27901, k1=0.44198, k2=0.27901;
    float acc = 0.0;
    acc += k0*k0 * dot(linearize(HOOKED_tex(uv + vec2(-pt.x,-pt.y))).rgb, W601);
    acc += k1*k0 * dot(linearize(HOOKED_tex(uv + vec2( 0.0 , -pt.y))).rgb, W601);
    acc += k2*k0 * dot(linearize(HOOKED_tex(uv + vec2( pt.x, -pt.y))).rgb, W601);
    acc += k0*k1 * dot(linearize(HOOKED_tex(uv + vec2(-pt.x, 0.0))).rgb, W601);
    acc += k1*k1 * dot(linearize(HOOKED_tex(uv)).rgb, W601);
    acc += k2*k1 * dot(linearize(HOOKED_tex(uv + vec2( pt.x, 0.0))).rgb, W601);
    acc += k0*k2 * dot(linearize(HOOKED_tex(uv + vec2(-pt.x, pt.y))).rgb, W601);
    acc += k1*k2 * dot(linearize(HOOKED_tex(uv + vec2( 0.0 , pt.y))).rgb, W601);
    acc += k2*k2 * dot(linearize(HOOKED_tex(uv + vec2( pt.x, pt.y))).rgb, W601);
    return acc;
}

// --- larger blur (5x5 separable) for halo guard ---
float blur_large_Y(vec2 uv, vec2 pt) {
    float k0=0.27901, k1=0.44198, k2=0.27901;
    float acc = 0.0;
    for (int yy=-2; yy<=2; yy++) {
        for (int xx=-2; xx<=2; xx++) {
            int ax = abs(xx); ax = ax>2?2:ax;
            int ay = abs(yy); ay = ay>2?2:ay;
            float wx = (ax==0? k0 : (ax==1? k1 : k2));
            float wy = (ay==0? k0 : (ay==1? k1 : k2));
            vec2 offs = vec2(float(xx)*pt.x, float(yy)*pt.y);
            acc += wx*wy * dot(linearize(HOOKED_tex(uv + offs)).rgb, W601);
        }
    }
    return acc;
}

// --- bilateral Y with spatial sigma (px) & small range factor ---
float bilateral_Y(vec2 uv, vec2 pt, float sigma_px, float range_k) {
    int r = int(clamp(floor(sigma_px + 0.5), 1.0, 12.0));
    float Yc = dot(linearize(HOOKED_tex(uv)).rgb, W601);
    float s2 = max(sigma_px*sigma_px, 1e-4);
    float acc = 0.0, wsum = 0.0;
    for (int y=-r; y<=r; y++) {
        for (int x=-r; x<=r; x++) {
            vec2 offs = vec2(float(x)*pt.x, float(y)*pt.y);
            float Ys = dot(linearize(HOOKED_tex(uv + offs)).rgb, W601);
            float ds2 = float(x*x + y*y);
            float w_sp = exp(-ds2 / (2.0*s2));
            float w_rg = exp(-abs(Ys - Yc) / max(range_k, 1e-3));
            float w = w_sp * w_rg;
            acc += w * Ys;
            wsum += w;
        }
    }
    return (wsum > 0.0) ? acc / wsum : Yc;
}

// --- Sobel gradient on Y (magnitude & direction) ---
vec2 sobel_Y(vec2 uv, vec2 pt) {
    float a = dot(linearize(HOOKED_tex(uv + vec2(-pt.x, -pt.y))).rgb, W601);
    float b = dot(linearize(HOOKED_tex(uv + vec2( 0.0,  -pt.y))).rgb, W601);
    float c = dot(linearize(HOOKED_tex(uv + vec2( pt.x, -pt.y))).rgb, W601);
    float d = dot(linearize(HOOKED_tex(uv + vec2(-pt.x,  0.0))).rgb, W601);
    float e = dot(linearize(HOOKED_tex(uv)).rgb, W601);
    float f = dot(linearize(HOOKED_tex(uv + vec2( pt.x,  0.0))).rgb, W601);
    float g = dot(linearize(HOOKED_tex(uv + vec2(-pt.x,  pt.y))).rgb, W601);
    float h = dot(linearize(HOOKED_tex(uv + vec2( 0.0,   pt.y))).rgb, W601);
    float i = dot(linearize(HOOKED_tex(uv + vec2( pt.x,  pt.y))).rgb, W601);
    float gx = -a - 2.0*d - g + c + 2.0*f + i;
    float gy = -a - 2.0*b - c + g + 2.0*h + i;
    return vec2(gx, gy);
}

vec4 hook() {
    vec2  uv   = HOOKED_pos;
    vec2  pt   = HOOKED_pt;
    ivec2 ipix = ivec2(floor(HOOKED_pos * HOOKED_size));

    // Source (linear)
    vec3  rgb_lin = linearize(HOOKED_tex(uv)).rgb;
    float Y       = dot(rgb_lin, W601);

    // Motion gate from previous Y
    float Y_prev  = (frame == 0) ? Y : imageLoad(PREV1, ipix).r;
    float dY      = abs(Y - Y_prev);
    float w_stat  = 1.0 - smoothstep(motion_lo, motion_hi, dY); // static→1, motion→0

    // Local mean & relative contrast (ΔY / Ȳ)
    float Y_mean  = bilateral_Y(uv, pt, 2.0, 0.10);
    float denom   = max(Y_mean, 0.10);                      // stabilize in darks
    float dY_rel  = abs(Y - Y_mean) / denom;
    float e_rel   = smoothstep(mrel_lo, mrel_hi, dY_rel);   // recognition-band gate

    // Noise suppression via local absolute deviation (MAD-like)
    float Y_local = bilateral_Y(uv, pt, 1.5, 0.05);         // gentle local model
    float mad     = abs(Y - Y_local);
    float e_n     = 1.0 - smoothstep(mad_lo, mad_hi, mad);  // 1 at low-noise, 0 at speckle

    // Block-edge helper using analytical derivatives (strong on DV / MPEG blocks)
    float b_mag   = max(abs(dFdx(Y)), abs(dFdy(Y)));
    float e_blk   = smoothstep(0.002, 0.012, b_mag);

    // Non-maximum suppression along gradient direction
    vec2  gY      = sobel_Y(uv, pt);
    float m       = length(gY);
    vec2  dir     = normalize(gY + vec2(EPS, EPS));
    float m_p     = length(sobel_Y(uv + dir * pt, pt));
    float m_m     = length(sobel_Y(uv - dir * pt, pt));
    float nms     = float(m >= m_p && m >= m_m);

    // Instantaneous edge eligibility (no temporal yet)
    float E0      = clamp(max(e_rel, e_blk) * e_n * nms * w_stat, 0.0, 1.0);

    // Temporal EMA on E (stability over frames)
    float E_prev  = (frame == 0) ? E0 : imageLoad(PREV2, ipix).r;
    float a       = clamp(ema_alpha, 0.0, 1.0);
    float E       = mix(E_prev, E0, a);

    // --- Softening (inside ambiguous zones) ---
    float H       = HOOKED_size.y;
    float r_min_px= r_soft_min * H;
    float r_max_px= r_soft_max * H;
    float sigma_soft = mix(r_max_px, r_min_px, E); // E↑ → less diffusion
    float Y_soft  = bilateral_Y(uv, pt, max(sigma_soft, 1.0), 0.03);
    float mix_soft= pow(max(1.0 - E, 0.0), 0.7) * w_stat;
    float Yp      = mix(Y, Y_soft, clamp(mix_soft, 0.0, 1.0));

    // --- Hard-edge finish (deconvolution-like, clamp + halo guard) ---
    float Y_blur_small = blur_small_Y(uv, pt);
    float h            = sqrt(E);
    float k            = 0.6;
    float delta        = clamp(k * (Yp - Y_blur_small), -clamp_hard, clamp_hard);

    float Y_blur_large = blur_large_Y(uv, pt);
    float before       = Yp - Y_blur_large;
    float after        = (Yp + h * delta) - Y_blur_large;
    float flip         = float(before * after < 0.0);
    float h_guard      = mix(h, 0.5 * h, flip);

    float Yh           = Yp + h_guard * delta * w_stat;

    // Recompose by luma-preserving scale (RGB space unchanged)
    float Y_src  = max(dot(rgb_lin, W601), EPS);
    float scale  = clamp(Yh / Y_src, 0.0, 16.0);
    vec3  rgb_out_lin = rgb_lin * scale;

    // Persist
    imageStore(PREV1, ipix, vec4(Y, 0.0, 0.0, 1.0)); // previous Y
    imageStore(PREV2, ipix, vec4(E, 0.0, 0.0, 1.0)); // EMA(E)

    // Debug: SAER trace = {E, h, σ_soft_norm}
    if (enable_debug > 0.5) {
        float sigma_norm = clamp((sigma_soft - r_min_px) / max(r_max_px - r_min_px, EPS), 0.0, 1.0);
        // non-treated (very low E and low mix_soft) → black
        float treated = float(E > 0.02 || mix_soft > 0.02 || h > 0.02);
        vec3 trace = treated > 0.5 ? vec3(E, h, sigma_norm) : vec3(0.0);
        return vec4(trace, 1.0);
    }

    vec3 out_nl = delinearize(vec4(clamp(rgb_out_lin, vec3(0.0), vec3(1e6)), 1.0)).rgb;
    return vec4(out_nl, HOOKED_tex(uv).a);
}

// --- persistent images ---
//!TEXTURE PREV1
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE
//!TEXTURE PREV2
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE
