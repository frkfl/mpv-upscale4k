//!PARAM strength
//!TYPE float
1.0

//!PARAM threshold
//!TYPE float
0.5

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC White-restore (raw RGB chroma expansion, domain-agnostic)

// As always: no tonemaps, no color spaces, no luma models.
// Pure RGB math that ALWAYS produces visible output when parameters are large.

vec4 hook() {
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;

    // --- 1. Intensity proxy -----------------------------------------
    // Max channel = highlight proxy that works in ANY domain.
    float P = max(c.r, max(c.g, c.b));

    // Threshold meaning:
    // Lower threshold  -> only near-white affected
    // Higher threshold -> more pixels affected
    // threshold = 100 -> basically whole picture considered “white”
    float t = max(threshold, 0.0);
    float gate = smoothstep(t, 1.0, P);  // gate grows as pixels approach “white”

    // --- 2. Neutral reference (the "white" that chroma deviates from) ----
    vec3 neutral = vec3(P);              // grey of same intensity as pixel

    // --- 3. Chroma vector -------------------------------------------
    // This ALWAYS reflects hue direction, even if extremely tiny.
    vec3 chroma = c - neutral;

    // --- 4. Apply chroma expansion -----------------------------------
    // scale = 1 + strength*gate ; guarantees EXPLOSION with large strength
    float s = max(strength, 0.0);
    float scale = 1.0 + s * gate;

    vec3 outc = neutral + chroma * scale;

    // Clamp (only at very end — ensures explosion still visible)
    outc = clamp(outc, 0.0, 1.0);

    return vec4(outc, 1.0);
}
