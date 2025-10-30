//!PARAM gx_thresh
//!TYPE float
0.05
//!PARAM gy_thresh
//!TYPE float
0.20
//!PARAM alpha_base
//!TYPE float
0.25
//!PARAM luma_gate_lo
//!TYPE float
0.05
//!PARAM luma_gate_hi
//!TYPE float
0.90
//!PARAM luma_gate_strength
//!TYPE float
0.00
//!PARAM phase_offset_px
//!TYPE float
0.0
//!PARAM blur_sigma
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV1
//!BIND PREV2
//!DESC 🎛️ Temporal Stabilizer — Deterministic (horizontal ringing suppression)

const float EPS = 1e-7;
const vec3  W709 = vec3(0.2126, 0.7152, 0.0722); // BT.709 luma

// 3-tap separable kernel for optional mid-band limit (σ∈[0,1], 0=bypass)
vec3 gauss3(float sigma) {
    sigma = clamp(sigma, 0.0, 1.0);
    float a = mix(0.0, 0.25, sigma);
    float b = 1.0 - 2.0 * a;
    return vec3(a, b, a);
}

// Previous-frame luma fetch with vertical sub-pixel phase offset in **pixels**
float prev_luma(ivec2 ipix, float phase_px) {
    float fy = fract(phase_px);
    int   oy = int(floor(phase_px));
    ivec2 p0 = ipix + ivec2(0, oy);
    vec4 s0 = imageLoad(PREV1, p0);   // r16f -> vec4
    if (fy == 0.0) return s0.r;
    ivec2 p1 = ipix + ivec2(0, oy + 1);
    vec4 s1 = imageLoad(PREV1, p1);
    return mix(s0.r, s1.r, fy);
}

vec4 hook() {
    // Source in linear light
    vec4 src_lin = linearize(HOOKED_tex(HOOKED_pos));
    vec3 rgb     = src_lin.rgb;

    // Integer pixel coords (match HOOKED)
    ivec2 ipix = ivec2(floor(HOOKED_pos * HOOKED_size));

    // Current luma (reference, unblurred for gradients)
    float Y_now = dot(rgb, W709);

    // Optional small separable blur to confine to mid-band (sub-band limit)
    float Yt = Y_now;
    if (blur_sigma > 0.0) {
        vec3 w = gauss3(blur_sigma);
        float Yx = w.x * dot(linearize(HOOKED_tex(HOOKED_pos + vec2(-HOOKED_pt.x, 0.0))).rgb, W709)
                 + w.y * Yt
                 + w.z * dot(linearize(HOOKED_tex(HOOKED_pos + vec2(+HOOKED_pt.x, 0.0))).rgb, W709);
        float Yy = w.x * dot(linearize(HOOKED_tex(HOOKED_pos + vec2(0.0, -HOOKED_pt.y))).rgb, W709)
                 + w.y * Yx
                 + w.z * dot(linearize(HOOKED_tex(HOOKED_pos + vec2(0.0, +HOOKED_pt.y))).rgb, W709);
        Yt = Yy;
    }

    // Previous frame luma (self for frame 0)
    float Yt_1 = (frame == 0) ? Yt : prev_luma(ipix, phase_offset_px);

    // (1) Luma difference map
    float dy = abs(Yt - Yt_1);

    // (2) Edge gate: horizontal detail (gx) but not vertical edge (gy)
    float gx = abs(dFdx(Y_now));
    float gy = abs(dFdy(Y_now));
    float candidate = (gy < gy_thresh && gx > gx_thresh) ? 1.0 : 0.0;

    // (3) Temporal coherence: running average of |dy| over ~3 frames (IIR α=1/3)
    float dy_avg_prev = (frame == 0) ? 0.0 : imageLoad(PREV2, ipix).r;
    float dy_avg      = mix(dy_avg_prev, dy, 0.33333334);
    float stable      = smoothstep(0.02, 0.06, abs(dy_avg - dy));

    // Adaptive EMA weight
    float alpha = alpha_base * stable * candidate;

    // Optional luma-weighted gating (preserve bright edges)
    if (luma_gate_strength > 0.0) {
        float w = smoothstep(luma_gate_lo, luma_gate_hi, clamp(Yt, 0.0, 1.0));
        alpha  *= mix(1.0, w, clamp(luma_gate_strength, 0.0, 1.0));
    }
    alpha = clamp(alpha, 0.0, 1.0);

    // Directional temporal EMA (prev-only) per spec
    float Yout = mix(Yt, mix(Yt, Yt_1, 0.5), alpha);

    // Chroma preservation by luma-matched scaling
    float Y_src = max(dot(rgb, W709), EPS);
    float scale = Yout / Y_src;
    vec3  rgb_out = rgb * scale;

    // Persist states for next frame
    imageStore(PREV1, ipix, vec4(Yt, 0.0, 0.0, 1.0));     // current (possibly mid-band) luma
    imageStore(PREV2, ipix, vec4(dy_avg, 0.0, 0.0, 1.0)); // running |dy| average

    // Output (back to display transfer)
    vec3 out_nl = delinearize(vec4(clamp(rgb_out, vec3(0.0), vec3(1e6)), 1.0)).rgb;
    return vec4(out_nl, HOOKED_tex(HOOKED_pos).a);
}

// Persistent storage images (nlmeans style, declared at end)
//!TEXTURE PREV1
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE

//!TEXTURE PREV2
//!SIZE 3840 3840
//!FORMAT r16f
//!STORAGE
