//!PARAM fsrn_base
//!TYPE float
0.55

//!PARAM edge_boost
//!TYPE float
1.40

//!PARAM flat_protect
//!TYPE float
0.25

//!PARAM sigma_s
//!TYPE float
1.00

//!PARAM sigma_r
//!TYPE float
0.075

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Hybrid mix of learned upscale with structural reference

// Hybrid: tame learned upscaler ringing by mixing with an edge-preserving structural pass.
// Tuned for linear BT.2020 / BT.709 in float32 pipelines.

const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);
float luma(vec3 c) { return dot(c, LUMA_WEIGHTS); }

// Simple 3x3 bilateral filter (structure-preserving blur)
vec3 bilateral3x3(vec2 uv, vec2 px, float s_s, float s_r) {
    vec3 c0 = HOOKED_tex(uv).rgb;
    float L0 = luma(c0);
    float wsum = 0.0;
    vec3 acc = vec3(0.0);

    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 o = vec2(i, j) * px;
            vec3 c = HOOKED_tex(uv + o).rgb;
            float L = luma(c);
            float ds = length(vec2(i, j));
            float wr = exp(-0.5 * pow((L - L0) / max(s_r, 1e-6), 2.0));
            float ws = exp(-0.5 * pow(ds / max(s_s, 1e-6), 2.0));
            float w = wr * ws;
            wsum += w;
            acc += c * w;
        }
    }

    return acc / max(wsum, 1e-6);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Learned output (current upscaler result)
    vec3 fsrn = HOOKED_tex(uv).rgb;

    // Structural (edge-preserving) reference
    vec3 structural = bilateral3x3(uv, px, sigma_s, sigma_r);

    // Edge strength via luma gradient (phase-stable)
    float L = luma(fsrn);
    float gx = abs(dFdx(L));
    float gy = abs(dFdy(L));
    float grad = clamp(gx + gy, 0.0, 1.0);

    // Adaptive blend weight
    float w = clamp(fsrn_base + edge_boost * grad - flat_protect, 0.0, 1.0);

    // Mix structural with learned
    vec3 mixed = mix(structural, fsrn, w);
    return vec4(clamp(mixed, 0.0, 1.0), 1.0);
}
