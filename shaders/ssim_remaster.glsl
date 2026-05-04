// SSIM Remaster — two-pass proof of concept
// Pass 1: Mitchell-Netravali downscale to 720p intermediate
// Pass 2: Lanczos-3 upscale back to output resolution
//
// Purpose: collapse the carefully upscaled 4K to a clean 720p,
// then re-upscale with sharper teeth. The intermediate averaging
// removes upscaling softness and grain inconsistencies; the
// Lanczos re-upscale finds real edges in a cleaner signal.

// ─── Pass 1: Mitchell-Netravali downscale ────────────────────────────────────

//!HOOK MAIN
//!BIND HOOKED
//!SAVE SSIM_720
//!WIDTH 1280
//!HEIGHT 720
//!DESC [Remaster] Mitchell downscale to 720p

// Mitchell-Netravali B=1/3, C=1/3 — balanced between ringing and blur
float mitchell(float x) {
    float B = 1.0/3.0;
    float C = 1.0/3.0;
    x = abs(x);
    if (x < 1.0)
        return ((12.0-9.0*B-6.0*C)*x*x*x + (-18.0+12.0*B+6.0*C)*x*x + (6.0-2.0*B)) / 6.0;
    else if (x < 2.0)
        return ((-B-6.0*C)*x*x*x + (6.0*B+30.0*C)*x*x + (-12.0*B-48.0*C)*x + (8.0*B+24.0*C)) / 6.0;
    return 0.0;
}

vec4 hook() {
    // Scale factor from output (720p) back to source (MAIN)
    vec2 scale = HOOKED_size / vec2(1280.0, 720.0);
    vec2 src   = HOOKED_pos * HOOKED_size;

    vec3  col = vec3(0.0);
    float W   = 0.0;

    // 4-tap Mitchell in each dimension (support radius 2)
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 spos   = (src + offset + 0.5) * HOOKED_pt;
            float wx    = mitchell(float(x) / scale.x);
            float wy    = mitchell(float(y) / scale.y);
            float w     = wx * wy;
            col += HOOKED_tex(spos).rgb * w;
            W   += w;
        }
    }

    return vec4(col / W, 1.0);
}

// ─── Pass 2: Lanczos-3 upscale ───────────────────────────────────────────────

//!HOOK MAIN
//!BIND HOOKED
//!BIND SSIM_720
//!DESC [Remaster] Lanczos-3 upscale to output

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
    // Map output pixel to SSIM_720 space
    vec2 src = HOOKED_pos * SSIM_720_size - 0.5;
    vec2 f   = fract(src);
    vec2 c   = floor(src);

    vec3  col = vec3(0.0);
    float W   = 0.0;

    for (int y = -2; y <= 3; y++) {
        for (int x = -2; x <= 3; x++) {
            vec2 tap  = c + vec2(float(x), float(y));
            vec2 tc   = (tap + 0.5) * SSIM_720_pt;
            float wx  = lanczos3(float(x) - f.x);
            float wy  = lanczos3(float(y) - f.y);
            float w   = wx * wy;
            col += SSIM_720_tex(tc).rgb * w;
            W   += w;
        }
    }

    return vec4(clamp(col / W, 0.0, 1.0), 1.0);
}
