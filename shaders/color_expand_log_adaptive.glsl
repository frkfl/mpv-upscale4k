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
//!DESC Adaptive log color expansion (highlight-safe, no white crush)

const float EPS = 1e-5;
const vec3  W2020 = vec3(0.2627,0.6780,0.0593);

// Log mapping
float map_log01(float v, float k) {
    v = clamp(v,0.0,1.0);
    return log(1.0 + k * v) / log(1.0 + k);
}

// Soft knee highlight roll-off
vec3 soft_clip(vec3 v, float knee) {
    if (knee <= 0.0) return clamp(v,0.0,1.0);
    vec3 base = clamp(v,0.0,1.0 + knee);
    vec3 over = max(base - 1.0, 0.0);
    vec3 rolled = over / (1.0 + over / knee);
    return clamp(base - over + rolled, 0.0, 1.0);
}

vec4 hook() {
    vec3 rgb = HOOKED_tex(HOOKED_pos).rgb;

    // Normalize limited range
    float range = max(white_level - black_level, EPS);
    vec3 norm = clamp((rgb - black_level) / range, 0.0, 1.0);

    // Luma and log-luma
    float luma = dot(norm, W2020);
    float log_luma = map_log01(luma, max(log_strength, EPS));

    // Luminance-driven exponent
    float expo_lin = mix(adapt_floor, adapt_ceiling, log_luma);
    float expo = mix(1.0, expo_lin, clamp(exponent_weight,0.0,1.0));

    // Exponent shaping
    vec3 shaped = pow(max(norm, vec3(EPS)), vec3(expo));

    // Adaptive gain around pivot
    float pivot_log = map_log01(clamp(adapt_pivot,0.0,1.0), max(log_strength,EPS));
    float gain = exp2((log_luma - pivot_log) * adapt_contrast);

    //--------------------------------------------------------------
    // *** FIX 1: prevent runaway gain from blowing out everything ***
    // Limit gain so that shaped_luma * gain stays inside soft-knee
    //--------------------------------------------------------------
    gain = min(gain, 1.0 + soft_knee * 3.0);

    // Luminance target WITHOUT clipping (soft knee later)
    float shaped_luma = max(dot(shaped, W2020), EPS);
    float target_luma = shaped_luma * gain;

    //--------------------------------------------------------------
    // *** FIX 2: apply soft knee BEFORE scaling RGB ***
    //--------------------------------------------------------------
    target_luma = soft_clip(vec3(target_luma), max(soft_knee,0.0)).r;

    // Scale RGB by safe luminance ratio
    float lum_scale = target_luma / shaped_luma;
    vec3 adapted = shaped * lum_scale;

    //--------------------------------------------------------------
    // *** FIX 3: prevent per-channel blowout before soft-knee ***
    //--------------------------------------------------------------
    adapted = min(adapted, vec3(1.0 + soft_knee));

    // Chromaticity preservation
    adapted = mix(adapted, norm, clamp(chroma_preserve,0.0,1.0));

    // Final soft knee
    vec3 out_rgb = soft_clip(adapted, max(soft_knee,0.0));

    return vec4(out_rgb, 1.0);
}
