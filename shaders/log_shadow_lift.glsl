//!PARAM shadow_start
//!TYPE float
0.02

//!PARAM shadow_end
//!TYPE float
0.18

//!PARAM shadow_gamma
//!TYPE float
0.65

//!PARAM strength
//!TYPE float
0.7

//!PARAM max_boost
//!TYPE float
2.0

//!PARAM color_blend
//!TYPE float
0.15

//!HOOK MAIN
//!BIND HOOKED
//!DESC Full-range shadow-band lift (local gamma curve, black-safe)

const float EPS  = 1e-6;
const vec3  W709 = vec3(0.2126, 0.7152, 0.0722);

vec4 hook()
{
    // Full-range linear RGB from mpv/libplacebo
    vec3 rgb = HOOKED_tex(HOOKED_pos).rgb;
    float Y  = dot(rgb, W709);  // luma in [0,1]

    // 1) Outside the shadow band: return input exactly
    if (Y <= shadow_start || Y >= shadow_end)
        return vec4(rgb, 1.0);

    // 2) Normalize Y into [0,1] inside the band
    float band = max(shadow_end - shadow_start, EPS);
    float t    = (Y - shadow_start) / band;   // 0..1

    // 3) Apply gamma-like curve on this local [0,1] range
    //    shadow_gamma < 1 lifts values in the middle, endpoints fixed
    float t_lift = pow(t, shadow_gamma);

    // Map back into original band; endpoints stay at shadow_start / shadow_end
    float Y_lift = shadow_start + t_lift * band;

    // 4) Blend between original and lifted luma
    float Y_target = mix(Y, Y_lift, clamp(strength, 0.0, 1.0));

    // 5) Turn luma change into a luma-preserving RGB gain
    float k = (Y > EPS) ? (Y_target / Y) : 1.0;

    // Only brighten; never darken. Cap how hard we can push.
    float k_max = 1.0 + max(max_boost, 0.0);
    k = clamp(k, 1.0, k_max);

    vec3 lifted = rgb * k;

    // 6) To avoid ugly color shifts on very strong lifts,
    //    blend a bit of the original RGB back when k is large.
    float strong = (k_max > 1.0) ? ((k - 1.0) / (k_max - 1.0)) : 0.0; // 0..1
    float c_mix  = color_blend * clamp(strong, 0.0, 1.0);

    vec3 out_rgb = mix(lifted, rgb, c_mix);

    // Clamp to full-range
    out_rgb = clamp(out_rgb, 0.0, 1.0);

    return vec4(out_rgb, 1.0);
}
