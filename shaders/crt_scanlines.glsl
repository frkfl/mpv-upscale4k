// CRT scanlines - symmetric luma alternation with temporal phase shift.
//
// Unlike a darkening-only approach, this alternates: one row is boosted,
// the adjacent row is dimmed by the same amount. Average luma is preserved
// exactly. The brain receives both a positive and negative reference
// simultaneously, which registers as a structural grid, not as noise or
// a global darkening.
//
// Temporal: the phase inverts every frame (bright row becomes dark row).
// At 60fps this is 30Hz per line - above flicker fusion, integrates as
// an organic texture rather than a static visible stripe.
//
// sl_amplitude: swing around 1.0. 0.0 = no effect.
//   bright rows: *= (1 + sl_amplitude)
//   dark rows:   *= (1 - sl_amplitude)
//   mean:        unchanged
// sl_period: rows per cycle (pixels at current resolution, default 4.0)

//!PARAM sl_amplitude
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.5
0.20

//!PARAM sl_period
//!TYPE float
//!MINIMUM 2.0
//!MAXIMUM 12.0
4.0

//!PARAM sl_display_height
//!TYPE float
//!MINIMUM 720.0
//!MAXIMUM 4320.0
2160.0

//!PARAM sl_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!PARAM sl_dark
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!PARAM sl_mid
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!PARAM sl_bright
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [CRT] Scanlines symmetric

#define frame_count  frame

vec4 hook() {
    vec4 col = HOOKED_tex(HOOKED_pos);
    const vec3 W709 = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(col.rgb, W709);

    // Spatially smoothed luma for the gate — 5-tap cross at period distance.
    // Adjacent pixels on the same surface share nearly the same blurred luma,
    // so they get nearly the same gate value. Prevents the arm inconsistency
    // where one side has full effect and the other has none.
    vec2 ppt = vec2(sl_period / HOOKED_size.x, sl_period / HOOKED_size.y);
    float luma_s = (luma
        + dot(HOOKED_tex(HOOKED_pos + vec2( ppt.x,  0.0)).rgb, W709)
        + dot(HOOKED_tex(HOOKED_pos + vec2(-ppt.x,  0.0)).rgb, W709)
        + dot(HOOKED_tex(HOOKED_pos + vec2( 0.0,  ppt.y)).rgb, W709)
        + dot(HOOKED_tex(HOOKED_pos + vec2( 0.0, -ppt.y)).rgb, W709)
    ) / 5.0;

    // Parabolic luma gate — rule-based, no parameters.
    // Peak at luma=0.5, tapers smoothly to zero at 0 and 1.
    // 2*sqrt(l*(1-l)): at 0.5->1.0, at 0.7->0.92, at 0.8->0.80, at 0.9->0.60
    // No hard cutoff: light areas still get some effect, just less.
    float luma_gate = 2.0 * sqrt(max(luma_s * (1.0 - luma_s), 0.0));

    // Content contrast gate — suppress where the image already has strong
    // vertical variation at the scanline scale (wing patterns, hard edges).
    float half_p = (norm_period * 0.5) / HOOKED_size.y;
    float luma_above = dot(HOOKED_tex(HOOKED_pos + vec2(0.0,  half_p)).rgb, W709);
    float luma_below = dot(HOOKED_tex(HOOKED_pos + vec2(0.0, -half_p)).rgb, W709);
    float contrast      = abs(luma_above - luma_below);
    float contrast_gate = 1.0 - smoothstep(0.08, 0.25, contrast);

    // Three-band zone strength — tent functions that sum to 1.0.
    // dark peaks at luma 0.0, mid peaks at 0.5, bright peaks at 1.0.
    // Each zone blends smoothly into its neighbors, no hard boundaries.
    float w_dark   = clamp(1.0 - 2.0 * luma_s,        0.0, 1.0);
    float w_bright = clamp(2.0 * luma_s - 1.0,        0.0, 1.0);
    float w_mid    = 1.0 - w_dark - w_bright;
    float zone     = w_dark * sl_dark + w_mid * sl_mid + w_bright * sl_bright;

    float gate = luma_gate * contrast_gate * zone * sl_strength;

    // Normalize period to display resolution.
    // sl_period is specified in display pixels (e.g. 4 at 2160p).
    // When the shader runs at a lower HOOKED resolution, scale down
    // so the display scaler produces the intended period at output.
    // Clamped to 1.0: below that, every row alternates (finest possible).
    float norm_period = max(1.0, sl_period * HOOKED_size.y / sl_display_height);

    // Cosine wave with per-frame phase flip
    float py = HOOKED_pos.y * HOOKED_size.y;
    float frame_phase = mod(float(frame_count), 2.0) * (norm_period * 0.5);
    float wave = cos((py + frame_phase) * (2.0 * 3.14159265) / norm_period);

    col.rgb *= 1.0 + sl_amplitude * wave * gate;

    return vec4(clamp(col.rgb, 0.0, 1.0), col.a);
}
