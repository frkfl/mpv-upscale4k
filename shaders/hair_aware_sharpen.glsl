//!PARAM sharp_amt
//!TYPE float
0.28

//!PARAM hf_gain
//!TYPE float
1.60

//!PARAM flat_guard
//!TYPE float
0.85

//!PARAM temp_sense
//!TYPE float
0.65

//!PARAM clamp_amt
//!TYPE float
0.030

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Hair-aware adaptive sharpen (temporal + HF mask)

// Luma weights (BT.709)
const vec3 LW = vec3(0.299, 0.587, 0.114);

// Luma helper
float luma(vec3 c) { return dot(c, LW); }

// High-frequency mask (grad + band-pass) from current frame
float hf_mask(vec2 uv) {
    vec2 px = 1.0 / HOOKED_size.xy;

    float c  = luma(HOOKED_tex(uv).rgb);
    float sx = abs(luma(HOOKED_tex(uv + vec2( px.x, 0.0)).rgb) -
                   luma(HOOKED_tex(uv + vec2(-px.x, 0.0)).rgb));
    float sy = abs(luma(HOOKED_tex(uv + vec2(0.0,  px.y)).rgb) -
                   luma(HOOKED_tex(uv + vec2(0.0, -px.y)).rgb));
    float g  = clamp((sx + sy) * 2.0, 0.0, 1.0);

    // 4-neighbor laplacian band-pass
    float lap = 0.0;
    lap += luma(HOOKED_tex(uv + vec2( px.x, 0.0)).rgb);
    lap += luma(HOOKED_tex(uv + vec2(-px.x, 0.0)).rgb);
    lap += luma(HOOKED_tex(uv + vec2(0.0,  px.y)).rgb);
    lap += luma(HOOKED_tex(uv + vec2(0.0, -px.y)).rgb);
    lap -= 4.0 * c;

    float bp = clamp(abs(lap) * 4.0, 0.0, 1.0);
    return clamp(mix(g, bp, 0.6), 0.0, 1.0);
}

// Temporal stability from current vs previous frame
float temporal_stability(vec2 uv) {
    float c = luma(HOOKED_tex(uv).rgb);
    float p = luma(PREV_tex(uv).rgb);
    float d = abs(c - p);
    return 1.0 - clamp(d * 8.0, 0.0, 1.0); // small diffs → stable
}

// 3x3 unsharp detail signal (current frame)
vec3 unsharp3x3(vec2 uv) {
    vec2 px = 1.0 / HOOKED_size.xy;

    vec3 b = vec3(0.0);
    b += HOOKED_tex(uv + px * vec2(-1.0, -1.0)).rgb * 1.0;
    b += HOOKED_tex(uv + px * vec2( 0.0, -1.0)).rgb * 2.0;
    b += HOOKED_tex(uv + px * vec2( 1.0, -1.0)).rgb * 1.0;

    b += HOOKED_tex(uv + px * vec2(-1.0,  0.0)).rgb * 2.0;
    b += HOOKED_tex(uv + px * vec2( 0.0,  0.0)).rgb * 4.0;
    b += HOOKED_tex(uv + px * vec2( 1.0,  0.0)).rgb * 2.0;

    b += HOOKED_tex(uv + px * vec2(-1.0,  1.0)).rgb * 1.0;
    b += HOOKED_tex(uv + px * vec2( 0.0,  1.0)).rgb * 2.0;
    b += HOOKED_tex(uv + px * vec2( 1.0,  1.0)).rgb * 1.0;

    b *= (1.0 / 16.0);
    vec3 c = HOOKED_tex(uv).rgb;
    return c - b; // detail = current - blur
}

vec4 hook() {
    vec2 uv   = HOOKED_pos;
    vec3 base = HOOKED_tex(uv).rgb;

    // High-frequency mask and temporal stability
    float hf   = hf_mask(uv);
    float stab = temporal_stability(uv);

    // Weight favors HF regions that are temporally stable
    float w = hf * hf_gain * mix(0.0, 1.0, pow(stab, temp_sense));
    w = clamp(w, 0.0, 1.5);

    // Protect flat regions
    w = mix(w, 0.0, flat_guard * (1.0 - hf));

    // Detail signal with clamp
    vec3 detail = unsharp3x3(uv);
    vec3 add = clamp(detail, vec3(-clamp_amt), vec3(clamp_amt));

    // Apply sharpening
    vec3 outc = base + add * (sharp_amt * w);
    return vec4(outc, 1.0);
}
