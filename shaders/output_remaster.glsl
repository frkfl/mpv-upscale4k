// Output Remaster
// Collapses the finished 4K OUTPUT to a 1080p sub-region, then re-upscales with Lanczos-4.
//
// The 1080p intermediate lives in the top-left quadrant of a 4K texture (UV < 0.5).
// No hook resizing needed: OUTPUT is not resizable, but the sub-region trick avoids it.
//
// Pass 1: 2×2 area average of 4K → 1080p stored in RMST[UV < 0.5]
// Pass 2: Lanczos-4 from the 1080p sub-region back to 4K OUTPUT

//!PARAM rmst_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!SAVE RMST
//!DESC [Remaster] 4K→1080p area downsample

vec4 hook() {
    vec2 uv = HOOKED_pos;
    if (uv.x >= 0.5 || uv.y >= 0.5) return vec4(0.0);

    // Map sub-region UV [0, 0.5) → full 4K source [0, 1)
    vec2 src = uv * 2.0;
    vec2 pt  = HOOKED_pt;

    // 2×2 area average: exact box filter for 2x downscale.
    // src lands at the boundary between the 4 input pixels,
    // so ±0.5*pt hits each pixel center exactly.
    return (HOOKED_tex(src + vec2(-0.5,  0.5) * pt)
          + HOOKED_tex(src + vec2( 0.5,  0.5) * pt)
          + HOOKED_tex(src + vec2(-0.5, -0.5) * pt)
          + HOOKED_tex(src + vec2( 0.5, -0.5) * pt)) * 0.25;
}

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND RMST
//!DESC [Remaster] Lanczos-4 1080p→4K

float lanczos2(float x) {
    const float a = 2.0;
    if (abs(x) < 1e-6) return 1.0;
    if (abs(x) >= a)   return 0.0;
    float px = 3.141592653589793 * x;
    return a * sin(px) * sin(px / a) / (px * px);
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;

    // pt2: UV spacing between adjacent 1080p pixels stored in RMST.
    // The 1080p pixels occupy RMST indices 0..1919 (x) and 0..1079 (y),
    // so their UV centers are spaced 2 * RMST_pt apart.
    vec2 pt2 = RMST_pt * 2.0;

    // Position of this 4K pixel in 1080p pixel coordinates.
    // For 4K pixel i at UV (i+0.5)/3840, p = (i+0.5)/2 — halfway between
    // 1080p pixels i/2 and i/2+1, consistent with a 2x upscale alignment.
    vec2 p   = uv / pt2;
    vec2 p0  = floor(p);
    vec2 fxy = p - p0;

    vec4  result  = vec4(0.0);
    float total_w = 0.0;

    for (int j = 0; j < 4; j++) {
        float wy = lanczos2(fxy.y + 1.0 - float(j));
        for (int i = 0; i < 4; i++) {
            float wx  = lanczos2(fxy.x + 1.0 - float(i));
            // UV of 1080p pixel at index (p0 + i-1, p0 + j-1) in RMST.
            // Pixel at integer index k has UV center (k + 0.5) * RMST_pt,
            // so tap = (p0 + (i-1) + 0.5) * RMST_pt = (p0 + i - 0.5) * RMST_pt.
            vec2  tap = (p0 + vec2(float(i) - 0.5, float(j) - 0.5)) * RMST_pt;
            float w   = wx * wy;
            result   += RMST_tex(tap) * w;
            total_w  += w;
        }
    }

    if (total_w <= 0.0) return HOOKED_tex(uv);
    result /= total_w;
    return vec4(mix(HOOKED_tex(uv).rgb, clamp(result.rgb, 0.0, 1.0), rmst_strength), 1.0);
}
