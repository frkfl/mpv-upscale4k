// Pre-upscale subtitle anti-aliaser — inverse-composite alpha method.
//
// For each pixel on a subtitle edge:
//
//   1. EDGE GATE: immediate-neighbor gradient must be large (hard step).
//      Interior text pixels have neighbors at the same luma → exit unchanged.
//
//   2. BIMODAL GATE: the 3×3 neighborhood must contain both a bright-text
//      cluster and a dark-background cluster.  Soft scene edges, grain, etc.
//      typically lack one cluster → exit unchanged.
//
//   3. INVERSE COMPOSITE: recover per-pixel alpha.
//      The subtitle is a composite:  pixel = mix(bgColor, textColor, alpha)
//      Solving:  alpha = (luma(pixel) - bgLuma) / (textLuma - bgLuma)
//      Interior text  → alpha ≈ 1.0  (mathematical guarantee, window-size-free)
//      Background     → alpha ≈ 0.0  (same guarantee)
//      Edge pixels    → 0 < alpha < 1  (the existing ramp)
//
//   4. WIDEN THE RAMP: convolve the alpha values with a 5-tap Gaussian
//      (1-4-6-4-1/16) along the gradient direction (perpendicular to edge).
//      Interior: alpha=1 everywhere in kernel → smoothed alpha stays 1.
//      Background: alpha=0 everywhere → stays 0.
//      Edge pixels gain a ~1px-wider ramp on each side → smooth AA for FSRCNNX.
//
//   5. RECONSTRUCT: mix(bgColor, textColor, smoothAlpha)
//      Gates (edge, bimodal, confidence) are multiplied for a soft blend.
//
// Parameters:
//   st_hi_thresh    — luma ≥ this → text pixel  (white, bright yellow)
//   st_lo_thresh    — luma ≤ this → background pixel
//   st_edge_lo/hi   — smoothstep range for the immediate-neighbor gradient gate
//   st_contrast_min — minimum local luma range (extra false-positive guard)
//   st_strength     — overall blend weight (1.0 = full replacement at gate)

//!PARAM st_hi_thresh
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.0
0.75

//!PARAM st_lo_thresh
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.30

//!PARAM st_edge_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.35

//!PARAM st_edge_hi
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.55

//!PARAM st_contrast_min
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.45

//!PARAM st_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Subtitle pre-upscale anti-alias

float st_luma(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;
    vec2 px  = HOOKED_pt;
    vec4 src = HOOKED_tex(uv);
    vec3 c   = src.rgb;
    float lc = st_luma(c);

    // ------------------------------------------------------------------
    // Gate 1: immediate-neighbor edge strength.
    // Only pixels sitting on a hard luma step pass through.
    // ------------------------------------------------------------------
    vec3 sL = HOOKED_tex(uv + vec2(-1.0,  0.0) * px).rgb;
    vec3 sR = HOOKED_tex(uv + vec2( 1.0,  0.0) * px).rgb;
    vec3 sU = HOOKED_tex(uv + vec2( 0.0, -1.0) * px).rgb;
    vec3 sD = HOOKED_tex(uv + vec2( 0.0,  1.0) * px).rgb;

    float lL = st_luma(sL), lR = st_luma(sR);
    float lU = st_luma(sU), lD = st_luma(sD);

    float edgeStrength = max(max(abs(lc - lL), abs(lc - lR)),
                             max(abs(lc - lU), abs(lc - lD)));
    float edgeGate = smoothstep(st_edge_lo, st_edge_hi, edgeStrength);
    if (edgeGate < 0.01) return src;

    // ------------------------------------------------------------------
    // Gate 2: bimodal cluster analysis on the 3×3 neighborhood.
    // Both clusters must be present; their means become textColor / bgColor.
    // Using 3×3 (not 5×5) keeps the background estimate local and accurate.
    // ------------------------------------------------------------------
    vec3 sUL = HOOKED_tex(uv + vec2(-1.0, -1.0) * px).rgb;
    vec3 sUR = HOOKED_tex(uv + vec2( 1.0, -1.0) * px).rgb;
    vec3 sDL = HOOKED_tex(uv + vec2(-1.0,  1.0) * px).rgb;
    vec3 sDR = HOOKED_tex(uv + vec2( 1.0,  1.0) * px).rgb;

    float cHi = 0.0, cLo = 0.0;
    vec3  colHi = vec3(0.0), colLo = vec3(0.0);
    float minL = 1.0, maxL = 0.0;

    // Classify each of the 9 samples into hi/lo/mid
    #define CLASSIFY(s) { \
        float _l = st_luma(s); \
        minL = min(minL, _l); maxL = max(maxL, _l); \
        if      (_l >= st_hi_thresh) { cHi += 1.0; colHi += (s); } \
        else if (_l <= st_lo_thresh) { cLo += 1.0; colLo += (s); } \
    }
    CLASSIFY(c)
    CLASSIFY(sL)  CLASSIFY(sR)  CLASSIFY(sU)  CLASSIFY(sD)
    CLASSIFY(sUL) CLASSIFY(sUR) CLASSIFY(sDL) CLASSIFY(sDR)
    #undef CLASSIFY

    float rangeL = maxL - minL;
    if (rangeL < st_contrast_min || cHi < 1.0 || cLo < 1.0) return src;

    vec3  textColor = colHi / cHi;
    vec3  bgColor   = colLo / cLo;
    float textLuma  = st_luma(textColor);
    float bgLuma    = st_luma(bgColor);
    float denom     = textLuma - bgLuma;
    if (abs(denom) < 0.05) return src;  // clusters too close to invert cleanly

    // ------------------------------------------------------------------
    // Inverse composite: recover per-pixel alpha at center.
    // pixel = mix(bg, text, alpha)  =>  alpha = (lc - bgLuma) / denom
    // Works for bright-on-dark and dark-on-bright (denom sign handles it).
    // ------------------------------------------------------------------
    float alpha0 = clamp((lc - bgLuma) / denom, 0.0, 1.0);

    // ------------------------------------------------------------------
    // Widen the alpha ramp: 5-tap Gaussian along the gradient direction.
    // gd = unit vector pointing from background toward text (gradient dir).
    // Sampling ±1 and ±2 px along gd and averaging spreads the ramp by ~1px.
    // Interior (all neighbors also text): all alphas = 1 → result = 1. Safe.
    // Background (all neighbors also bg): all alphas = 0 → result = 0. Safe.
    // ------------------------------------------------------------------
    float dx = lR - lL;   // horizontal gradient (2px span)
    float dy = lD - lU;   // vertical gradient   (2px span)
    float gradLen = sqrt(dx * dx + dy * dy);
    if (gradLen < 0.01) return src;   // no dominant direction — skip

    vec2 gd = vec2(dx, dy) / gradLen;  // unit gradient direction

    float a_p1 = clamp((st_luma(HOOKED_tex(uv + gd * px       ).rgb) - bgLuma) / denom, 0.0, 1.0);
    float a_p2 = clamp((st_luma(HOOKED_tex(uv + gd * px * 2.0 ).rgb) - bgLuma) / denom, 0.0, 1.0);
    float a_m1 = clamp((st_luma(HOOKED_tex(uv - gd * px       ).rgb) - bgLuma) / denom, 0.0, 1.0);
    float a_m2 = clamp((st_luma(HOOKED_tex(uv - gd * px * 2.0 ).rgb) - bgLuma) / denom, 0.0, 1.0);

    // 1-4-6-4-1 Gaussian kernel / 16
    float smoothAlpha = (a_m2 + 4.0*a_m1 + 6.0*alpha0 + 4.0*a_p1 + a_p2) / 16.0;

    // ------------------------------------------------------------------
    // Reconstruct and blend
    // ------------------------------------------------------------------
    float confidence   = smoothstep(1.0, 3.0, min(cHi, cLo));
    float contrastGate = smoothstep(st_contrast_min, st_contrast_min + 0.15, rangeL);
    float gate = edgeGate * confidence * contrastGate * st_strength;

    vec3 aa = mix(bgColor, textColor, smoothAlpha);
    return vec4(mix(c, aa, gate), src.a);
}
