// Motion-gated temporal accumulation for static mid-tone smooth regions.
//
// Noise is perceptually loudest where three conditions align:
//   1. Mid-tone luma  — Weber's law peaks around Y≈0.2–0.5 linear
//   2. Temporal stillness — no motion to mask the oscillation
//   3. Spatial smoothness — no fine texture to absorb the noise
//
// Typical victims: curtains, walls, flat clothing, neutral backgrounds.
// Typical non-victims: skin (texture + movement), dark suits (absorbed),
//                      complex objects (spatial masking), moving things (temporal masking).
//
// Algorithm:
//   For pixels that pass ALL gates (mid-tone, static, smooth, not-skin):
//     new_accum = mix(current, prev_accum, ss_alpha)   // EMA temporal average
//     output    = mix(current, new_accum, gate × ss_strength)
//   Otherwise:
//     output    = current                               // pass-through
//     new_accum = current                               // reset accumulation state
//
//   The EMA accumulates coherent signal while cancelling random noise frame by frame.
//   With ss_alpha=0.75, effective accumulation ≈ 4 frames → ~2× SNR improvement.
//   Because accumulation only runs in static zones, moving content is untouched.
//
// Gates:
//   ss_motion_thr   — luma delta to previous frame above which = motion → off
//   ss_luma_lo/hi   — luma window for "mid-tone" (below = dark suit, above = highlight)
//   ss_smooth_thr   — max 4-neighbor gradient above which = real texture → off
//   ss_skin_protect — suppresses the gate near skin hue (0=off, 1=full)
//
// Place after the DNR residue cleaner, before hdeband and upscalers.

//!PARAM ss_alpha
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.95
0.75

//!PARAM ss_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.85

//!PARAM ss_motion_thr
//!TYPE float
//!MINIMUM 0.002
//!MAXIMUM 0.10
0.018

//!PARAM ss_luma_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.06

//!PARAM ss_luma_hi
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 1.0
0.55

//!PARAM ss_smooth_thr
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.20
0.035

//!PARAM ss_skin_protect
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.80

//!HOOK MAIN
//!BIND HOOKED
//!BIND SS_PREV
//!DESC [Custom] Static-zone temporal smooth

// BT.2020 luma (linear domain)
float ss_luma(vec3 c) { return dot(c, vec3(0.2627, 0.6780, 0.0593)); }

// BT.2020 YCbCr for skin detection (column-major)
const mat3 RGB_TO_YCC = mat3(
     0.2627, -0.1396,  0.5000,
     0.6780, -0.3604, -0.4598,
     0.0593,  0.5000, -0.0402
);

vec4 hook() {
    vec2  uv  = HOOKED_pos;
    vec2  px  = HOOKED_pt;
    vec4  src = HOOKED_tex(uv);

    vec3  rgb = linearize(src).rgb;
    float Y   = ss_luma(rgb);

    ivec2 ipix = ivec2(floor(uv * HOOKED_size));

    // ------------------------------------------------------------------
    // Previous accumulated frame (stored linearized RGB)
    // ------------------------------------------------------------------
    vec4  prev_data = imageLoad(SS_PREV, ipix);
    vec3  prev_accum = prev_data.rgb;
    float Y_prev     = ss_luma(prev_accum);

    // ------------------------------------------------------------------
    // Gate 1: motion — compare current luma to previous accumulation.
    // Large change = real content motion or scene cut → reset.
    // ------------------------------------------------------------------
    float motion     = abs(Y - Y_prev);
    float motionGate = 1.0 - smoothstep(ss_motion_thr, ss_motion_thr * 2.5, motion);

    // ------------------------------------------------------------------
    // Gate 2: mid-tone luma window.
    // Dark regions (suit) and bright highlights are excluded.
    // ------------------------------------------------------------------
    float lumaGate = smoothstep(ss_luma_lo, ss_luma_lo + 0.04, Y) *
                     (1.0 - smoothstep(ss_luma_hi, ss_luma_hi + 0.04, Y));

    // ------------------------------------------------------------------
    // Gate 3: local spatial smoothness.
    // A smooth region (curtain, wall) has small pixel-to-pixel gradient.
    // A textured region (face, fabric detail) has large gradient → excluded.
    // Measured as max |ΔY| to the 4 immediate neighbours.
    // ------------------------------------------------------------------
    float lL = ss_luma(linearize(HOOKED_tex(uv + vec2(-1.0,  0.0) * px)).rgb);
    float lR = ss_luma(linearize(HOOKED_tex(uv + vec2( 1.0,  0.0) * px)).rgb);
    float lU = ss_luma(linearize(HOOKED_tex(uv + vec2( 0.0, -1.0) * px)).rgb);
    float lD = ss_luma(linearize(HOOKED_tex(uv + vec2( 0.0,  1.0) * px)).rgb);
    float maxGrad = max(max(abs(Y - lL), abs(Y - lR)),
                        max(abs(Y - lU), abs(Y - lD)));
    float smoothGate = 1.0 - smoothstep(ss_smooth_thr, ss_smooth_thr * 2.0, maxGrad);

    // ------------------------------------------------------------------
    // Gate 4: skin protection.
    // Skin in BT.2020 linear: Cb ≈ -0.04 to -0.06, Cr ≈ 0.04 to 0.09.
    // A small exclusion radius around this cluster protects faces.
    // ------------------------------------------------------------------
    vec3  ycc     = RGB_TO_YCC * rgb;
    float Cb      = ycc.y;
    float Cr      = ycc.z;
    // Distance from skin cluster centre in Cb/Cr space
    float skinDist = length(vec2(Cb - (-0.050), Cr - 0.065));
    float skinMask = 1.0 - smoothstep(0.025, 0.060, skinDist);  // 1 = skin
    float skinGate = 1.0 - skinMask * ss_skin_protect;

    // ------------------------------------------------------------------
    // Combined gate
    // ------------------------------------------------------------------
    float gate = motionGate * lumaGate * smoothGate * skinGate;

    // ------------------------------------------------------------------
    // Temporal EMA accumulation
    //   new_accum = mix(current, prev_accum, ss_alpha)
    //             = (1 - α) × current + α × prev_accum
    // Effective accumulation depth ≈ 1/(1-α) frames.
    // With ss_alpha=0.75 → ~4 frames → ~2× SNR improvement on static content.
    // ------------------------------------------------------------------
    vec3 new_accum = mix(rgb, prev_accum, ss_alpha);

    // Output: blend current frame toward the accumulated average
    vec3 rgb_out = mix(rgb, new_accum, gate * ss_strength);

    // ------------------------------------------------------------------
    // Persist: store accumulated state for next frame.
    // In static zones: store new_accum (keep building history).
    // In moving zones: store current rgb (reset accumulation state).
    // Smooth transition between the two via the gate.
    // ------------------------------------------------------------------
    vec3 store = mix(rgb, new_accum, gate);
    imageStore(SS_PREV, ipix, vec4(store, 1.0));

    vec3 nl = delinearize(vec4(clamp(rgb_out, 0.0, 1.0), 1.0)).rgb;
    return vec4(nl, src.a);
}

//!TEXTURE SS_PREV
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE
