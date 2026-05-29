// DNR-residue suppressor for Blu-ray / streaming sources with heavy-handed DNR.
//
// Bad studio DNR (Aliens BR, etc.) leaves two distinct artifacts:
//
//   CHROMA SPECKLE — fixed-pattern 1-2px chromatic blobs locked to the 4:2:0
//   grid.  Each 4:2:0 block got an inconsistent chroma decision from the DNR
//   algorithm, producing a periodic coloured dithering pattern.
//
//   TEMPORAL OSCILLATION — the same decision threshold wavers frame-to-frame
//   on borderline pixels.  Same pixel oscillates between "treated" and
//   "untreated" states, producing the "unstable 1-pixel dithering" effect
//   that fuses at 1080p but is plainly visible on 4K or large screens.
//
// Two targeted operations in one pass (linear BT.2020 YCbCr):
//
//   SPATIAL chroma bilateral filter (3×3):
//     Smooths Cb/Cr where the chroma distance to neighbours is small.
//     Protects real colour boundaries (large chroma delta = high bilateral cost).
//     Targets the fixed-pattern speckle that bilateral filtering is designed for.
//
//   SPATIAL luma outlier gate:
//     Detects isolated luma pixels that differ strongly from the neighbourhood
//     mean, in regions where the neighbourhood itself is smooth (small range).
//     Pulls them toward the mean.  Skips real edges (large neighbourhood range).
//
//   TEMPORAL chroma EMA (needs PREV frame):
//     Blends current Cb/Cr toward previous frame, gated on:
//       - luma motion  (don't blend when objects are moving)
//       - chroma-delta amplitude  (only blend the small DNR oscillation,
//         not large real colour transitions)
//
// Place after mild_clean_blockfix / fake_micro_texture_removal, before hdeband
// and upscalers.  Reason: catch the artifact at native 1080p frequency before
// FSRCNNX scales and bakes it into the 4K output.
//
// Parameters:
//   dr_chroma_sigma  — chroma bilateral range sigma.  DNR speckle is typically
//                      ±0.02-0.04 in linear Cb/Cr; sigma=0.028 sets the
//                      half-weight point at ~0.033 chroma distance.
//   dr_chroma_str    — spatial bilateral blend weight (0=off, 1=full)
//   dr_luma_str      — isolated-pixel luma correction strength
//   dr_temporal_str  — temporal chroma EMA blend strength
//   dr_motion_thr    — luma motion gate threshold; above this = real motion,
//                      temporal blend is suppressed

//!PARAM dr_chroma_sigma
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.15
0.028

//!PARAM dr_chroma_str
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.70

//!PARAM dr_luma_str
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.40

//!PARAM dr_temporal_str
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.35

//!PARAM dr_motion_thr
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.10
0.025

//!HOOK MAIN
//!BIND HOOKED
//!BIND DR_PREV
//!DESC [Custom] DNR residue — chroma/luma stabilizer

// BT.2020 RGB ↔ YCbCr — column-major GLSL, linear domain
// Y  =  0.2627 R + 0.6780 G + 0.0593 B
// Cb = -0.1396 R - 0.3604 G + 0.5000 B
// Cr =  0.5000 R - 0.4598 G - 0.0402 B
const mat3 RGB_TO_YCC = mat3(
     0.2627, -0.1396,  0.5000,   // col 0 — R → Y, Cb, Cr
     0.6780, -0.3604, -0.4598,   // col 1 — G → Y, Cb, Cr
     0.0593,  0.5000, -0.0402    // col 2 — B → Y, Cb, Cr
);
// R = Y + 1.4746 Cr
// G = Y - 0.1645 Cb - 0.5714 Cr
// B = Y + 1.8814 Cb
const mat3 YCC_TO_RGB = mat3(
    1.0,     1.0,      1.0,       // col 0 — Y  → R, G, B
    0.0,    -0.1645,   1.8814,    // col 1 — Cb → R, G, B
    1.4746, -0.5714,   0.0        // col 2 — Cr → R, G, B
);

vec4 hook() {
    vec2  uv   = HOOKED_pos;
    vec2  px   = HOOKED_pt;
    vec4  src  = HOOKED_tex(uv);

    // Work in linear light throughout
    vec3  rgb  = linearize(src).rgb;
    vec3  ycc  = RGB_TO_YCC * rgb;
    float Y    = ycc.x;
    float Cb   = ycc.y;
    float Cr   = ycc.z;

    ivec2 ipix = ivec2(floor(uv * HOOKED_size));

    // ------------------------------------------------------------------
    // 3×3 spatial pass
    // Accumulates:
    //   - bilateral-weighted Cb/Cr (chroma speckle removal)
    //   - unweighted Y of 8 neighbours excl. centre (luma outlier detection)
    // ------------------------------------------------------------------
    float inv2sr2 = 0.5 / (dr_chroma_sigma * dr_chroma_sigma);

    float wSum  = 0.0, CbAcc = 0.0, CrAcc = 0.0;
    float YnAcc = 0.0, YnMin = 1.0e6, YnMax = -1.0e6;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec3  s    = linearize(HOOKED_tex(uv + vec2(float(dx), float(dy)) * px)).rgb;
            vec3  sycc = RGB_TO_YCC * s;
            float sY   = sycc.x;
            float sCb  = sycc.y;
            float sCr  = sycc.z;

            // Spatial Gaussian weight (sigma_s = 1.0 → 2σ² = 2)
            float ws = exp(-float(dx*dx + dy*dy) * 0.5);

            // Chroma bilateral weight — low when chroma distance is large
            float dCb = sCb - Cb;
            float dCr = sCr - Cr;
            float wc  = ws * exp(-(dCb*dCb + dCr*dCr) * inv2sr2);

            wSum  += wc;
            CbAcc += wc * sCb;
            CrAcc += wc * sCr;

            // Luma: neighbours only (exclude centre pixel from the reference mean
            // so the outlier doesn't bias its own reference)
            if (dx != 0 || dy != 0) {
                YnAcc += sY;
                YnMin  = min(YnMin, sY);
                YnMax  = max(YnMax, sY);
            }
        }
    }

    // Chroma: bilateral-filtered result
    float Cb_sp  = CbAcc / wSum;
    float Cr_sp  = CrAcc / wSum;
    float Cb_out = mix(Cb, Cb_sp, dr_chroma_str);
    float Cr_out = mix(Cr, Cr_sp, dr_chroma_str);

    // Luma: statistical outlier gate
    //   devY     = how far centre is from neighbour mean
    //   YnRange  = spread of neighbours; large → real edge → don't touch
    float YnMean  = YnAcc / 8.0;
    float YnRange = YnMax - YnMin;
    float devY    = abs(Y - YnMean);
    float smooth  = 1.0 - smoothstep(0.04, 0.10, YnRange);   // 0 at edge, 1 in flat region
    float outlier = smoothstep(0.018, 0.040, devY) * smooth;
    float Y_out   = mix(Y, YnMean, outlier * dr_luma_str);

    // ------------------------------------------------------------------
    // Temporal chroma EMA
    // PREV stores [Y, Cb_out, Cr_out] from the previous processed frame.
    // Only blends in:
    //   - static regions (luma motion below threshold)
    //   - small-amplitude chroma changes (the DNR oscillation character)
    // ------------------------------------------------------------------
    if (frame > 0) {
        vec4  prev    = imageLoad(DR_PREV, ipix);
        float Y_prev  = prev.r;
        float Cb_prev = prev.g;
        float Cr_prev = prev.b;

        // Motion gate: luma changed → real motion → suppress blend
        float motion     = abs(Y - Y_prev);
        float motionGate = 1.0 - smoothstep(dr_motion_thr, dr_motion_thr * 2.5, motion);

        // Chroma oscillation gate: fire on small periodic changes, not large ones.
        // Lower bound: below this the signal is already stable (no need to blend).
        // Upper bound: above this it's a real colour event (cut, flash, movement).
        float chromaDelta = length(vec2(Cb_out - Cb_prev, Cr_out - Cr_prev));
        float chromaGate  = smoothstep(0.004, 0.016, chromaDelta) *
                            (1.0 - smoothstep(0.04, 0.08, chromaDelta));

        float blend = dr_temporal_str * motionGate * chromaGate;
        Cb_out = mix(Cb_out, Cb_prev, blend);
        Cr_out = mix(Cr_out, Cr_prev, blend);
    }

    // ------------------------------------------------------------------
    // Reconstruct + persist
    // ------------------------------------------------------------------
    vec3 rgb_out = YCC_TO_RGB * vec3(Y_out, Cb_out, Cr_out);

    // Store current processed [Y, Cb, Cr] for next frame's temporal gate
    imageStore(DR_PREV, ipix, vec4(Y_out, Cb_out, Cr_out, 1.0));

    vec3 nl = delinearize(vec4(clamp(rgb_out, 0.0, 1.0), 1.0)).rgb;
    return vec4(nl, src.a);
}

//!TEXTURE DR_PREV
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE
