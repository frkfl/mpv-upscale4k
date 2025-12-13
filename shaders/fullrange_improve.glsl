//!PARAM strength
//!TYPE float
0.75

//!PARAM black_protect
//!TYPE float
0.015

//!PARAM pivot
//!TYPE float
0.45

//!PARAM gamma_low
//!TYPE float
0.80

//!PARAM gamma_high
//!TYPE float
1.10

//!PARAM fade_start
//!TYPE float
0.80

//!PARAM soft_knee
//!TYPE float
0.02

//!PARAM chroma_preserve
//!TYPE float
0.25

//!PARAM luma_r
//!TYPE float
0.2627

//!PARAM luma_g
//!TYPE float
0.6780

//!PARAM luma_b
//!TYPE float
0.0593

//!HOOK MAIN
//!BIND HOOKED
//!DESC Mild luma S-curve (full-range, black-safe, non-HDR)

const float EPS = 1e-6;

// Soft knee highlight roll-off (very gentle, just to avoid hard clipping)
vec3 soft_clip(vec3 v, float knee) {
    if (knee <= 0.0) return clamp(v, 0.0, 1.0);

    vec3 base   = clamp(v, 0.0, 1.0 + knee);
    vec3 over   = max(base - 1.0, 0.0);
    vec3 rolled = over / (1.0 + over / knee);

    return clamp(base - over + rolled, 0.0, 1.0);
}

float s_curve_luma(float L,
                   float black_protect,
                   float pivot,
                   float gamma_low,
                   float gamma_high,
                   float fade_start,
                   float strength)
{
    // Identity for extreme black protection
    if (L <= black_protect) {
        return L;
    }

    // Clamp core parameters
    pivot       = clamp(pivot, 0.05, 0.95);
    gamma_low   = max(gamma_low,  EPS);
    gamma_high  = max(gamma_high, EPS);
    fade_start  = clamp(fade_start, 0.0, 1.0);
    strength    = clamp(strength, 0.0, 1.0);

    // Base S-curve (two gammas around pivot)
    float L_curve;

    if (L <= pivot) {
        // Normalize [black_protect .. pivot] -> [0..1]
        float t = (L - black_protect) / max(pivot - black_protect, EPS);
        t = clamp(t, 0.0, 1.0);

        // Gamma < 1 lifts
        float t_c = pow(t, gamma_low);

        // Back to [black_protect .. pivot]
        L_curve = mix(black_protect, pivot, t_c);
    } else {
        // Normalize [pivot .. 1] -> [1..0] for symmetric gamma
        float u = (1.0 - L) / max(1.0 - pivot, EPS);
        u = clamp(u, 0.0, 1.0);

        // Gamma > 1 compresses
        float u_c = pow(u, gamma_high);

        // Back to [pivot .. 1]
        L_curve = 1.0 - u_c * (1.0 - pivot);
    }

    // Fade effect out near highlights so white & near-white stay stable
    float fade = 1.0 - smoothstep(fade_start, 1.0, L);  // 1 in mids, 0 at white
    float s_eff = strength * fade;

    // Final luma: mix between identity and curve
    return mix(L, L_curve, s_eff);
}

vec4 hook() {
    vec3 rgb  = HOOKED_tex(HOOKED_pos).rgb;
    vec3 W    = vec3(luma_r, luma_g, luma_b);

    // Current luma in mpv/libplacebo's full-range working space
    float L_in = clamp(dot(rgb, W), 0.0, 1.0);

    // Apply S-curve on luma only
    float L_out = s_curve_luma(
        L_in,
        black_protect,
        pivot,
        gamma_low,
        gamma_high,
        fade_start,
        strength
    );

    // If luma is ~0, keep black (avoid division noise)
    if (L_in <= EPS) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // Scale RGB to hit new luma (hue-preserving)
    float scale = L_out / L_in;
    vec3 rgb_toned = rgb * scale;

    // Very gentle highlight safety
    rgb_toned = soft_clip(rgb_toned, soft_knee);

    // Optional chroma preservation: pull back toward original RGB
    rgb_toned = mix(rgb_toned, rgb, clamp(chroma_preserve, 0.0, 1.0));

    // Final clamp to displayable range
    rgb_toned = clamp(rgb_toned, 0.0, 1.0);

    return vec4(rgb_toned, 1.0);
}
