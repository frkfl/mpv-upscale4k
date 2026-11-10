// static_detail_accum.glsl
//
// Temporal accumulation with two modes split by spatial texture:
//
//   FLAT zones (small spatial gradient):
//     Standard temporal smoothing — EMA toward accumulated mean.
//     Kills oscillating noise on walls, curtains, etc. Same logic as static_smooth.
//
//   TEXTURED zones (meaningful spatial gradient):
//     Temporal detail amplification.
//     The EMA mean is a noise-cleaned version of the signal. The residual
//     (current - mean) is mostly real structure once accumulation has settled.
//     Amplifying it = temporal unsharp masking, where the "blur" is accumulated
//     temporal noise rather than a spatial kernel.
//     Film-grain DVDs benefit most: grain varies per frame, averaging reveals
//     the signal underneath, residual carries genuine texture.
//
// A confidence counter (A channel of storage) ramps up over static frames
// and resets on motion. Detail amplification is gated on confidence — prevents
// amplifying freshly-reset noise after a scene cut or motion burst.
//
// Setting sda_detail_gain=0 → pure smoothing, same behaviour as static_smooth.
//
// NOTE: hooks OUTPUT (post-upscale 4K). The accumulated detail is whatever
// ArtCNN/SSimSuperRes produced frame-to-frame. For genuine pre-upscale detail
// recovery the hook would need to move to MAIN at native resolution.

//!PARAM sda_alpha
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.95
0.75

//!PARAM sda_smooth_str
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.60

//!PARAM sda_detail_gain
//!DESC Amplification of settled temporal residual in textured zones. 0 = smooth only.
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.30

//!PARAM sda_conf_rate
//!DESC Confidence ramp rate per static frame. 1/rate = approx frames to 63%.
//!TYPE float
//!MINIMUM 0.01
//!MAXIMUM 1.0
0.20

//!PARAM sda_motion_thr
//!TYPE float
//!MINIMUM 0.002
//!MAXIMUM 0.10
0.012

//!PARAM sda_luma_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.06

//!PARAM sda_luma_hi
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 1.0
0.75

//!PARAM sda_smooth_thr
//!DESC Gradient threshold between flat zones (smooth) and textured zones (detail).
//!TYPE float
//!MINIMUM 0.005
//!MAXIMUM 0.20
0.035

//!PARAM sda_skin_protect
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.80

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND SDA_PREV
//!DESC [Custom] Temporal detail accumulation

float sda_luma(vec3 c) { return dot(c, vec3(0.2627, 0.6780, 0.0593)); }

const mat3 SDA_RGB_TO_YCC = mat3(
     0.2627, -0.1396,  0.5000,
     0.6780, -0.3604, -0.4598,
     0.0593,  0.5000, -0.0402
);

vec4 hook() {
    vec2  uv  = HOOKED_pos;
    vec2  px  = HOOKED_pt;
    vec4  src = HOOKED_tex(uv);

    vec3  rgb = linearize(src).rgb;
    float Y   = sda_luma(rgb);

    ivec2 ipix = ivec2(floor(uv * HOOKED_size));

    // Load storage: RGB = accumulated mean, A = confidence
    vec4  prev_data  = imageLoad(SDA_PREV, ipix);
    vec3  prev_accum = prev_data.rgb;
    float confidence = prev_data.a;
    float Y_prev     = sda_luma(prev_accum);

    // Gate: motion
    float motion     = abs(Y - Y_prev);
    float motionGate = 1.0 - smoothstep(sda_motion_thr, sda_motion_thr * 2.5, motion);

    // Gate: luma window
    float lumaGate = smoothstep(sda_luma_lo, sda_luma_lo + 0.04, Y) *
                     (1.0 - smoothstep(sda_luma_hi, sda_luma_hi + 0.04, Y));

    // Gate: skin protection
    vec3  ycc      = SDA_RGB_TO_YCC * rgb;
    float skinDist = length(vec2(ycc.y - (-0.050), ycc.z - 0.065));
    float skinGate = 1.0 - smoothstep(0.025, 0.060, skinDist) * sda_skin_protect;

    // Spatial texture measure — splits flat zones (smooth) from textured (detail).
    // smoothZone: 1 = flat, 0 = textured
    float lL = sda_luma(linearize(HOOKED_tex(uv + vec2(-1.0,  0.0) * px)).rgb);
    float lR = sda_luma(linearize(HOOKED_tex(uv + vec2( 1.0,  0.0) * px)).rgb);
    float lU = sda_luma(linearize(HOOKED_tex(uv + vec2( 0.0, -1.0) * px)).rgb);
    float lD = sda_luma(linearize(HOOKED_tex(uv + vec2( 0.0,  1.0) * px)).rgb);
    float maxGrad   = max(max(abs(Y - lL), abs(Y - lR)),
                          max(abs(Y - lU), abs(Y - lD)));
    float smoothZone = 1.0 - smoothstep(sda_smooth_thr, sda_smooth_thr * 2.0, maxGrad);

    // EMA accumulation
    vec3 new_accum = mix(rgb, prev_accum, sda_alpha);

    // Confidence ramp: builds while static, resets on motion
    float new_confidence = mix(0.0,
                               min(confidence + sda_conf_rate, 1.0),
                               motionGate);

    // Combined output.
    // net_weight > 0: pull toward mean (smooth, flat zone)
    // net_weight < 0: push away from mean (amplify, textured zone)
    // rgb_out = rgb + (new_accum - rgb) * net_weight * combinedBlend
    float combinedBlend = motionGate * lumaGate * skinGate;
    float net_weight    = smoothZone * sda_smooth_str
                        - (1.0 - smoothZone) * new_confidence * sda_detail_gain;
    vec3  accum_delta = clamp(new_accum - rgb, -0.15, 0.15);
    vec3  rgb_out     = rgb + accum_delta * net_weight * combinedBlend;

    // Persist: static zones keep accumulating, motion resets to current frame
    vec3 store = mix(rgb, new_accum, motionGate * lumaGate * skinGate);
    imageStore(SDA_PREV, ipix, vec4(store, new_confidence));

    vec3 nl = delinearize(vec4(clamp(rgb_out, 0.0, 1.0), 1.0)).rgb;
    return vec4(nl, src.a);
}

//!TEXTURE SDA_PREV
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE
