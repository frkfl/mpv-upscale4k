//!PARAM strength
//!TYPE float
0.7

//!PARAM var_low
//!TYPE float
0.0003

//!PARAM var_high
//!TYPE float
0.004

//!PARAM edge_thresh
//!TYPE float
0.05

//!PARAM debug_mask
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC Conditional deblock / degrid (BT.2020, low-variance only)

const vec3  W2020 = vec3(0.2627, 0.6780, 0.0593);
const float EPS   = 1e-6;

// Helper: sample with integer texel offset (mpv/libplacebo built-in)
vec3 sample_off(ivec2 o)
{
    return HOOKED_texOff(o).rgb;
}

vec4 hook()
{
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;   // full-range BT.2020 linear

    // --- 1. Gather 3x3 neighborhood ---

    vec3 c00 = sample_off(ivec2(-1,-1));
    vec3 c10 = sample_off(ivec2( 0,-1));
    vec3 c20 = sample_off(ivec2( 1,-1));

    vec3 c01 = sample_off(ivec2(-1, 0));
    vec3 c11 = c;
    vec3 c21 = sample_off(ivec2( 1, 0));

    vec3 c02 = sample_off(ivec2(-1, 1));
    vec3 c12 = sample_off(ivec2( 0, 1));
    vec3 c22 = sample_off(ivec2( 1, 1));

    float Y00 = dot(c00, W2020);
    float Y10 = dot(c10, W2020);
    float Y20 = dot(c20, W2020);
    float Y01 = dot(c01, W2020);
    float Y11 = dot(c11, W2020);
    float Y21 = dot(c21, W2020);
    float Y02 = dot(c02, W2020);
    float Y12 = dot(c12, W2020);
    float Y22 = dot(c22, W2020);

    // --- 2. Local variance & edge strength on BT.2020 luma ---

    float m1 = (Y00 + Y10 + Y20 +
                Y01 + Y11 + Y21 +
                Y02 + Y12 + Y22) / 9.0;

    float m2 = (Y00*Y00 + Y10*Y10 + Y20*Y20 +
                Y01*Y01 + Y11*Y11 + Y21*Y21 +
                Y02*Y02 + Y12*Y12 + Y22*Y22) / 9.0;

    float var = max(m2 - m1*m1, 0.0);

    // "flatness" mask: 1 in very flat areas, 0 in high-variance areas
    float flat_mask = 1.0 - smoothstep(var_low, var_high, var);

    // Edge strength: maximum absolute difference to 4-neighborhood
    float dY_left  = abs(Y11 - Y01);
    float dY_right = abs(Y11 - Y21);
    float dY_up    = abs(Y11 - Y10);
    float dY_down  = abs(Y11 - Y12);

    float max_grad = max(max(dY_left, dY_right), max(dY_up, dY_down));

    // Edge mask: 1 on strong edges, 0 in smooth areas
    float edge_mask = smoothstep(edge_thresh, edge_thresh * 2.0, max_grad);

    // Final smoothing weight: high in flat, non-edge regions
    float w = strength * flat_mask * (1.0 - edge_mask);
    w = clamp(w, 0.0, 1.0);

    // --- 3. 3x3 Gaussian blur of RGB (only used where w>0) ---

    // Weights: [1 2 1; 2 4 2; 1 2 1] / 16
    vec3 blur =
        (c00 + c20 + c02 + c22) * (1.0/16.0) +
        (c10 + c01 + c21 + c12) * (2.0/16.0) +
        (c11)                   * (4.0/16.0);

    vec3 out_rgb = mix(c, blur, w);

    if (debug_mask > 0.5) {
        // visualize where smoothing is applied:
        //  - pure original where w==0
        //  - greener where w is larger
        vec3 tint = mix(out_rgb, vec3(0.0, 1.0, 0.0), w);
        return vec4(tint, 1.0);
    }

    return vec4(out_rgb, 1.0);
}
