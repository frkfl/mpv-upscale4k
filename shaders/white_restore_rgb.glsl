// White restoration - amplifies residual chroma on near-white pixels.
// wrr_strength:  amplification factor
// wrr_threshold: brightness floor (pixels below this are not touched)
// wrr_sat_limit: chroma ceiling - pixels already saturated are left alone
//   0.05 = very tight (only near-neutral touched), 0.20 = allow faded colors through

//!PARAM wrr_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.3

//!PARAM wrr_threshold
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM wrr_sat_limit
//!TYPE float
//!MINIMUM 0.01
//!MAXIMUM 0.5
0.10

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] White restoration

vec4 hook() {
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;

    float P = max(c.r, max(c.g, c.b));

    vec3 neutral     = vec3(P);
    vec3 chroma      = c - neutral;
    float chroma_mag = max(abs(chroma.r), max(abs(chroma.g), abs(chroma.b)));

    float bright_gate = smoothstep(wrr_threshold, 1.0, P);
    float sat_gate    = 1.0 - smoothstep(wrr_sat_limit * 0.5, wrr_sat_limit, chroma_mag);
    float gate        = bright_gate * sat_gate;
    float scale       = 1.0 + wrr_strength * gate;

    vec3 outc = clamp(neutral + chroma * scale, 0.0, 1.0);
    return vec4(outc, 1.0);
}
