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

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC HDR-safe OkLab vibrance (auto-linear-detect)

const float EPS = 1e-6;

// --- gamma helpers (but auto-detect if input is already linear) ---
vec3 try_to_linear(vec3 c) {
    // If any channel > 1.2 → definitely linear HDR float
    float m = max(max(c.r, c.g), c.b);
    if (m > 1.2) return c;

    // Heuristic: SDR but gamma-encoded
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

vec3 to_gamma(vec3 c) {
    // allow negative and >1 → clamp at end only
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

// --- OkLab transforms (linear RGB only) ---
mat3 M1 = mat3(
    0.4122214708, 0.5363325363, 0.0514459929,
    0.2119034982, 0.6806995451, 0.1073969566,
    0.0883024619, 0.2817188376, 0.6299787005
);
mat3 M2 = mat3(
    0.2104542553,  0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050,  0.4505937099,
    0.0259040371,  0.7827717662, -0.8086757660
);

vec3 linear_srgb_to_oklab(vec3 c) {
    // keep LMS non-negative for cube root
    vec3 lms = M1 * c;
    lms = pow(max(lms, vec3(EPS)), vec3(1.0/3.0));
    return M2 * lms;
}

vec3 oklab_to_linear_srgb(vec3 LLab) {
    float L = LLab.x, a = LLab.y, b = LLab.z;
    float l = L + 0.3963377774 * a + 0.2158037573 * b;
    float m = L - 0.1055613458 * a - 0.0638541728 * b;
    float s = L - 0.0894841775 * a - 1.2914855480 * b;

    l = l*l*l; m = m*m*m; s = s*s*s;

    mat3 Mi = mat3(
        4.0767416621, -3.3077115913,  0.2309699292,
       -1.2684380046,  2.6097574011, -0.3413193965,
        0.0041960863, -0.7034186147,  1.6996226760
    );

    return Mi * vec3(l,m,s);
}

// Skin hue detector (robust)
float safe_hue(vec3 c) {
    float M = max(max(c.r, c.g), c.b);
    float m = min(min(c.r, c.g), c.b);
    float C = max(M - m, EPS);
    vec3 n = (c - m) / C;
    float h = (M == c.r) ? (n.g - n.b)
            : (M == c.g) ? (2.0 + n.b - n.r)
                         : (4.0 + n.r - n.g);
    return fract(h / 6.0);
}

vec4 hook() {
    vec3 srgb = HOOKED_tex(HOOKED_pos).rgb;

    // Convert to linear, even for HDR
    vec3 lin = try_to_linear(srgb);

    // Prevent LMS from going negative
    vec3 lin_clamped = max(lin, vec3(EPS));

    // OkLab
    vec3 lab = linear_srgb_to_oklab(lin_clamped);
    float L = lab.x, a = lab.y, b = lab.z;

    float C = length(vec2(a,b));
    float sat = C / max(L, EPS);

    // mid-sat boost
    float mid = smoothstep(0.0, 1.0, sat / (sat + 0.5));
    mid = mix(1.0, mid, mid_bias);

    // skin protection
    float h  = safe_hue(lin_clamped);
    float dh = min(abs(h - skin_hue), 1.0 - abs(h - skin_hue));
    float skin_gate = 1.0 - skin_protect * exp(-0.5 * pow(dh / skin_width, 2.0));

    // vibrance
    float k = vibrance * mid * skin_gate;

    vec3 lab2 = vec3(L, a * (1.0 + k), b * (1.0 + k));

    // Convert back
    vec3 out_lin = oklab_to_linear_srgb(lab2);

    // Collapse HDR/wide to SDR gamma
    vec3 out_sdr = to_gamma(out_lin);

    // Final clamp
    return vec4(clamp(out_sdr, 0.0, 1.0), 1.0);
}
