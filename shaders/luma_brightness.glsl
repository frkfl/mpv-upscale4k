//!PARAM lb_strength
//!TYPE float
//!MINIMUM -1000.0
//!MAXIMUM 1000.0
0.0

//!PARAM lb_shoulder
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 4.0
1.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Luma brightness

// Reinhard Shoulder
vec3 reinhard_exposure(vec3 c, float k, float shoulder) {
    vec3 num = c * k;
    vec3 den = 1.0 + c * (k - 1.0) * shoulder;
    return num / den;
}

vec4 hook() {
    vec4 src = HOOKED_tex(HOOKED_pos);

    // Exposure scale
    float k = 1.0 + lb_strength / 100.0;

    // Prevent inversion if strength < -100
    k = max(k, 0.0);

    vec3 outc = reinhard_exposure(src.rgb, k, lb_shoulder);

    // Final safety clamp
    outc = clamp(outc, 0.0, 1.0);

    return vec4(outc, src.a);
}