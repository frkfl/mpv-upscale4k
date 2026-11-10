// gb_sigma is σ² (variance), not σ itself.
// inv2s2 = 0.5/σ² = 0.5/gb_sigma — no squaring needed in the formula.
// gb_sigma=1 → σ=1, gb_sigma=2 → σ≈1.41, gb_sigma=4 → σ=2, gb_sigma=5 → σ≈2.24.
// Equal parameter steps feel more uniform than linear-σ did (1→2 was a large jump).
// At max=5, the ±4 kernel captures ~92% of the Gaussian mass — no visible truncation.
//!PARAM gb_sigma
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 5.0
0.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Gaussian blur

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    if (gb_sigma <= 0.0) return HOOKED_tex(uv);

    float inv2s2 = 0.5 / gb_sigma;
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
