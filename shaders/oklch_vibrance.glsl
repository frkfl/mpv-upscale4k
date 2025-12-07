//!PARAM vibrance
//!TYPE float
0.18

//!PARAM skin_protect
//!TYPE float
0.60

//!PARAM skin_hue
//!TYPE float
0.07

//!PARAM skin_width
//!TYPE float
0.06

//!PARAM mid_bias
//!TYPE float
0.20

//!PARAM gamma_in
//!TYPE float
1.0

//!PARAM gamma_out
//!TYPE float
1.0

//!PARAM chroma_tame
//!TYPE float
0.15

//!HOOK MAIN
//!BIND HOOKED
//!DESC OkLCH cinema-style vibrance (HDR-safe, skin-protected, chroma-tamed)

// Small epsilon to keep cube roots happy
const float EPS = 1e-6;
const float PI  = 3.14159265358979323846;

// --- OkLab transforms (linear RGB only) ---
// GLSL mat3 is column-major: mat3(c0, c1, c2) with columns = vec3s.

// Linear sRGB -> LMS
const mat3 M1 = mat3(
    0.4122214708, 0.2119034982, 0.0883024619,  // column 0
    0.5363325363, 0.6806995451, 0.2817188376,  // column 1
    0.0514459929, 0.1073969566, 0.6299787005   // column 2
);

// LMS^(1/3) -> OkLab
const mat3 M2 = mat3(
    0.2104542553,  1.9779984951,  0.0259040371,  // column 0
    0.7936177850, -2.4285922050,  0.7827717662,  // column 1
   -0.0040720468,  0.4505937099, -0.8086757660   // column 2
);

// OkLab -> linear sRGB
const mat3 Mi = mat3(
    4.0767416621, -1.2684380046,  0.0041960863,  // column 0
   -3.3077115913,  2.6097574011, -0.7034186147,  // column 1
    0.2309699292, -0.3413193965,  1.6996226760   // column 2
);

vec3 linear_srgb_to_oklab(vec3 c) {
    vec3 lms = M1 * c;
    lms = pow(max(lms, vec3(EPS)), vec3(1.0 / 3.0));
    return M2 * lms;
}

vec3 oklab_to_linear_srgb(vec3 LLab) {
    float L = LLab.x;
    float a = LLab.y;
    float b = LLab.z;

    float l = L + 0.3963377774 * a + 0.2158037573 * b;
    float m = L - 0.1055613458 * a - 0.0638541728 * b;
    float s = L - 0.0894841775 * a - 1.2914855480 * b;

    l = l * l * l;
    m = m * m * m;
    s = s * s * s;

    return Mi * vec3(l, m, s);
}

// Simple hue extraction in encoded space (good for skin hue tuning)
float safe_hue(vec3 c) {
    float M = max(max(c.r, c.g), c.b);
    float m = min(min(c.r, c.g), c.b);
    float C = max(M - m, EPS);
    vec3 n = (c - m) / C;
    float h = (M == c.r) ? (n.g - n.b)
            : (M == c.g) ? (2.0 + n.b - n.r)
                         : (4.0 + n.r - n.g);
    return fract(h / 6.0); // 0..1
}

vec4 hook() {
    // Source in pipeline encoding (could be SDR or HDR)
    vec4 src = HOOKED_tex(HOOKED_pos);

    // Linearize using libplacebo helper (handles SDR/HDR correctly)
    vec3 lin = linearize(src).rgb;
    vec3 lin_clamped = max(lin, vec3(EPS));

    // Convert to OkLab
    vec3 lab = linear_srgb_to_oklab(lin_clamped);
    float L = lab.x;
    float a = lab.y;
    float b = lab.z;

    // --- Optional OkLab-L contrast shaping (gamma_in/out) ---
    // Gentle, perceptual contrast on L. With gamma_in=gamma_out=1.0, this is a no-op.
    float g_in  = max(gamma_in,  0.01);
    float g_out = max(gamma_out, 0.01);

    float L_norm    = clamp(L, 0.0, 1.0);
    float L_shaped  = pow(pow(L_norm, 1.0 / g_in), g_out);
    L = mix(L, L_shaped, 0.5);  // 0.5 keeps it subtle; adjust if you want stronger effect.

    // Re-pack L for later use
    lab.x = L;

    // Convert to OkLCH
    float C = length(vec2(a, b));
    float H = atan(b, a);  // radians, -pi..pi

    // --- Cinema-style vibrance shaping ---

    // 1) Lightness gate: favor midtones
    float l_lo  = smoothstep(0.08, 0.30, L);
    float l_hi  = 1.0 - smoothstep(0.75, 0.95, L);
    float l_mid = l_lo * l_hi;

    // 2) Chroma gate: favor low/mid chroma, avoid nuking already-saturated stuff
    float c_low   = smoothstep(0.00, 0.25, C);
    float c_high  = 1.0 - smoothstep(0.35, 0.80, C);
    float c_mid   = c_low * c_high;

    float vib_shape = l_mid * c_mid;
    float shape_gate = mix(1.0, vib_shape, clamp(mid_bias, 0.0, 1.0));

    // 3) Skin protection (hue from encoded space)
    float h_src  = safe_hue(src.rgb);
    float dh     = min(abs(h_src - skin_hue), 1.0 - abs(h_src - skin_hue));
    float skin_gate = 1.0 - skin_protect * exp(-0.5 * pow(dh / max(skin_width, EPS), 2.0));

    // 4) Vibrance: boost low-sat colors more than high-sat ones
    float low_sat_boost = 1.0 - smoothstep(0.25, 0.75, C); // 1 at low C, 0 at high C

    float k = vibrance
            * shape_gate
            * skin_gate
            * (0.3 + 0.7 * low_sat_boost); // ensure some effect even in mid/high C

    k = max(k, 0.0);

    // Apply to chroma only (hue and lightness preserved)
    float C2 = C * (1.0 + k);

    // Soft per-pixel cap to avoid crazy jumps
    float max_boost = 1.5 * vibrance + 1.0;
    C2 = min(C2, C * max_boost);

    // --- Global chroma taming ---
    // Sub-linear compression so VHS/SD can look "colored again" without UHD demo saturation.
    float tame = max(chroma_tame, 0.0);
    if (tame > 0.0) {
        float Cnorm = max(C2, 0.0);      // assume typical C in ~0..1 for SDR
        float Ccomp = Cnorm / (1.0 + tame * Cnorm);
        // Blend towards compressed chroma; tame acts as how strong this is.
        C2 = mix(C2, Ccomp, clamp(tame, 0.0, 1.0));
    }

    // Back to a,b from LCH
    vec2 ab2 = C2 * vec2(cos(H), sin(H));
    vec3 lab2 = vec3(L, ab2.x, ab2.y);

    // Back to linear RGB
    vec3 out_lin = oklab_to_linear_srgb(lab2);

    // Back to pipeline encoding (SRGB / PQ / HLG / etc.)
    vec3 out_enc = delinearize(vec4(out_lin, src.a)).rgb;

    // Let libplacebo handle range; only clamp against negatives
    out_enc = max(out_enc, vec3(0.0));

    return vec4(out_enc, src.a);
}
