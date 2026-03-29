//!PARAM tmb_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM tmb_motion_lo
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.3
0.02

//!PARAM tmb_motion_hi
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.10

//!PARAM tmb_transience_lo
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 10.0
2.0

//!PARAM tmb_transience_hi
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 20.0
6.0

//!PARAM tmb_ema_alpha
//!TYPE float
//!MINIMUM 0.05
//!MAXIMUM 0.9
0.25

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV1
//!BIND PREV2
//!DESC [Custom] Temporal Motion Blur

const vec3  W709 = vec3(0.2126, 0.7152, 0.0722);
const float EPS  = 1e-6;

vec4 hook() {
    ivec2 ipix  = ivec2(floor(HOOKED_pos * HOOKED_size));
    vec3  cur   = HOOKED_tex(HOOKED_pos).rgb;
    float Y_cur = dot(cur, W709);

    // Read previous frame luma and motion EMA — own position only, no hazard
    float Y_prev  = (frame == 0) ? Y_cur  : imageLoad(PREV1, ipix).r;
    float M_avg   = (frame == 0) ? 0.0    : imageLoad(PREV2, ipix).r;

    float motion  = abs(Y_cur - Y_prev);

    // Update EMA of motion magnitude for this pixel
    float M_avg_new = mix(M_avg, motion, tmb_ema_alpha);

    // Transience: how much does current motion exceed its own history?
    // High → sudden/transient change (artifact) → blend
    // Low  → sustained motion (pan) or static → no blend
    float transience  = motion / (M_avg + 0.005);

    float motion_gate     = smoothstep(tmb_motion_lo,     tmb_motion_hi,     motion);
    float transience_gate = smoothstep(tmb_transience_lo, tmb_transience_hi, transience);
    float blend           = motion_gate * transience_gate * tmb_strength;

    // Spatial blur of current frame, scaled by blend factor.
    // Previous frame is used only as motion detector — its RGB never
    // touches the output, so no ghosting or color fringing is possible.
    // A 5-tap cross softens moving areas; wrong content but reads as blur.
    vec2 pt = 1.0 / HOOKED_size;
    vec3 spatial =
        HOOKED_tex(HOOKED_pos).rgb * 0.40 +
        HOOKED_tex(HOOKED_pos + vec2( pt.x, 0.0)).rgb * 0.15 +
        HOOKED_tex(HOOKED_pos + vec2(-pt.x, 0.0)).rgb * 0.15 +
        HOOKED_tex(HOOKED_pos + vec2(0.0,  pt.y)).rgb * 0.15 +
        HOOKED_tex(HOOKED_pos + vec2(0.0, -pt.y)).rgb * 0.15;
    vec3  rgb_out = clamp(mix(cur, spatial, blend), 0.0, 1.0);

    // Persist for next frame — own position only
    imageStore(PREV1, ipix, vec4(Y_cur,     0.0, 0.0, 1.0));
    imageStore(PREV2, ipix, vec4(M_avg_new, 0.0, 0.0, 1.0));

    return vec4(rgb_out, 1.0);
}

//!TEXTURE PREV1
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE

//!TEXTURE PREV2
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE
