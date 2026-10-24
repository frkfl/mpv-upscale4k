//!PARAM gb_sigma
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 6.0
0.01

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Gaussian blur

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    if (gb_sigma <= 0.0) return HOOKED_tex(uv);

    float inv2s2 = 0.5 / (gb_sigma * gb_sigma);
    vec3  col = vec3(0.0);
    float W   = 0.0;

    for (int y = -4; y <= 4; y++) {
        for (int x = -4; x <= 4; x++) {
            float w = exp(-float(x*x + y*y) * inv2s2);
            col += HOOKED_tex(uv + vec2(float(x), float(y)) * px).rgb * w;
            W   += w;
        }
    }

    return vec4(col / W, HOOKED_tex(uv).a);
}
