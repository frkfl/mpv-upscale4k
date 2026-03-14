//!PARAM mc_radius
//!TYPE float
1.0

//!PARAM mc_amount
//!TYPE float
0.12

//!PARAM mc_threshold
//!TYPE float
0.02

//!PARAM mc_gamma_in
//!TYPE float
2.20

//!PARAM mc_gamma_out
//!TYPE float
2.20

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Micro-Contrast addition

// Compute luma (BT.709)
float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Convert to linear space
vec3 toLin(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? 1.0 / g : 1.0));
}

// Convert back to gamma space
vec3 toGam(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? g : 1.0));
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    float r = mc_radius;

    // Fetch current pixel in linear light
    vec3 c = toLin(HOOKED_tex(uv).rgb, mc_gamma_in);

    // 3×3 blur neighborhood
    vec3 n = toLin(HOOKED_tex(uv + vec2(0.0, -px.y * r)).rgb, mc_gamma_in);
    vec3 s = toLin(HOOKED_tex(uv + vec2(0.0, px.y * r)).rgb, mc_gamma_in);
    vec3 e = toLin(HOOKED_tex(uv + vec2( px.x * r, 0.0)).rgb, mc_gamma_in);
    vec3 w = toLin(HOOKED_tex(uv + vec2(-px.x * r, 0.0)).rgb, mc_gamma_in);
    vec3 ne = toLin(HOOKED_tex(uv + vec2( px.x * r, -px.y * r)).rgb, mc_gamma_in);
    vec3 nw = toLin(HOOKED_tex(uv + vec2(-px.x * r, -px.y * r)).rgb, mc_gamma_in);
    vec3 se = toLin(HOOKED_tex(uv + vec2( px.x * r, px.y * r)).rgb, mc_gamma_in);
    vec3 sw = toLin(HOOKED_tex(uv + vec2(-px.x * r, px.y * r)).rgb, mc_gamma_in);

    // Simple average blur
    vec3 blur = (c + n + s + e + w + ne + nw + se + sw) * (1.0 / 9.0);

    // Local tone contrast signal
    vec3 diff = c - blur;

    // Gating to avoid noise amplification
    float gate = smoothstep(mc_threshold, 3.0 * mc_threshold, abs(luma(diff)));

    // Apply contrast boost
    vec3 boosted = c + diff * (mc_amount * gate);

    // Reapply output gamma
    return vec4(toGam(boosted, mc_gamma_out), 1.0);
}