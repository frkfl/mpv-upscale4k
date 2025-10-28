//!DESC Normalization Front-End v2 (Deterministic / linear / pre-upscale)
//!HOOK MAIN
//!BIND HOOKED

// ---- Parameters (strict format) ----
//!PARAM th_low
//!TYPE float
0.035
//!PARAM th_high
//!TYPE float
0.12
//!PARAM shift_px
//!TYPE float
0.75
//!PARAM k_strength
//!TYPE float
0.50
//!PARAM alpha_yfb
//!TYPE float
0.10
//!PARAM beta_cfb
//!TYPE float
0.02
//!PARAM blur_sigma
//!TYPE float
1.20
//!PARAM protect_gate
//!TYPE float
0.70
//!PARAM shadow_thresh
//!TYPE float
0.05
//!PARAM knee_gain
//!TYPE float
1.0
//!PARAM ema_low
//!TYPE float
0.15
//!PARAM ema_high
//!TYPE float
0.60
//!PARAM motion_thr
//!TYPE float
0.03
//!PARAM s_chroma_protect
//!TYPE float
0.70
//!PARAM e_ref
//!TYPE float
0.08
//!PARAM max_desat
//!TYPE float
0.30

// ---- Constants ----
const float EPS  = 1e-6;
const vec3  W601 = vec3(0.299, 0.587, 0.114); // Rec.601 luma (linear)

// RGB<->YCbCr 601 (full-range, linear)
vec3 rgb_to_ycbcr601(vec3 rgb) {
    float Y  = dot(rgb, W601);
    float Cb = (rgb.b - Y) / 1.772 + 0.5;
    float Cr = (rgb.r - Y) / 1.402 + 0.5;
    return vec3(Y, Cb, Cr);
}
vec3 ycbcr601_to_rgb(vec3 ycc) {
    float Y  = ycc.x;
    float Cb = ycc.y - 0.5;
    float Cr = ycc.z - 0.5;
    float R  = Y + 1.402 * Cr;
    float B  = Y + 1.772 * Cb;
    float G  = (Y - 0.114 * B - 0.299 * R) / 0.587;
    return vec3(R, G, B);
}

// Gaussian 5-tap weights (separable)
vec3 gauss5(float s) {
    s = max(s, 1e-4);
    float w0 = 1.0;
    float w1 = exp(-0.5 / (s*s));
    float w2 = exp(-2.0 / (s*s));
    float n  = 2.0*(w1 + w2) + w0;
    return vec3(w0, w1, w2) / n;
}

vec3 blur5_rgb(vec3 center, vec2 dir, vec2 pt, float s) {
    vec3 w = gauss5(s);
    vec2 d1 = dir * pt;
    vec2 d2 = 2.0 * d1;
    vec3 c1 = 0.5*(HOOKED_tex(HOOKED_pos + d1).rgb + HOOKED_tex(HOOKED_pos - d1).rgb);
    vec3 c2 = 0.5*(HOOKED_tex(HOOKED_pos + d2).rgb + HOOKED_tex(HOOKED_pos - d2).rgb);
    return w.x*center + w.y*c1 + w.z*c2;
}

float blur5_y(float Yc, vec2 dir, vec2 pt, float s) {
    vec3 w = gauss5(s);
    float y1p = dot(HOOKED_tex(HOOKED_pos + dir*pt).rgb, W601);
    float y1m = dot(HOOKED_tex(HOOKED_pos - dir*pt).rgb, W601);
    float y2p = dot(HOOKED_tex(HOOKED_pos + dir*pt*2.0).rgb, W601);
    float y2m = dot(HOOKED_tex(HOOKED_pos - dir*pt*2.0).rgb, W601);
    float c1 = 0.5*(y1p + y1m);
    float c2 = 0.5*(y2p + y2m);
    return w.x*Yc + w.y*c1 + w.z*c2;
}

float soft_knee_log(float y, float gain) {
    gain = max(gain, 1.0);
    return log(1.0 + gain * clamp(y, 0.0, 1.0)) / log(1.0 + gain);
}

vec4 hook() {
    // Samples from HOOKED_tex are **already linear** under gpu-next; don't re-linearize.
    vec3 rgb = HOOKED_tex(HOOKED_pos).rgb;

    // YCbCr (linear)
    vec3 ycc = rgb_to_ycbcr601(rgb);
    float Y  = ycc.x;
    float Cb = ycc.y;
    float Cr = ycc.z;

    vec2 pt = HOOKED_pt;

    // ---- Local metrics ----
    float Yl = dot(HOOKED_tex(HOOKED_pos - vec2(pt.x, 0)).rgb, W601);
    float Yr = dot(HOOKED_tex(HOOKED_pos + vec2(pt.x, 0)).rgb, W601);
    float Gy = 0.5*(Yr - Yl);

    vec3 rgb_l = HOOKED_tex(HOOKED_pos - vec2(pt.x, 0)).rgb;
    vec3 rgb_r = HOOKED_tex(HOOKED_pos + vec2(pt.x, 0)).rgb;
    float Cb_l = rgb_to_ycbcr601(rgb_l).y;
    float Cr_l = rgb_to_ycbcr601(rgb_l).z;
    float Cb_r = rgb_to_ycbcr601(rgb_r).y;
    float Cr_r = rgb_to_ycbcr601(rgb_r).z;

    float dC_sum = (Cb - Cb_l) + (Cr - Cr_l);
    float eC = abs(Cb - Cb_l) + abs(Cr - Cr_l) +
               abs(Cb_r - Cb) + abs(Cr_r - Cr) + EPS;

    float S_raw = smoothstep(th_low, th_high, abs(dC_sum) / eC);
    float sgn   = sign(Gy * dC_sum); // -1,0,+1

    // ---- Protection + chroma-energy adaptive scaling ----
    float Yh = blur5_y(Y, vec2(1,0), pt, 1.0);
    float Yv = blur5_y(Y, vec2(0,1), pt, 1.0);
    float Ylp = 0.5*(Yh + Yv);
    float HF  = abs(Y - Ylp);
    float Protect = clamp(HF * (1.0 - S_raw) * protect_gate, 0.0, 1.0);

    float e_local = (abs(Cb - Cb_l) + abs(Cr - Cr_l) + abs(Cb_r - Cb) + abs(Cr_r - Cr)) * 0.5;
    float damp = clamp(1.0 - s_chroma_protect * (1.0 - clamp(e_local / max(e_ref, EPS), 0.0, 1.0)), 0.0, 1.0);

    // Extra suppression in flat mid/high-luma areas to protect skin/whites
    float flat_gate = 1.0 - smoothstep(0.02, 0.12, HF);
    float lum_gate  = smoothstep(0.10, 0.85, Y); // less correction in mid/high luma if not edgey
    float S = clamp(S_raw * (1.0 - Protect) * damp * mix(1.0, 0.6, flat_gate*lum_gate), 0.0, 1.0);

    // ---- Frequency split on chroma ----
    vec3 blur_h = blur5_rgb(rgb, vec2(1,0), pt, blur_sigma);
    vec3 blur_2 = blur5_rgb(blur_h, vec2(0,1), pt, blur_sigma);
    vec2 C_LF   = rgb_to_ycbcr601(blur_2).yz;
    vec2 C_HF   = vec2(Cb,Cr) - C_LF;

    // ---- Directional re-alignment (LF) ----
    float dx = shift_px * pt.x * sgn;
    vec2 C_LF_shift = rgb_to_ycbcr601(HOOKED_tex(HOOKED_pos - vec2(dx, 0)).rgb).yz;
    vec2 C_corr = mix(C_LF, C_LF_shift, k_strength * S);

    // One-sided smoothing opposite bleed
    float sdir = -sgn;
    vec2 C1 = rgb_to_ycbcr601(HOOKED_tex(HOOKED_pos + vec2(sdir*pt.x, 0)).rgb).yz;
    vec2 C2 = rgb_to_ycbcr601(HOOKED_tex(HOOKED_pos + vec2(2.0*sdir*pt.x, 0)).rgb).yz;
    vec2 C_dir = (C_corr + C1 + C2) / 3.0;
    C_corr = mix(C_corr, C_dir, 0.5 * S * (1.0 - Protect));

    // Recombine
    vec2 CbCr = C_corr + C_HF;

    // ---- Desaturation guard ----
    vec2 c0 = vec2(Cb - 0.5, Cr - 0.5);
    vec2 c1 = vec2(CbCr.x - 0.5, CbCr.y - 0.5);
    float r0 = length(c0);
    float r1 = length(c1);
    float rmin = (1.0 - clamp(max_desat, 0.0, 1.0)) * r0;
    if (r1 < rmin && r0 > 0.0) {
        c1 *= rmin / max(r1, EPS);
    }
    Cb = c1.x + 0.5;
    Cr = c1.y + 0.5;

    // ---- Y<->C re-balance (soft) ----
    float fb = S * sgn;
    float Yp = Y + alpha_yfb * fb * dC_sum;
    float Cscale = 1.0 - beta_cfb * fb * Gy;
    Cb *= Cscale;  Cr *= Cscale;

    // ---- Tone gate + soft-knee (knee off by default) ----
    float gate = smoothstep(0.0, shadow_thresh, Yp);
    Cb = mix(0.5, Cb, gate);
    Cr = mix(0.5, Cr, gate);
    float Yk = (knee_gain <= 1.0001) ? clamp(Yp, 0.0, 1.0) : soft_knee_log(clamp(Yp, 0.0, 1.0), knee_gain);

    // ---- Temporal luma stabilization (deterministic, no storage) ----
    float motion = step(motion_thr, abs(Y - Ylp));
    float a = mix(ema_low, ema_high, motion);
    float Yt = mix(Yk, mix(Yk, Ylp, 0.25), a * 0.2);

    // Back to RGB (stay linear; gpu-next handles presentation)
    vec3 ycc_out = vec3(clamp(Yt, 0.0, 1.0), clamp(Cb, 0.0, 1.0), clamp(Cr, 0.0, 1.0));
    vec3 rgb_out = ycbcr601_to_rgb(ycc_out);
    rgb_out = clamp(rgb_out, -0.025, 1.025);
    rgb_out = clamp(rgb_out * 0.98 + 0.01, 0.0, 1.0);

    return vec4(rgb_out, HOOKED_tex(HOOKED_pos).a);
}
