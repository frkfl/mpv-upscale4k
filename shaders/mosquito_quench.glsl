// Mosquito Noise Quench — temporal suppressor for MPEG-2 edge-adjacent ringing.
//
// MPEG-2 DCT quantization produces ringing halos within ~8 pixels of strong edges.
// Because each frame's quantization coefficients differ slightly, this ringing
// oscillates frame-to-frame — the "buzzing" visible around text and hard edges.
//
// A pixel qualifies as a mosquito candidate when ALL of these hold:
//   (a) edge_proximity — it is NEAR (but not ON) a strong luma edge,
//   (b) flicker       — its luma differs from the previous frame in a local 3×3,
//   (c) motion        — the surrounding region is NOT genuinely moving.
//
// Suppression: conditional blend toward the previous frame. For oscillating DCT
// ringing (sign alternates each frame), blending averages out the oscillation and
// converges toward the true underlying value over consecutive frames.
//
// Hook: MAIN — native DVD resolution (720×480), before upscaling.
// The artifact lives here; catching it before ravu/FSRCNNX spreads it is key.

//!PARAM mnq_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.55

//!PARAM mnq_edge_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.20
0.04

//!PARAM mnq_edge_hi
//!TYPE float
//!MINIMUM 0.02
//!MAXIMUM 0.50
0.18

//!PARAM mnq_flicker_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.10
0.006

//!PARAM mnq_flicker_hi
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.20
0.040

//!PARAM mnq_motion_thr
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.15
0.030

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV
//!DESC [DVD] Mosquito noise temporal quench

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 pt = HOOKED_pt;
    const vec3 lw = vec3(0.299, 0.587, 0.114);

    vec3 c    = HOOKED_tex(uv).rgb;
    vec3 prev = PREV_tex(uv).rgb;

    // ─── 3×3 neighbourhood: Sobel gradient + local flicker in one pass ──────
    // Reuses the same 9 sample positions for both computations.
    float s[9];
    float flicker = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int   idx = (dy + 1) * 3 + (dx + 1);
            vec2  o   = uv + pt * vec2(float(dx), float(dy));
            float yc  = (dx == 0 && dy == 0) ? dot(c,    lw) : dot(HOOKED_tex(o).rgb, lw);
            float yp  = (dx == 0 && dy == 0) ? dot(prev, lw) : dot(PREV_tex(o).rgb,   lw);
            s[idx]   = yc;
            flicker  += abs(yc - yp);
        }
    }
    flicker /= 9.0;

    // Sobel from the sampled grid
    float Gx = (s[2] + 2.0*s[5] + s[8]) - (s[0] + 2.0*s[3] + s[6]);
    float Gy = (s[6] + 2.0*s[7] + s[8]) - (s[0] + 2.0*s[1] + s[2]);
    float self_edge = length(vec2(Gx, Gy));

    // ─── Extended proximity: gradient span across a ±3 px cross ─────────────
    // Detects pixels that are near (but not necessarily on) a strong edge.
    // abs(luma(+3) - luma(-3)) is large when an edge falls inside that 6px window.
    float el = dot(HOOKED_tex(uv + pt * vec2(-3.0,  0.0)).rgb, lw);
    float er = dot(HOOKED_tex(uv + pt * vec2( 3.0,  0.0)).rgb, lw);
    float eu = dot(HOOKED_tex(uv + pt * vec2( 0.0, -3.0)).rgb, lw);
    float ed = dot(HOOKED_tex(uv + pt * vec2( 0.0,  3.0)).rgb, lw);
    float prox = max(self_edge, max(abs(er - el), abs(ed - eu)));

    // edge_gate:  fires when near a strong edge
    // self_gate:  suppressed when the pixel IS the strong edge (protects contours)
    float edge_gate = smoothstep(mnq_edge_lo, mnq_edge_hi, prox);
    float self_gate = 1.0 - smoothstep(mnq_edge_hi * 0.8, mnq_edge_hi * 1.5, self_edge);

    // ─── Flicker gate ────────────────────────────────────────────────────────
    float flicker_gate = smoothstep(mnq_flicker_lo, mnq_flicker_hi, flicker);

    // ─── Regional motion: mean |curr – prev| at ±5 px cardinal ──────────────
    // If the surrounding region is genuinely moving, the flicker is real content.
    float motion = 0.0;
    motion += abs(dot(HOOKED_tex(uv + pt * vec2( 5.0,  0.0)).rgb, lw)
                - dot(PREV_tex (uv + pt * vec2( 5.0,  0.0)).rgb, lw));
    motion += abs(dot(HOOKED_tex(uv + pt * vec2(-5.0,  0.0)).rgb, lw)
                - dot(PREV_tex (uv + pt * vec2(-5.0,  0.0)).rgb, lw));
    motion += abs(dot(HOOKED_tex(uv + pt * vec2( 0.0,  5.0)).rgb, lw)
                - dot(PREV_tex (uv + pt * vec2( 0.0,  5.0)).rgb, lw));
    motion += abs(dot(HOOKED_tex(uv + pt * vec2( 0.0, -5.0)).rgb, lw)
                - dot(PREV_tex (uv + pt * vec2( 0.0, -5.0)).rgb, lw));
    motion /= 4.0;
    float motion_gate = 1.0 - smoothstep(mnq_motion_thr * 0.5, mnq_motion_thr, motion);

    // ─── Combine and blend ───────────────────────────────────────────────────
    float gate = edge_gate * self_gate * flicker_gate * motion_gate * mnq_strength;
    return vec4(mix(c, prev, gate), 1.0);
}
