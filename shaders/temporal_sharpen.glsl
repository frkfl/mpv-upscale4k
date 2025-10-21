
//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Temporal Sharpen (motion-aware, halo-clamped)
//!PARAM float strength = 0.25   // 0..0.6  base sharpen amount
//!PARAM float motion_sense = 0.60 // 0..1  reduce sharpen on motion (higher = calmer)
//!PARAM float decay = 0.80      // 0..1   temporal blend decay for the HF term
//!PARAM float radius = 1.00     // 0.5..2 sample radius in pixels
//!PARAM float clamp_amt = 0.030 // 0..0.1 limit to prevent halos
//!PARAM float thresh = 0.020    // 0..0.1 ignore micro noise
//!PARAM float gamma_in = 2.20   // approximate source gamma
//!PARAM float gamma_out = 2.20  // display gamma

// Utilities
float luma(vec3 c){ return dot(c, vec3(0.2126,0.7152,0.0722)); }
vec3 toLin(vec3 c, float g){ return pow(max(c,0.0), vec3(g>0.0? 1.0/g : 1.0)); }
vec3 toGam(vec3 c, float g){ return pow(max(c,0.0), vec3(g>0.0? g : 1.0)); }

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Fetch current / previous in linear light
    vec3 cur = toLin(HOOKED_tex(uv).rgb, gamma_in);
    vec3 prv = toLin(PREV_tex(uv).rgb,   gamma_in);

    // 3x3 unsharp (small radius) to get a HF detail signal
    float r = radius;
    vec3 c  = cur;
    vec3 n  = toLin(HOOKED_tex(uv + vec2(0.0, -px.y*r)).rgb, gamma_in);
    vec3 s  = toLin(HOOKED_tex(uv + vec2(0.0,  px.y*r)).rgb, gamma_in);
    vec3 e  = toLin(HOOKED_tex(uv + vec2( px.x*r, 0.0)).rgb, gamma_in);
    vec3 w  = toLin(HOOKED_tex(uv + vec2(-px.x*r, 0.0)).rgb, gamma_in);
    vec3 ne = toLin(HOOKED_tex(uv + vec2( px.x*r, -px.y*r)).rgb, gamma_in);
    vec3 nw = toLin(HOOKED_tex(uv + vec2(-px.x*r, -px.y*r)).rgb, gamma_in);
    vec3 se = toLin(HOOKED_tex(uv + vec2( px.x*r,  px.y*r)).rgb, gamma_in);
    vec3 sw = toLin(HOOKED_tex(uv + vec2(-px.x*r,  px.y*r)).rgb, gamma_in);

    vec3 blur = (n+s+e+w+ne+nw+se+sw + c)* (1.0/9.0); // small, isotropic
    vec3 hf   = c - blur;                              // high-frequency component

    // Noise thresholding (keep structure, ignore codec speckle)
    float yl = luma(c);
    float hfl = luma(abs(hf));
    float gate = smoothstep(thresh, 3.0*thresh, hfl);  // 0..1

    // Simple motion mask using prev frame (in linear light, so differences are meaningful)
    float m = abs(luma(c) - luma(prv));                // 0..~1
    float calm = 1.0 - clamp(motion_sense * smoothstep(0.004, 0.020, m), 0.0, 1.0);

    // Temporal accumulation of the HF term to stabilize over time (TXAA-ish)
    // Recompute previous HF from prev frame neighborhood (cheap proxy via single blur)
    vec3 p_n  = toLin(PREV_tex(uv + vec2(0.0, -px.y*r)).rgb, gamma_in);
    vec3 p_s  = toLin(PREV_tex(uv + vec2(0.0,  px.y*r)).rgb, gamma_in);
    vec3 p_e  = toLin(PREV_tex(uv + vec2( px.x*r, 0.0)).rgb, gamma_in);
    vec3 p_w  = toLin(PREV_tex(uv + vec2(-px.x*r, 0.0)).rgb, gamma_in);
    vec3 p_ne = toLin(PREV_tex(uv + vec2( px.x*r,-px.y*r)).rgb, gamma_in);
    vec3 p_nw = toLin(PREV_tex(uv + vec2(-px.x*r,-px.y*r)).rgb, gamma_in);
    vec3 p_se = toLin(PREV_tex(uv + vec2( px.x*r, px.y*r)).rgb, gamma_in);
    vec3 p_sw = toLin(PREV_tex(uv + vec2(-px.x*r, px.y*r)).rgb, gamma_in);
    vec3 p_blur = (p_n+p_s+p_e+p_w+p_ne+p_nw+p_se+p_sw + prv)*(1.0/9.0);
    vec3 p_hf   = prv - p_blur;

    vec3 hf_temporal = mix(hf, p_hf, decay); // decay<1 biases toward current

    // Halo clamp: limit sharpen contribution per-channel relative to local contrast
    vec3 limit = clamp_amt * (abs(c - blur) + 1e-4);
    vec3 add   = clamp(hf_temporal, -limit, limit)
               * (strength * gate * calm);

    vec3 out_lin = c + add;

    return vec4(toGam(out_lin, gamma_out), 1.0);
}
