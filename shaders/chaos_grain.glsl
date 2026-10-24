// Chaos Grain — Aliens-style temporally-incoherent film grain.
//
// Every pixel is independently hashed against the current frame seed (mpv's
// `random` uniform). No spatial correlation, no temporal correlation.
// Frame N and frame N+1 share zero pattern — the eye integrates them to a
// smooth, organic surface rather than any structured artifact.
//
// Distribution: three uniform samples averaged → triangular/Gaussian-like.
// Extreme pixel values become rare (unlike raw white noise which is salt-and-pepper).
// Most pixels get a small nudge; only a few get a large one. That is film grain.
//
// cg_strength: grain amplitude. 0.04 = subtle, 0.08 = visible, 0.14 = heavy Aliens.
//              Start around 0.06 and adjust by feel.

//!PARAM cg_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.03

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Chaos grain (Aliens-style)

uint wang_hash(uint s) {
    s ^= s >> 16u; s *= 0x45d9f3bu;
    s ^= s >> 16u; s *= 0x45d9f3bu;
    s ^= s >> 16u;
    return s;
}

float hash_f(uint s) {
    return float(wang_hash(s)) / 4294967295.0; // [0, 1]
}

vec4 hook() {
    vec4  src  = HOOKED_tex(HOOKED_pos);
    ivec2 px   = ivec2(floor(HOOKED_pos * HOOKED_size));

    // Per-frame seed: different every frame, same for all pixels this frame.
    uint frame_seed = wang_hash(floatBitsToUint(random));

    // Per-pixel base hash.
    uint h = wang_hash(uint(px.x))
           ^ wang_hash(uint(px.y) + 2747636419u)
           ^ wang_hash(frame_seed);

    // Three independent samples averaged → Gaussian-like distribution.
    // Extreme values are rare. Most pixels get a small nudge.
    float n = (hash_f(h) + hash_f(h + 1u) + hash_f(h + 2u)) / 3.0;
    float noise = n * 2.0 - 1.0; // [-1, 1], concentrated near 0

    // Protect deep blacks (avoid clipping asymmetry → salt-pepper on black).
    // Protect bright highlights (avoid clipping the tops).
    float luma    = dot(src.rgb, vec3(0.2627, 0.6780, 0.0593));
    float envelope = smoothstep(0.0, 0.10, luma)           // fade in from black
                   * (1.0 - smoothstep(0.80, 1.0, luma));  // fade out into white

    vec3 out_rgb = src.rgb + vec3(noise * cg_strength * envelope);
    return vec4(clamp(out_rgb, 0.0, 1.0), src.a);
}