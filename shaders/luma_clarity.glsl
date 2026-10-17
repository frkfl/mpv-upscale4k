// Luma Clarity — mid-frequency local contrast enhancement.
//
// Large-radius unsharp mask on the luma channel only.
// Enhances the 3D form and surface variation (faces, folds, depth) without
// sharpening edges or adding color shifts.
//
// This is the complement to downscale-remaster smoothing: the remaster calms
// high-frequency chaos; clarity brings back the mid-frequency "opinion" on luma
// that makes surfaces feel solid rather than flat.
//
// lc_strength: 0.0 = off, 0.25 = subtle punch, 0.5 = strong.
// lc_radius:   feature scale in output pixels. 6 = skin texture, 12 = face form.

//!PARAM lc_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.95

//!PARAM lc_radius
//!TYPE float
//!MINIMUM 2.0
//!MAXIMUM 24.0
8.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Luma clarity (mid-frequency local contrast)

float luma(vec3 c) { return dot(c, vec3(0.2627, 0.6780, 0.0593)); }

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;
    vec2 r  = lc_radius * px;

    vec3 c = HOOKED_tex(uv).rgb;

    // 8-direction star blur at lc_radius pixels — reference for "local average".
    // Weighted so diagonal taps count less (they are farther: radius * sqrt(2)).
    vec3 blur = c;
    blur += HOOKED_tex(uv + r * vec2( 0.0,  1.0)).rgb;
    blur += HOOKED_tex(uv + r * vec2( 0.0, -1.0)).rgb;
    blur += HOOKED_tex(uv + r * vec2( 1.0,  0.0)).rgb;
    blur += HOOKED_tex(uv + r * vec2(-1.0,  0.0)).rgb;
    blur += HOOKED_tex(uv + r * vec2( 1.0,  1.0)).rgb * 0.707;
    blur += HOOKED_tex(uv + r * vec2( 1.0, -1.0)).rgb * 0.707;
    blur += HOOKED_tex(uv + r * vec2(-1.0,  1.0)).rgb * 0.707;
    blur += HOOKED_tex(uv + r * vec2(-1.0, -1.0)).rgb * 0.707;
    blur /= (1.0 + 4.0 + 4.0 * 0.707);

    // Luma-only difference: how much this pixel deviates from its local average.
    float Y_c    = luma(c);
    float Y_blur = luma(blur);
    float diff_Y = Y_c - Y_blur;

    // Soft gate: don't boost pixels that are already at the local average
    // (pure flat areas get nothing; areas with some variation get the lift).
    float gate = smoothstep(0.005, 0.025, abs(diff_Y));

    // Add the luma deviation back — same delta to all channels = no hue shift.
    vec3 out_rgb = c + vec3(diff_Y * lc_strength * gate);
    return vec4(clamp(out_rgb, 0.0, 1.0), HOOKED_tex(uv).a);
}