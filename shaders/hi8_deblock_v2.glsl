//!PARAM hd_threshold
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.2

//!PARAM hd_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.8

//!PARAM hd_size
//!TYPE int
//!MINIMUM 1
//!MAXIMUM 8
4

//!PARAM hd_debug_mask
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Hi8 vertical stripe deblocker - Blur across uncorrelated pixel boundaries

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

    // Get left and right neighbors
    vec3 c_left = sample_off(ivec2(-1, 0));
    vec3 c_right = sample_off(ivec2(1, 0));

    float Y_center = dot(c, W2020);
    float Y_left = dot(c_left, W2020);
    float Y_right = dot(c_right, W2020);

    // Detect uncorrelated boundary: left and right are very different from each other
    float boundary_strength = abs(Y_left - Y_right);

    // Apply blur if boundary strength exceeds threshold
    float apply_blur = step(hd_threshold, boundary_strength);

    // Horizontal blur across the boundary
    vec3 blur = vec3(0.0);
    float total_weight = 0.0;

    for (int dx = -hd_size; dx <= hd_size; dx++) {
        float dist = float(dx);
        float sigma = float(hd_size) * 0.5;
        float weight = exp(-dist * dist / (2.0 * sigma * sigma));
        blur += sample_off(ivec2(dx, 0)) * weight;
        total_weight += weight;
    }

    blur /= total_weight;

    vec3 out_rgb = mix(c, blur, hd_strength * apply_blur);

    if (hd_debug_mask > 0.5) {
        // Visualize detected boundaries: red tint
        vec3 tint = mix(out_rgb, vec3(1.0, 0.0, 0.0), apply_blur * 0.5);
        return vec4(tint, 1.0);
    }

    return vec4(out_rgb, 1.0);
}
