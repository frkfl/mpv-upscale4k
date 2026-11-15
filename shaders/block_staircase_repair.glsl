//!PARAM bsr_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM bsr_grad_thr
//!TYPE float
//!MINIMUM 0.001
//!MAXIMUM 0.20
0.025

//!PARAM bsr_temporal_boost
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!HOOK MAIN
//!BIND HOOKED
//!BIND BSR_PREV
//!DESC [Custom] Block Staircase Repair

float luma(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

vec4 hook() {
    vec2  uv   = HOOKED_pos;
    vec2  px   = 1.0 / HOOKED_size;
    ivec2 ipos = ivec2(uv * HOOKED_size);

    vec3  cur   = HOOKED_tex(uv).rgb;
    float cur_Y = luma(cur);

    // Temporal boost (not gate): adds strength on cold-start / motion,
    // falls back to base on persistent stable staircases
    vec3  prev   = imageLoad(BSR_PREV, ipos).rgb;
    float motion = abs(cur_Y - luma(prev));
    float t_boost = 1.0 - bsr_temporal_boost * (1.0 - smoothstep(0.005, 0.04, motion));

    // Grid proximity: staircase steps fall on 8-pixel DCT block boundaries.
    // Covers ~3 pixels each side of boundary (smoothstep end at 0.45 of 0–0.5 range).
    float gx_frac    = float(ipos.x & 7);
    float gy_frac    = float(ipos.y & 7);
    float dist_bnd_x = min(gx_frac, 8.0 - gx_frac) / 8.0;
    float dist_bnd_y = min(gy_frac, 8.0 - gy_frac) / 8.0;
    float grid_prox  = 1.0 - smoothstep(0.0, 0.45, min(dist_bnd_x, dist_bnd_y));

    // 3x3 Sobel gradient
    float n  = luma(HOOKED_tex(uv + vec2(  0.0, -px.y)).rgb);
    float s  = luma(HOOKED_tex(uv + vec2(  0.0,  px.y)).rgb);
    float e  = luma(HOOKED_tex(uv + vec2( px.x,  0.0 )).rgb);
    float w  = luma(HOOKED_tex(uv + vec2(-px.x,  0.0 )).rgb);
    float ne = luma(HOOKED_tex(uv + vec2( px.x, -px.y)).rgb);
    float nw = luma(HOOKED_tex(uv + vec2(-px.x, -px.y)).rgb);
    float se = luma(HOOKED_tex(uv + vec2( px.x,  px.y)).rgb);
    float sw = luma(HOOKED_tex(uv + vec2(-px.x,  px.y)).rgb);

    float dx = (ne + 2.0*e + se) - (nw + 2.0*w + sw);
    float dy = (sw + 2.0*s + se) - (nw + 2.0*n + ne);
    float grad_mag  = length(vec2(dx, dy)) / 8.0;
    float edge_gate = smoothstep(bsr_grad_thr * 0.5, bsr_grad_thr * 2.0, grad_mag);

    // Activation: grid alignment × edge strength × overall strength.
    // Temporal modulates (boosts on motion, never blocks on static staircases).
    float activate = edge_gate * grid_prox * t_boost * bsr_strength;

    if (activate < 0.001) {
        imageStore(BSR_PREV, ipos, vec4(cur, 1.0));
        return vec4(cur, 1.0);
    }

    // Directional reconstruction along the true edge
    float inv_len = 1.0 / (length(vec2(dx, dy)) + 1e-6);
    vec2  edge_dir = vec2(-dy, dx) * inv_len;

    vec3 ea = HOOKED_tex(uv + edge_dir * px).rgb;
    vec3 eb = HOOKED_tex(uv - edge_dir * px).rgb;
    vec3 ec = HOOKED_tex(uv + edge_dir * px * 2.0).rgb;
    vec3 ed = HOOKED_tex(uv - edge_dir * px * 2.0).rgb;

    vec3 smooth_edge = cur * 0.40 + (ea + eb) * 0.20 + (ec + ed) * 0.10;

    vec3 out_rgb = mix(cur, smooth_edge, activate);
    out_rgb = clamp(out_rgb, 0.0, 1.0);

    imageStore(BSR_PREV, ipos, vec4(out_rgb, 1.0));
    return vec4(out_rgb, 1.0);
}

//!TEXTURE BSR_PREV
//!SIZE 1920 1080
//!FORMAT rgba16f
//!STORAGE
