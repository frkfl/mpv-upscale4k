//!PARAM chroma_thresh
//!TYPE float
0.16

//!PARAM chroma_soft
//!TYPE float
0.06

//!PARAM decision_strength
//!TYPE float
1.00

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC BT.601/709 → BT.2020 normalizer (auto)

// OkLab (Björn Ottosson), using linear RGB input
const mat3 OKLAB_M1 = mat3(
    0.4122214708, 0.5363325363, 0.0514459929,
    0.2119034982, 0.6806995451, 0.1073969566,
    0.0883024619, 0.2817188376, 0.6299787005
);
const mat3 OKLAB_M2 = mat3(
    0.2104542553,  0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050,  0.4505937099,
    0.0259040371,  0.7827717662, -0.8086757660
);

vec3 linear_to_oklab(vec3 c) {
    vec3 lms = pow(OKLAB_M1 * c, vec3(1.0 / 3.0));
    return OKLAB_M2 * lms;
}

// Correction matrices in linear BT.2020 space
// Corr_709_as_601: libplacebo assumed BT.709 but source was BT.601
const mat3 CORR_709_AS_601 = mat3(
    0.943900908, 0.0403665673, 0.0157325244,
    0.0233725474, 0.9595007930, 0.0171266597,
   -0.0008264745,-0.0070981000, 1.0079245700
);

// Corr_601_as_709: libplacebo assumed BT.601 but source was BT.709
const mat3 CORR_601_AS_709 = mat3(
    1.0605270900,-0.0447336179,-0.0157934743,
   -0.0258457274, 1.0431678200,-0.0173220915,
    0.0006875942, 0.0073096128, 0.9920027930
);

// Per-candidate plausibility metric: penalize excess chroma in mid-lightness
float chroma_penalty(vec3 rgb_lin, float chroma_thresh, float chroma_soft) {
    rgb_lin = clamp(rgb_lin, 0.0, 1.0);
    vec3 lab = linear_to_oklab(rgb_lin);
    float L = lab.x;
    float C = length(lab.yz);

    // Focus on mid-lightness, where oversaturation is most noticeable
    float wL = smoothstep(0.15, 0.5, L) * (1.0 - smoothstep(0.6, 0.9, L));

    float t = max(C - chroma_thresh, 0.0);
    float s = max(chroma_soft, 1e-4);
    float p = (t * t) / (s * s);

    // Also discourage extreme negative channels after matrixing
    float under = max(-min(min(rgb_lin.r, rgb_lin.g), rgb_lin.b), 0.0);
    p += under * 4.0;

    return wL * p;
}

vec4 hook() {
    vec3 rgb_in = HOOKED_tex(HOOKED_pos).rgb; // linear BT.2020

    // Candidates:
    // c0: metadata assumed correct
    // c1: assumed BT.709, actually BT.601
    // c2: assumed BT.601, actually BT.709
    vec3 c0 = rgb_in;
    vec3 c1 = CORR_709_AS_601 * rgb_in;
    vec3 c2 = CORR_601_AS_709 * rgb_in;

    // Compute penalties
    float p0 = chroma_penalty(c0, chroma_thresh, chroma_soft);
    float p1 = chroma_penalty(c1, chroma_thresh, chroma_soft);
    float p2 = chroma_penalty(c2, chroma_thresh, chroma_soft);

    // Push decision slightly towards "no correction" for low-strength settings
    float k = clamp(decision_strength, 0.0, 1.0);
    p1 *= mix(1.2, 1.0, k);
    p2 *= mix(1.2, 1.0, k);

    vec3 out_rgb = c0;
    float best = p0;

    if (p1 < best) {
        best = p1;
        out_rgb = c1;
    }
    if (p2 < best) {
        best = p2;
        out_rgb = c2;
    }

    out_rgb = clamp(out_rgb, 0.0, 1.0);
    return vec4(out_rgb, 1.0);
}
