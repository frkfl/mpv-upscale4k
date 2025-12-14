#version 450

//!PARAM strength
//!TYPE float
0.28

//!PARAM threshold
//!TYPE float
0.004

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Micro Detail Enhancer (Luma-only, edge-gated)

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

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;

    vec3 c00  = HOOKED_tex(uv).rgb;
    vec3 c10  = HOOKED_tex(uv + vec2( px.x, 0.0)).rgb;
    vec3 c_10 = HOOKED_tex(uv + vec2(-px.x, 0.0)).rgb;
    vec3 c01  = HOOKED_tex(uv + vec2(0.0,  px.y)).rgb;
    vec3 c0_1 = HOOKED_tex(uv + vec2(0.0, -px.y)).rgb;
    vec3 c11  = HOOKED_tex(uv + vec2( px.x,  px.y)).rgb;
    vec3 c1_1 = HOOKED_tex(uv + vec2( px.x, -px.y)).rgb;
    vec3 c_11 = HOOKED_tex(uv + vec2(-px.x,  px.y)).rgb;
    vec3 c_1_1= HOOKED_tex(uv + vec2(-px.x, -px.y)).rgb;

    // 8-neighbor mean
    vec3 mean = (c10 + c_10 + c01 + c0_1 + c11 + c1_1 + c_11 + c_1_1) * (1.0 / 8.0);

    // Luma high-pass (micro detail)
    float Y0 = luma2020(c00);
    float Ym = luma2020(mean);
    float highY = Y0 - Ym;

    // Edge/detail gate based on local contrast (not brightness)
    float t = max(threshold, 0.0);
    float soft = max(t * 1.75, 1e-6);
    float w = smoothstep(t, t + soft, abs(highY));

    // Apply only on luma to avoid hue shifts
    vec3 ycc = rgb_to_ycbcr2020(c00);
    float k = strength * w;

    // Mild limiter to avoid harsh ringing
    float lim = mix(0.010, 0.030, clamp(strength, 0.0, 1.0));
    float deltaY = clamp(highY * k, -lim, lim);

    ycc.x = clamp(ycc.x + deltaY, 0.0, 1.0);

    vec3 out_rgb = ycbcr_to_rgb2020(ycc);
    return vec4(clamp(out_rgb, 0.0, 1.0), 1.0);
}
