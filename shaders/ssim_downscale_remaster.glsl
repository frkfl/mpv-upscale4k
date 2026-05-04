// SSIM Downscale Remaster v2
// Variance-preserving 4K->720p collapse + Lanczos-3 re-upscale.
//
// Unlike ssim_remaster.glsl (Mitchell-only, clipped kernel), this:
//   - Uses the full Mitchell kernel support (+-2*scale taps, not just +-2)
//   - Computes true source variance from E[X^2] - E[X]^2
//   - Applies a per-channel gain map to restore structural detail
//     that the downscale filter suppressed
//
// Pass 1 (720p): Mitchell full-kernel mean              -> SSIM2_MEAN
// Pass 2 (720p): Mitchell full-kernel mean of src^2     -> SSIM2_SQ
// Pass 3 (720p): variance-preserving SSIM gain          -> SSIM2_OUT
// Pass 4 (full): Lanczos-3 upscale from SSIM2_OUT       -> output

//!PARAM ssim2_gain_max
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
3.0

//!PARAM ssim2_eps
//!TYPE float
//!MINIMUM 0.001
//!MAXIMUM 0.05
0.015

//!PARAM ssim2_crop
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.10
0.03

//!HOOK MAIN
//!BIND HOOKED
//!SAVE SSIM2_MEAN
//!WIDTH 1280
//!HEIGHT 720
//!DESC [SSIM2] Mitchell downscale mean

float mitch(float x) {
    const float B = 1.0/3.0, C = 1.0/3.0;
    x = abs(x);
    if (x < 1.0)
        return ((12.0-9.0*B-6.0*C)*x*x*x + (-18.0+12.0*B+6.0*C)*x*x + (6.0-2.0*B)) / 6.0;
    else if (x < 2.0)
        return ((-B-6.0*C)*x*x*x + (6.0*B+30.0*C)*x*x + (-12.0*B-48.0*C)*x + (8.0*B+24.0*C)) / 6.0;
    return 0.0;
}

vec4 hook() {
    // Map output pixel [0,1] into the cropped region [crop, 1-crop] of source.
    // This removes the CRT barrel border before downscaling.
    vec2 src_pos = ssim2_crop + HOOKED_pos * (1.0 - 2.0 * ssim2_crop);
    // scale: source pixels per output pixel, accounting for crop
    vec2 scale   = HOOKED_size * (1.0 - 2.0 * ssim2_crop) / vec2(1280.0, 720.0);
    vec2 src     = src_pos * HOOKED_size;

    vec3  col = vec3(0.0);
    float W   = 0.0;

    // Loop +-6 covers full Mitchell support for 3x downscale (4K->720p).
    // mitch() returns 0 outside [-2,2] so over-sampling is harmless.
    for (int y = -6; y <= 6; y++) {
        for (int x = -6; x <= 6; x++) {
            vec2 spos = (src + vec2(float(x), float(y)) + 0.5) * HOOKED_pt;
            float w   = mitch(float(x) / scale.x) * mitch(float(y) / scale.y);
            col += HOOKED_tex(spos).rgb * w;
            W   += w;
        }
    }
    return vec4(col / max(W, 1e-6), 1.0);
}

//!HOOK MAIN
//!BIND HOOKED
//!SAVE SSIM2_SQ
//!WIDTH 1280
//!HEIGHT 720
//!DESC [SSIM2] Mitchell downscale mean of squares

float mitch(float x) {
    const float B = 1.0/3.0, C = 1.0/3.0;
    x = abs(x);
    if (x < 1.0)
        return ((12.0-9.0*B-6.0*C)*x*x*x + (-18.0+12.0*B+6.0*C)*x*x + (6.0-2.0*B)) / 6.0;
    else if (x < 2.0)
        return ((-B-6.0*C)*x*x*x + (6.0*B+30.0*C)*x*x + (-12.0*B-48.0*C)*x + (8.0*B+24.0*C)) / 6.0;
    return 0.0;
}

vec4 hook() {
    vec2 src_pos = ssim2_crop + HOOKED_pos * (1.0 - 2.0 * ssim2_crop);
    vec2 scale   = HOOKED_size * (1.0 - 2.0 * ssim2_crop) / vec2(1280.0, 720.0);
    vec2 src     = src_pos * HOOKED_size;

    vec3  sq = vec3(0.0);
    float W  = 0.0;

    for (int y = -6; y <= 6; y++) {
        for (int x = -6; x <= 6; x++) {
            vec2 spos = (src + vec2(float(x), float(y)) + 0.5) * HOOKED_pt;
            vec3 s    = HOOKED_tex(spos).rgb;
            float w   = mitch(float(x) / scale.x) * mitch(float(y) / scale.y);
            sq += s * s * w;
            W  += w;
        }
    }
    return vec4(sq / max(W, 1e-6), 1.0);
}

//!HOOK MAIN
//!BIND HOOKED
//!BIND SSIM2_MEAN
//!BIND SSIM2_SQ
//!SAVE SSIM2_OUT
//!WIDTH 1280
//!HEIGHT 720
//!DESC [SSIM2] Variance-preserving gain

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt  = SSIM2_MEAN_pt;

    vec3 mu  = SSIM2_MEAN_tex(pos).rgb;
    vec3 msq = SSIM2_SQ_tex(pos).rgb;

    // Source std dev: sqrt(E[X^2] - E[X]^2)
    vec3 sigma_src = sqrt(max(msq - mu * mu, vec3(0.0)));

    // Local mean of the downscaled image (3x3 box)
    vec3 lmu = vec3(0.0);
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
            lmu += SSIM2_MEAN_tex(pos + vec2(float(dx), float(dy)) * pt).rgb;
    lmu /= 9.0;

    // Local variance of the downscaled image (3x3 box)
    vec3 lvar = vec3(0.0);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec3 d = SSIM2_MEAN_tex(pos + vec2(float(dx), float(dy)) * pt).rgb - lmu;
            lvar += d * d;
        }
    }
    vec3 sigma_low = sqrt(lvar / 9.0);

    // Gain: only boost, never reduce (lower bound = 1.0)
    vec3 gain = clamp(
        sigma_src / max(sigma_low, vec3(ssim2_eps)),
        vec3(1.0),
        vec3(ssim2_gain_max)
    );

    // Apply to AC component (deviation from local mean)
    vec3 out_col = clamp(lmu + gain * (mu - lmu), vec3(0.0), vec3(1.0));
    return vec4(out_col, 1.0);
}

//!HOOK MAIN
//!BIND HOOKED
//!BIND SSIM2_OUT
//!DESC [SSIM2] Lanczos-3 upscale to output

float sinc(float x) {
    if (abs(x) < 1e-5) return 1.0;
    x *= 3.14159265;
    return sin(x) / x;
}

float lanczos3(float x) {
    if (abs(x) >= 3.0) return 0.0;
    return sinc(x) * sinc(x / 3.0);
}

vec4 hook() {
    // Map output pixel into SSIM2_OUT (720p) texel space
    vec2 src = HOOKED_pos * SSIM2_OUT_size - 0.5;
    vec2 f   = fract(src);
    vec2 c   = floor(src);

    vec3  col = vec3(0.0);
    float W   = 0.0;

    for (int y = -2; y <= 3; y++) {
        for (int x = -2; x <= 3; x++) {
            vec2 tap = c + vec2(float(x), float(y));
            vec2 tc  = (tap + 0.5) * SSIM2_OUT_pt;
            float w  = lanczos3(float(x) - f.x) * lanczos3(float(y) - f.y);
            col += SSIM2_OUT_tex(tc).rgb * w;
            W   += w;
        }
    }
    return vec4(clamp(col / max(W, 1e-6), 0.0, 1.0), 1.0);
}
