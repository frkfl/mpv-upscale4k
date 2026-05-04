// CRT perceptual texture
// Two effects that replace hard scanlines:
//
// 1. Vertical luma micro-contrast at scanline frequency
//    Samples neighbors at half-period distance (targets response peak at
//    frequency 1/period). Computes the Laplacian: how much this row stands
//    out from its scanline-scale neighborhood. Adds that difference back.
//    Flat areas: delta ~= 0, no change.
//    Edges and gradients: rows pull slightly apart from each other.
//    The brain infers vertical sub-resolution detail without seeing a stripe.
//    Average luma is preserved.
//
// 2. Chromatic phosphor triad micro-variation
//    Sine wave over triad_size pixels horizontally, half-pixel vertical stagger.
//    Mimics CRT shadow mask: R-G-B dot columns with slight horizontal offset.
//    R channel pushed warm (+) where B is pushed cool (-) and vice versa.
//    Gated by luma: no color shift in dark areas (authentic - dark CRT phosphor
//    emits nothing, no color). Integrates to zero over one triad period so
//    average color is unchanged.
//
// Place before SSIM downscale. The Mitchell kernel dissolves both modulations
// into the 720p intermediate. The SSIM variance gain sees smooth content-driven
// variance, not a periodic spike. Lanczos reintroduces as subpixel richness.

//!PARAM cpt_scan_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.20

//!PARAM cpt_scan_period
//!TYPE float
//!MINIMUM 2.0
//!MAXIMUM 12.0
4.0

//!PARAM cpt_chroma_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.05
0.015

//!PARAM cpt_triad_size
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 6.0
3.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [CRT] Phosphor texture

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec4 src = HOOKED_tex(pos);

    const vec3 W709 = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(src.rgb, W709);

    // --- 1. Vertical luma micro-contrast ---
    // Sampling at half-period targets the Laplacian peak at 1/period frequency.
    float half_p = (cpt_scan_period * 0.5) / HOOKED_size.y;

    float luma_above = dot(HOOKED_tex(pos + vec2(0.0,  half_p)).rgb, W709);
    float luma_below = dot(HOOKED_tex(pos + vec2(0.0, -half_p)).rgb, W709);

    // How much this row stands out from its scanline-scale neighborhood
    float delta = luma - 0.5 * (luma_above + luma_below);

    // Apply as uniform RGB shift: luma changes, hue does not
    vec3 col = src.rgb + vec3(cpt_scan_strength * delta);

    // --- 2. Chromatic phosphor triad micro-variation ---
    // Horizontal sine at triad period, vertical stagger at half pixel.
    // Produces a diagonal dot-triad pattern like a shadow mask CRT.
    float px = pos.x * HOOKED_size.x;
    float py = pos.y * HOOKED_size.y;

    float phase = (px + py * 0.5) / cpt_triad_size * 2.0 * 3.14159265;
    float shift = sin(phase);

    // Gate by luma: blacks contribute nothing, brights get full shift.
    // R and B pushed in opposite directions - G (luma carrier) unchanged.
    col.r += cpt_chroma_strength * shift * luma;
    col.b -= cpt_chroma_strength * shift * luma;

    return vec4(clamp(col, 0.0, 1.0), src.a);
}
