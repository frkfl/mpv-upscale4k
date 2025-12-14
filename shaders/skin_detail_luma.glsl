#version 450

//!PARAM strength
//!TYPE float
0.18

//!PARAM skin_hue
//!TYPE float
0.075

//!PARAM skin_width
//!TYPE float
0.070

//!PARAM skin_soft
//!TYPE float
0.030

//!PARAM freq
//!TYPE float
1.25

//!PARAM anisotropy
//!TYPE float
0.55

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Skin Detail Enhancer (skin-gated luma microtexture, grain-free output)

// BT.2020 luma (linear RGB)
float luma2020(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

// Linear BT.2020 RGB <-> YCbCr (linear-domain)
vec3 rgb_to_ycbcr2020(vec3 rgb) {
    const float Kr = 0.2627;
    const float Kb = 0.0593;
    const float Kg = 1.0 - Kr - Kb;
    float Y  = Kr * rgb.r + Kg * rgb.g + Kb * rgb.b;
    float Cb = (rgb.b - Y) / (2.0 * (1.0 - Kb));
    float Cr = (rgb.r - Y) / (2.0 * (1.0 - Kr));
    return vec3(Y, Cb, Cr);
}

vec3 ycbcr_to_rgb2020(vec3 ycc) {
    const float Kr = 0.2627;
    const float Kb = 0.0593;
    const float Kg = 1.0 - Kr - Kb;
    float Y  = ycc.x;
    float Cb = ycc.y;
    float Cr = ycc.z;
    float R = Y + Cr * (2.0 * (1.0 - Kr));
    float B = Y + Cb * (2.0 * (1.0 - Kb));
    float G = (Y - Kr * R - Kb * B) / max(Kg, 1e-6);
    return vec3(R, G, B);
}

// Hue in [0..1) from linear RGB (for skin gating)
float safe_hue(vec3 rgb_lin) {
    float M = max(max(rgb_lin.r, rgb_lin.g), rgb_lin.b);
    float m = min(min(rgb_lin.r, rgb_lin.g), rgb_lin.b);
    float C = max(M - m, 1e-6);
    vec3 n = (rgb_lin - m) / C;
    float h = (M == rgb_lin.r) ? (n.g - n.b)
            : (M == rgb_lin.g) ? (2.0 + n.b - n.r)
                               : (4.0 + n.r - n.g);
    return fract((h / 6.0) + 1.0);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth band-pass-ish noise in luma, evaluated but NOT left as visible grain (gated + tiny amplitude)
float micro_tex(vec2 p) {
    // p in pixel space
    float n0 = hash12(p);
    float n1 = hash12(p * 1.91 + vec2(17.0, 9.0));
    float n2 = hash12(p * 3.73 + vec2(3.0, 41.0));
    float n  = (n0 * 0.55 + n1 * 0.30 + n2 * 0.15);
    // remap to centered, slightly "blue-ish" by highpassing against a coarse term
    float c  = hash12(p * 0.45 + vec2(101.0, 13.0));
    float hp = (n - c);
    return hp;
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;
    vec2 p  = uv * HOOKED_size;

    vec3 c00 = HOOKED_tex(uv).rgb;

    // Skin gate by hue (linear RGB)
    float h = safe_hue(c00);
    float dh = abs(h - skin_hue);
    dh = min(dh, 1.0 - dh);
    float w_skin = 1.0 - smoothstep(max(skin_width, 1e-4), max(skin_width + skin_soft, 1e-4), dh);

    // Detail gate: only add texture where the image is already fairly smooth (avoid adding on edges/ringing)
    vec3 c10  = HOOKED_tex(uv + vec2( px.x, 0.0)).rgb;
    vec3 c_10 = HOOKED_tex(uv + vec2(-px.x, 0.0)).rgb;
    vec3 c01  = HOOKED_tex(uv + vec2(0.0,  px.y)).rgb;
    vec3 c0_1 = HOOKED_tex(uv + vec2(0.0, -px.y)).rgb;

    float Y0  = luma2020(c00);
    float Yx  = 0.5 * (luma2020(c10) + luma2020(c_10));
    float Yy  = 0.5 * (luma2020(c01) + luma2020(c0_1));
    float grad = abs(Yx - Y0) + abs(Yy - Y0);
    float w_flat = exp(-grad / 0.020); // ~1 in smooth areas, ~0 on edges

    // Anisotropic "strand" modulation (procedural, subtle)
    vec2 dir = normalize(vec2(1.0, anisotropy));
    float sphase = dot(p, dir) * (0.09 * freq);
    float strand = sin(sphase) * 0.5 + 0.5;

    // Micro texture (centered)
    float mt = micro_tex(p * (0.85 * freq)) * 0.6 + (strand - 0.5) * 0.4;

    // Apply on luma only
    vec3 ycc = rgb_to_ycbcr2020(c00);

    float k = clamp(strength, 0.0, 1.0);
    float amp = mix(0.0006, 0.0022, k); // linear luma amplitude
    float addY = mt * amp * w_skin * w_flat;

    // Safety limiter
    addY = clamp(addY, -0.004, 0.004);

    ycc.x = clamp(ycc.x + addY, 0.0, 1.0);

    vec3 out_rgb = ycbcr_to_rgb2020(ycc);
    return vec4(clamp(out_rgb, 0.0, 1.0), 1.0);
}
