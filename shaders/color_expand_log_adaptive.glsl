//!PARAM black_level
//!TYPE float
0.062561
//!PARAM white_level
//!TYPE float
0.918367
//!PARAM log_strength
//!TYPE float
12.0
//!PARAM exponent_weight
//!TYPE float
0.85
//!PARAM adapt_floor
//!TYPE float
0.68
//!PARAM adapt_ceiling
//!TYPE float
1.18
//!PARAM adapt_pivot
//!TYPE float
0.18
//!PARAM adapt_contrast
//!TYPE float
0.60
//!PARAM chroma_preserve
//!TYPE float
0.15
//!PARAM soft_knee
//!TYPE float
0.02

//!HOOK MAIN
//!BIND HOOKED
//!DESC Adaptive log color expansion (BT.2020 limited→full)

// Constants
const float EPS = 1e-5;                         // small epsilon
const vec3  W2020 = vec3(0.2627,0.6780,0.0593); // BT.2020 luma

// Log mapping normalized to 0..1
float map_log01(float v, float k) {             // v∈[0,1], k>0
    return log(1.0 + k * clamp(v,0.0,1.0)) / log(1.0 + k);
}

// Soft knee highlight roll-off
vec3 soft_clip(vec3 v, float knee) {
    if (knee <= 0.0) return clamp(v,0.0,1.0);   // no knee
    vec3 base = clamp(v,0.0,1.0 + knee);       // allow headroom
    vec3 over = max(base - 1.0, 0.0);          // amount over 1
    vec3 rolled = over / (1.0 + over / knee);  // reciprocal knee
    return clamp(base - over + rolled, 0.0, 1.0);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;                      // pixel coord
    vec4 src = HOOKED_tex(uv);                 // source texel
    vec3 rgb = src.rgb;                        // source rgb

    // Normalize limited-range to 0..1
    float range = max(white_level - black_level, EPS);
    vec3 norm = clamp((rgb - black_level) / range, 0.0, 1.0);

    // Luminance in log domain
    float luma = dot(norm, W2020);             // 2020 luma
    float log_luma = map_log01(luma, max(log_strength, EPS));

    // Luminance-dependent exponent
    float expo_lin = mix(adapt_floor, adapt_ceiling, log_luma);
    float expo = mix(1.0, expo_lin, clamp(exponent_weight, 0.0, 1.0));

    // Shape with exponent
    vec3 shaped = pow(max(norm, vec3(EPS)), vec3(expo));

    // Adaptive gain around pivot in log space
    float pivot_log = map_log01(clamp(adapt_pivot,0.0,1.0), max(log_strength, EPS));
    float gain = exp2((log_luma - pivot_log) * adapt_contrast);

    // Match target luminance
    float shaped_luma = max(dot(shaped, W2020), EPS);
    float target_luma = clamp(shaped_luma * gain, 0.0, 1.0);
    float lum_scale = target_luma / shaped_luma;
    vec3 adapted = shaped * lum_scale;

    // Blend some original chroma
    adapted = mix(adapted, norm, clamp(chroma_preserve, 0.0, 1.0));

    // Apply soft knee and output
    vec3 out_rgb = soft_clip(adapted, max(soft_knee, 0.0));
    return vec4(out_rgb, src.a);               // full-range out
}
