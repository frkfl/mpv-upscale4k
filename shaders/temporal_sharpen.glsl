//!PARAM strength
//!TYPE float
0.25

//!PARAM motion_sense
//!TYPE float
0.60

//!PARAM decay
//!TYPE float
0.80

//!PARAM radius
//!TYPE float
1.00

//!PARAM clamp_amt
//!TYPE float
0.030

//!PARAM thresh
//!TYPE float
0.020

//!PARAM gamma_in
//!TYPE float
2.20

//!PARAM gamma_out
//!TYPE float
2.20

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV_FRAME
//!SAVE PREV_FRAME
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h
//!DESC [Custom] Temporal Sharpen

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 toLin(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? 1.0 / g : 1.0));
}

vec3 toGam(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? g : 1.0));
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    vec3 cur = toLin(HOOKED_tex(uv).rgb, gamma_in);

    // On first frame PREV_FRAME is undefined → fallback to current
    vec3 prv = toLin(PREV_FRAME_tex(uv).rgb, gamma_in);
    if (frame == 0) {
        prv = cur;
    }

    float r = radius;
    vec3 c  = cur;

    vec3 n  = toLin(HOOKED_tex(uv + vec2(0.0, -px.y * r)).rgb, gamma_in);
    vec3 s  = toLin(HOOKED_tex(uv + vec2(0.0,  px.y * r)).rgb, gamma_in);
    vec3 e  = toLin(HOOKED_tex(uv + vec2( px.x * r, 0.0)).rgb, gamma_in);
    vec3 w  = toLin(HOOKED_tex(uv + vec2(-px.x * r, 0.0)).rgb, gamma_in);
    vec3 ne = toLin(HOOKED_tex(uv + vec2( px.x * r, -px.y * r)).rgb, gamma_in);
    vec3 nw = toLin(HOOKED_tex(uv + vec2(-px.x * r, -px.y * r)).rgb, gamma_in);
    vec3 se = toLin(HOOKED_tex(uv + vec2( px.x * r,  px.y * r)).rgb, gamma_in);
    vec3 sw = toLin(HOOKED_tex(uv + vec2(-px.x * r,  px.y * r)).rgb, gamma_in);

    vec3 blur = (n + s + e + w + ne + nw + se + sw + c) * (1.0 / 9.0);
    vec3 hf   = c - blur;

    float hfl  = luma(abs(hf));
    float gate = smoothstep(thresh, 3.0 * thresh, hfl);

    float m = abs(luma(c) - luma(prv));
    float calm = 1.0 - clamp(motion_sense * smoothstep(0.004, 0.020, m), 0.0, 1.0);

    vec3 p_n  = toLin(PREV_FRAME_tex(uv + vec2(0.0, -px.y * r)).rgb, gamma_in);
    vec3 p_s  = toLin(PREV_FRAME_tex(uv + vec2(0.0,  px.y * r)).rgb, gamma_in);
    vec3 p_e  = toLin(PREV_FRAME_tex(uv + vec2( px.x * r, 0.0)).rgb, gamma_in);
    vec3 p_w  = toLin(PREV_FRAME_tex(uv + vec2(-px.x * r, 0.0)).rgb, gamma_in);
    vec3 p_ne = toLin(PREV_FRAME_tex(uv + vec2( px.x * r, -px.y * r)).rgb, gamma_in);
    vec3 p_nw = toLin(PREV_FRAME_tex(uv + vec2(-px.x * r, -px.y * r)).rgb, gamma_in);
    vec3 p_se = toLin(PREV_FRAME_tex(uv + vec2( px.x * r,  px.y * r)).rgb, gamma_in);
    vec3 p_sw = toLin(PREV_FRAME_tex(uv + vec2(-px.x * r,  px.y * r)).rgb, gamma_in);

    vec3 p_blur = (p_n + p_s + p_e + p_w + p_ne + p_nw + p_se + p_sw + prv) * (1.0 / 9.0);
    vec3 p_hf   = prv - p_blur;

    vec3 hf_temporal = mix(hf, p_hf, decay);

    vec3 limit = clamp_amt * (abs(c - blur) + 1e-4);
    vec3 add   = clamp(hf_temporal, -limit, limit) * (strength * gate * calm);

    vec3 out_lin = c + add;

    return vec4(toGam(out_lin, gamma_out), 1.0);
}
