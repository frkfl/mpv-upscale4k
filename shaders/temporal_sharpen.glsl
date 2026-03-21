//!PARAM tsh_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.35

//!PARAM tsh_radius
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 3.0
1.0

//!HOOK MAIN
//!BIND HOOKED
//!BIND TSH_PREV
//!SAVE MAIN
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h
//!DESC [Custom] Temporal Sharpen

float luma(vec3 c) {
    // BT.2020 coefficients
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

vec3 gaussBlur(vec2 uv, vec2 px, float r) {
    vec3 c  = HOOKED_tex(uv).rgb;
    vec3 n  = HOOKED_tex(uv + vec2( 0.0,      -px.y*r)).rgb;
    vec3 s  = HOOKED_tex(uv + vec2( 0.0,       px.y*r)).rgb;
    vec3 e  = HOOKED_tex(uv + vec2( px.x*r,    0.0   )).rgb;
    vec3 w  = HOOKED_tex(uv + vec2(-px.x*r,    0.0   )).rgb;
    vec3 ne = HOOKED_tex(uv + vec2( px.x*r,   -px.y*r)).rgb;
    vec3 nw = HOOKED_tex(uv + vec2(-px.x*r,   -px.y*r)).rgb;
    vec3 se = HOOKED_tex(uv + vec2( px.x*r,    px.y*r)).rgb;
    vec3 sw = HOOKED_tex(uv + vec2(-px.x*r,    px.y*r)).rgb;
    return c  * 0.375
         + (n + s + e + w)     * 0.125
         + (ne + nw + se + sw) * 0.0625;
}

vec3 gaussBlurPrev(ivec2 ipos, float r) {
    ivec2 ir = ivec2(round(vec2(r)));
    vec3 c  = imageLoad(TSH_PREV, ipos).rgb;
    vec3 n  = imageLoad(TSH_PREV, ipos + ivec2( 0,      -ir.y)).rgb;
    vec3 s  = imageLoad(TSH_PREV, ipos + ivec2( 0,       ir.y)).rgb;
    vec3 e  = imageLoad(TSH_PREV, ipos + ivec2( ir.x,    0   )).rgb;
    vec3 w  = imageLoad(TSH_PREV, ipos + ivec2(-ir.x,    0   )).rgb;
    vec3 ne = imageLoad(TSH_PREV, ipos + ivec2( ir.x,   -ir.y)).rgb;
    vec3 nw = imageLoad(TSH_PREV, ipos + ivec2(-ir.x,   -ir.y)).rgb;
    vec3 se = imageLoad(TSH_PREV, ipos + ivec2( ir.x,    ir.y)).rgb;
    vec3 sw = imageLoad(TSH_PREV, ipos + ivec2(-ir.x,    ir.y)).rgb;
    return c  * 0.375
         + (n + s + e + w)     * 0.125
         + (ne + nw + se + sw) * 0.0625;
}

vec4 hook() {
    vec2  uv   = HOOKED_pos;
    vec2  px   = 1.0 / HOOKED_size;
    ivec2 ipos = ivec2(uv * HOOKED_size);

    vec3 cur = HOOKED_tex(uv).rgb;
    vec3 prv = imageLoad(TSH_PREV, ipos).rgb;

    vec3 blur_cur = gaussBlur(uv, px, tsh_radius);
    vec3 blur_prv = gaussBlurPrev(ipos, tsh_radius);

    vec3 hf_cur = cur - blur_cur;
    vec3 hf_prv = prv - blur_prv;

    vec3 hf = mix(hf_cur, hf_prv, 0.4);

    float m    = abs(luma(cur) - luma(prv));
    float calm = 1.0 - smoothstep(0.004, 0.025, m);

    vec3 limit = 0.05 * (abs(hf_cur) + 1e-4);
    vec3 add   = clamp(hf, -limit, limit) * (tsh_strength * calm);

    vec3 out_rgb = clamp(cur + add, 0.0, 1.0);

    imageStore(TSH_PREV, ipos, vec4(out_rgb, 1.0));
    return vec4(out_rgb, 1.0);
}

//!TEXTURE TSH_PREV
//!SIZE 3840 2160
//!FORMAT rgba16f
//!STORAGE