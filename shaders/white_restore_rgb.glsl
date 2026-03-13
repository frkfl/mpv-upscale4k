//!PARAM strength
//!TYPE float
0.3

//!PARAM threshold
//!TYPE float
0.5

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] White restoration

vec4 hook() {
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;

    // Max channel = highlight proxy that works in any domain.
    float P = max(c.r, max(c.g, c.b));

    // Threshold meaning:
    // Lower threshold  -> only near-white affected
    // Higher threshold -> more pixels affected
    // threshold = 100 -> basically whole picture considered “white”
    float t = max(threshold, 0.0);
    float gate = smoothstep(t, 1.0, P);  // gate grows as pixels approach “white”

    // Neutral reference (the "white" that chroma deviates from)
    vec3 neutral = vec3(P);              // grey of same intensity as pixel

    // This reflects hue direction, even if extremely tiny.
    vec3 chroma = c - neutral;

    // Apply chroma expansion
    // scale = 1 + strength*gate;
    float s = max(strength, 0.0);
    float scale = 1.0 + s * gate;

    vec3 outc = neutral + chroma * scale;
    outc = clamp(outc, 0.0, 1.0);

    return vec4(outc, 1.0);
}
