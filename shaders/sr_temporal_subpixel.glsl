// Multi-frame subpixel super-resolution via motion-compensated HF accumulation.
//
// Core idea: each frame is a differently-phased aliased observation of a higher-res scene.
// The alternating jitter from frame_shift.glsl guarantees subpixel diversity —
// even on completely static shots, consecutive frames sample the scene at different
// subpixel offsets. By registering the previous frame and averaging the high-frequency
// components, we recover detail that no single frame can provide alone.
//
// Three steps per frame:
//   1. Register PREV to current coordinates using the known jitter offset,
//      refined with a ±2px integer search to absorb natural camera drift.
//   2. Extract the HF (3x3 unsharp) from both current frame and accumulated image.
//   3. Mix the two HF observations — different subpixel phases, so uncorrelated
//      quantization noise partly cancels; coherent scene detail adds up.
//
// SR_ACCUM stores the previous frame's enhanced output. Reading its HF is reading
// the geometrically-weighted average of all past frame HF components — genuine
// multi-frame accumulation without a separate EMA pass.
//
// Placement: immediately after frame_shift.glsl, before temporal_motion_blur.glsl.
// sr_jitter_x / sr_jitter_y must match fsh_x / fsh_y exactly.
//
// Cold start: SR_ACCUM is black on frame 0, so hf_accum = 0 and blend = 0 — the
// first 2-3 frames pass through cleanly, then the effect ramps up automatically.

//!PARAM sr_jitter_x
//!TYPE float
//!MINIMUM -4.0
//!MAXIMUM 4.0
0.9

//!PARAM sr_jitter_y
//!TYPE float
//!MINIMUM -4.0
//!MAXIMUM 4.0
-0.5

//!PARAM sr_mix
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.45

//!PARAM sr_motion_thr
//!TYPE float
//!MINIMUM 0.001
//!MAXIMUM 0.20
0.04

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND PREV
//!BIND SR_ACCUM
//!SAVE SR_ACCUM
//!DESC [SR] Multi-frame subpixel reconstruction

const vec3 LW = vec3(0.299, 0.587, 0.114);

vec4 hook()
{
    vec2 uv = HOOKED_pos;
    vec2 pt = HOOKED_pt;

    vec3 current = HOOKED_tex(uv).rgb;
    float cur_luma = dot(current, LW);

    // ── 1. Motion estimate ───────────────────────────────────────────────────
    //
    // Base: known jitter offset.
    //   frame_shift shifts on even frames (frame % fsh_every == 0).
    //   On even frames: HOOKED is shifted, PREV was not.
    //     HOOKED[uv] = scene at (uv + jitter) in unshifted coords.
    //     PREV[uv + jitter] = same scene content.  → mv = +jitter
    //   On odd frames: HOOKED is not shifted, PREV was.
    //     PREV[uv - jitter] = same scene content.  → mv = -jitter

    vec2 jitter = vec2(sr_jitter_x, sr_jitter_y);
    vec2 mv     = (frame % 2u == 0u) ? jitter : -jitter;

    // Refine: ±2px integer search over PREV to absorb camera drift.
    float best_sad = 1e9;
    vec2  best_mv  = mv;

    for (int dx = -2; dx <= 2; dx++) {
        for (int dy = -2; dy <= 2; dy++) {
            vec2  cand = mv + vec2(float(dx), float(dy));
            float sad  = abs(dot(PREV_tex(uv + cand * pt).rgb, LW) - cur_luma);
            if (sad < best_sad) {
                best_sad = sad;
                best_mv  = cand;
            }
        }
    }
    mv = best_mv;
    vec2 prev_uv = uv + mv * pt;

    // Confidence: residual luma difference after compensation.
    // High residual → scene moved beyond search range, suppress blending.
    float residual = abs(dot(PREV_tex(prev_uv).rgb, LW) - cur_luma);
    float conf     = 1.0 - smoothstep(0.0, sr_motion_thr, residual);

    // ── 2. High-frequency extraction (3x3 box unsharp) ──────────────────────

    // HF of current frame
    vec3 blur_cur = vec3(0.0);
    for (int bx = -1; bx <= 1; bx++)
        for (int by = -1; by <= 1; by++)
            blur_cur += HOOKED_tex(uv + vec2(float(bx), float(by)) * pt).rgb;
    blur_cur *= (1.0 / 9.0);
    vec3 hf_current = current - blur_cur;

    // HF of accumulated image at registered previous position.
    // SR_ACCUM holds last frame's enhanced output — its HF is the geometrically-
    // weighted average of all past frame HF components at that phase offset.
    vec3 accum_aligned = SR_ACCUM_tex(prev_uv).rgb;

    vec3 blur_accum = vec3(0.0);
    for (int bx = -1; bx <= 1; bx++)
        for (int by = -1; by <= 1; by++)
            blur_accum += SR_ACCUM_tex(prev_uv + vec2(float(bx), float(by)) * pt).rgb;
    blur_accum *= (1.0 / 9.0);
    vec3 hf_accum = accum_aligned - blur_accum;

    // Cold-start guard: if accum is unseeded (near black), skip blending.
    float accum_energy = dot(accum_aligned, vec3(1.0));
    float is_seeded    = step(0.015, accum_energy);

    // ── 3. HF merge and injection ────────────────────────────────────────────
    //
    // Mix the two HF observations. The accumulated HF at prev_uv is at a
    // different subpixel phase than current — uncorrelated noise averages out,
    // coherent scene detail reinforces. This is the super-resolution step.

    float blend  = sr_mix * conf * is_seeded;
    vec3 hf_improved = mix(hf_current, hf_accum, blend);

    // Replace current HF with the improved version.
    // LF base is always from current frame — no ghosting on moving content.
    vec3 result = current - hf_current + hf_improved;

    return vec4(clamp(result, 0.0, 1.0), 1.0);
}