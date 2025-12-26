//!PARAM pivot
//!TYPE float
0.3

//!PARAM strength
//!TYPE float
1.00

//!PARAM dark_lo
//!TYPE float
0.05

//!PARAM dark_hi
//!TYPE float
0.1

//!PARAM flat_lo
//!TYPE float
0.00

//!PARAM flat_hi
//!TYPE float
0.07

//!PARAM debug_mode
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC BT.2020 neighbor-aware shadow lift (or green if changed)

const float EPS   = 1e-6;
const vec3  W2020 = vec3(0.2627, 0.6780, 0.0593);

// integer texel offset sampler (mpv/libplacebo built-in)
vec3 sample_off(ivec2 o)
{
    return HOOKED_texOff(o).rgb;
}

vec4 hook()
{
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;  // full-range BT.2020 linear
    float Y = dot(c, W2020);

    // --- 1. Compute local mean luma (3x3) ---

    float Y00 = dot(sample_off(ivec2(-1,-1)), W2020);
    float Y10 = dot(sample_off(ivec2( 0,-1)), W2020);
    float Y20 = dot(sample_off(ivec2( 1,-1)), W2020);

    float Y01 = dot(sample_off(ivec2(-1, 0)), W2020);
    float Y11 = Y;
    float Y21 = dot(sample_off(ivec2( 1, 0)), W2020);

    float Y02 = dot(sample_off(ivec2(-1, 1)), W2020);
    float Y12 = dot(sample_off(ivec2( 0, 1)), W2020);
    float Y22 = dot(sample_off(ivec2( 1, 1)), W2020);

    float Y_mean = (Y00 + Y10 + Y20 +
                    Y01 + Y11 + Y21 +
                    Y02 + Y12 + Y22) / 9.0;

    // --- 2. Shadow mask: dark + flat ---

    // Darkness based on local mean
    float dark_mask = 1.0 - smoothstep(dark_lo, dark_hi, Y_mean);

    // Flatness based on |Y - mean|
    float dY = abs(Y - Y_mean);
    float flat_mask = 1.0 - smoothstep(flat_lo, flat_hi, dY);

    float shadow_mask = clamp(dark_mask * flat_mask, 0.0, 1.0);

    // --- 3. Luma lift inside shadow regions ---

    float Y_target = Y;

    if (shadow_mask > 0.0 && Y > EPS) {
        float w = clamp(strength * shadow_mask, 0.0, 1.0);
        Y_target = mix(Y, pivot, w);      // pull toward pivot
        Y_target = clamp(Y_target, 0.0, 1.0);
    }

    // Map luma change to a single color-preserving gain
    float gain = (Y > EPS) ? (Y_target / Y) : 1.0;
    vec3 outc  = clamp(c * gain, 0.0, 1.0);

    // --- 4. Debug: bright green where pixel changed ---

    if (debug_mode > 0.5) {
        bool changed = any(greaterThan(abs(outc - c), vec3(1e-4)));
        if (changed) {
            return vec4(0.0, 1.0, 0.0, 1.0);
        } else {
            return vec4(c, 1.0);
        }
    }

    return vec4(outc, 1.0);
}
