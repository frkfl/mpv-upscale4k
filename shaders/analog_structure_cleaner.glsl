// analog_structure_cleaner.glsl
//
// Two-pass analog noise / structure shader.
//
// IDEA: analog noise often looks like a Sobel map — it has strong directional,
// gradient-like character. A simple edge detector cannot tell noise from real
// structure because both produce high gradient response.
//
// The key discriminator is chroma-luma coherence: real edges produce correlated
// gradients in both luma and chroma. Analog noise produces independent luma and
// chroma perturbations → coherence is low for noisy "edges".
//
// Pass 1 computes a per-pixel clarity potential P (0=real edge, 1=noise/unclear)
// and saves the gradient direction alongside it.
//
// Pass 2 applies a dual action:
//   - Where P is high (noise region): smooth perpendicular to the local gradient.
//     Smoothing across the fake edge reduces it without blurring real structure.
//   - Where P is low (real edge, coherent): apply directional unsharp masking
//     along the gradient, reinforcing luma contrast so downstream shaders
//     treat it as a definite edge.
//
// The middle ground (P ≈ 0.5) gets neither action — the shader stays hands-off.

// ════════════════════════════════════════════════════════════════════════════
// PASS 1 — Classify: compute clarity map
// ════════════════════════════════════════════════════════════════════════════

//!PARAM asc_sigma
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 2.0
0.5

//!PARAM asc_m_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.3
0.02

//!PARAM asc_m_hi
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.20

//!PARAM asc_r_low
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.15

//!PARAM asc_r_high
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.45

//!HOOK MAIN
//!BIND HOOKED
//!SAVE ASC_MAP
//!DESC [Custom] Analog Structure Cleaner — Pass 1: clarity classify

#define EPS 1e-6

float luma(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

// Average of Cb and Cr (BT.709), useful as a single chroma scalar
float chroma_mean(vec3 rgb, float Y) {
    float Cb = (rgb.b - Y) / 1.8556 + 0.5;
    float Cr = (rgb.r - Y) / 1.5748 + 0.5;
    return 0.5 * (Cb + Cr);
}

// 3-tap separable Gaussian weights for a given sigma
vec3 gauss3w(float s) {
    float w1 = exp(-0.5 / (s * s));
    float n  = 1.0 + 2.0 * w1;
    return vec3(w1, 1.0, w1) / n;
}

// Pre-smoothed luma (separable 3-tap, horizontal then vertical)
float luma_smooth(vec2 uv, vec2 px) {
    vec3 w = gauss3w(asc_sigma);
    // horizontal blur first
    float h = w.x * luma(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb)
            + w.y * luma(HOOKED_tex(uv                   ).rgb)
            + w.z * luma(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb);
    // vertical blur using raw samples (approximation; centre reuses h)
    float v = w.x * luma(HOOKED_tex(uv - vec2(0.0, px.y)).rgb)
            + w.y * h
            + w.z * luma(HOOKED_tex(uv + vec2(0.0, px.y)).rgb);
    return v;
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // ── Gradient on pre-smoothed luma ────────────────────────────────────
    float Ys   = luma_smooth(uv,                   px);
    float Ys_r = luma_smooth(uv + vec2(px.x, 0.0), px);
    float Ys_l = luma_smooth(uv - vec2(px.x, 0.0), px);
    float Ys_u = luma_smooth(uv + vec2(0.0, px.y), px);
    float Ys_d = luma_smooth(uv - vec2(0.0, px.y), px);

    vec2  gY  = 0.5 * vec2(Ys_r - Ys_l, Ys_u - Ys_d);
    float m   = length(gY);
    vec2  dir = (m > EPS) ? gY / m : vec2(1.0, 0.0);

    // ── Curvature along gradient direction ───────────────────────────────
    // Second derivative: positive = concave, negative = convex
    float Yp1 = luma(HOOKED_tex(uv + dir * px).rgb);
    float Ym1 = luma(HOOKED_tex(uv - dir * px).rgb);
    float Ypp = Yp1 + Ym1 - 2.0 * Ys;
    float dY  = 0.5 * abs(Yp1 - Ym1) + EPS;
    // r_w: high curvature relative to gradient → noise-like
    float r_w = clamp(abs(Ypp) / dY, 0.0, 2.0);

    // ── Chroma-luma coherence ─────────────────────────────────────────────
    // Real edges: luma gradient and chroma gradient point the same way.
    // Noise: luma and chroma perturbations are independent → low coherence.
    float Y_r = luma(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb);
    float Y_l = luma(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb);
    float Y_u = luma(HOOKED_tex(uv + vec2(0.0, px.y)).rgb);
    float Y_d = luma(HOOKED_tex(uv - vec2(0.0, px.y)).rgb);
    float C_r = chroma_mean(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb, Y_r);
    float C_l = chroma_mean(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb, Y_l);
    float C_u = chroma_mean(HOOKED_tex(uv + vec2(0.0, px.y)).rgb, Y_u);
    float C_d = chroma_mean(HOOKED_tex(uv - vec2(0.0, px.y)).rgb, Y_d);
    vec2 gC   = 0.5 * vec2(C_r - C_l, C_u - C_d);

    float gY_len = max(length(gY), EPS);
    float gC_len = max(length(gC), EPS);
    float c = abs(dot(gY, gC) / (gY_len * gC_len));
    c = clamp(c, 0.0, 1.0);

    // ── Clarity potential P ───────────────────────────────────────────────
    // P is HIGH  → noise / unclear structure (clean it)
    // P is LOW   → real edge, coherent      (reinforce it)
    // s_gate suppresses P at strong edges: strong gradient = probably real
    float s_gate = 1.0 - smoothstep(asc_m_lo, asc_m_hi, m);
    float P = s_gate * smoothstep(asc_r_low, asc_r_high, r_w) * c;
    P = clamp(P, 0.0, 1.0);

    // Pack: R=P, G=dir.x (packed 0..1), B=dir.y (packed 0..1), A=unused
    return vec4(P, dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, 1.0);
}

// ════════════════════════════════════════════════════════════════════════════
// PASS 2 — Apply: clean noise + reinforce real edges
// ════════════════════════════════════════════════════════════════════════════

//!PARAM asc_clean
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM asc_sharpen
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.6

//!PARAM asc_edge_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.2
0.01

//!PARAM asc_edge_hi
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.08

//!HOOK MAIN
//!BIND HOOKED
//!BIND ASC_MAP
//!DESC [Custom] Analog Structure Cleaner — Pass 2: clean + reinforce

#define EPS2 1e-6
const vec3 W709 = vec3(0.2126, 0.7152, 0.0722);

float luma2(vec3 rgb) { return dot(rgb, W709); }

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // ── Unpack classification ─────────────────────────────────────────────
    vec4  map = ASC_MAP_tex(ASC_MAP_pos);
    float P   = map.r;
    vec2  dir = map.gb * 2.0 - 1.0;   // unpack [-1, 1]

    vec3  rgb = HOOKED_tex(uv).rgb;
    float Y   = luma2(rgb);

    // ── Gradient magnitude (recomputed, cheap) ────────────────────────────
    float Yr = luma2(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb);
    float Yl = luma2(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb);
    float Yu = luma2(HOOKED_tex(uv + vec2(0.0, px.y)).rgb);
    float Yd = luma2(HOOKED_tex(uv - vec2(0.0, px.y)).rgb);
    float m  = 0.5 * length(vec2(Yr - Yl, Yu - Yd));

    // ── ACTION 1: Clean noise interiors ──────────────────────────────────
    // Smooth perpendicular to the gradient direction.
    // This diffuses across the fake "edge" created by the noise,
    // reducing it without touching real edges (where P is low).
    vec2 perp    = vec2(-dir.y, dir.x);
    vec3 rgb_p1  = HOOKED_tex(uv + perp * px).rgb;
    vec3 rgb_m1  = HOOKED_tex(uv - perp * px).rgb;
    // Weighted: centre gets 2x weight for a gentle 1-2-1 kernel
    vec3 rgb_smooth = (rgb_p1 + 2.0 * rgb + rgb_m1) / 4.0;
    // Blend toward smooth proportional to P (noise) × user strength
    vec3 rgb_clean  = mix(rgb, rgb_smooth, P * asc_clean);

    // ── ACTION 2: Reinforce real edges ────────────────────────────────────
    // At real edge midpoints the second derivative along the gradient
    // direction (Ypp) is non-zero. Subtracting it from luma boosts
    // contrast at the edge — equivalent to directional unsharp masking.
    // Gate: only where (1-P) is high (real edge) and gradient is meaningful.
    float Yp1      = luma2(HOOKED_tex(uv + dir * px).rgb);
    float Ym1      = luma2(HOOKED_tex(uv - dir * px).rgb);
    float Ypp      = Yp1 + Ym1 - 2.0 * Y;
    float edge_gate = (1.0 - P) * smoothstep(asc_edge_lo, asc_edge_hi, m);
    // Clamp Ypp to avoid over-sharpening on very hard edges
    float delta_Y  = -asc_sharpen * clamp(Ypp, -0.15, 0.15) * edge_gate;

    // Apply delta to luma only, preserving chroma ratios
    float Y_clean = luma2(rgb_clean);
    float Y_new   = clamp(Y_clean + delta_Y, 0.0, 1.0);
    vec3  rgb_out = rgb_clean * (Y_new / (Y_clean + EPS2));

    return vec4(clamp(rgb_out, 0.0, 1.0), 1.0);
}
