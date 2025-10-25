//!PARAM amount
//!TYPE float
0.12

//!PARAM radius
//!TYPE float
1.2

//!PARAM clamp_c
//!TYPE float
0.06

//!PARAM gamma_in
//!TYPE float
2.20

//!PARAM gamma_out
//!TYPE float
2.20

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Chroma Pop (local chroma contrast, luma-safe)

// sRGB <-> linear helpers
vec3 toLin(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? 1.0 / g : 1.0));
}
vec3 toGam(vec3 c, float g) {
    return pow(max(c, 0.0), vec3(g > 0.0 ? g : 1.0));
}

// BT.709 RGB↔YUV matrices (linear domain)
mat3 RGB2YUV = mat3(
    0.2126,  0.7152,  0.0722,
   -0.1146, -0.3854,  0.5000,
    0.5000, -0.4542, -0.0458
);
mat3 YUV2RGB = inverse(RGB2YUV);

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;
    float r = radius;

    // Source to linear YUV
    vec3 srgb = HOOKED_tex(uv).rgb;
    vec3 lin  = toLin(srgb, gamma_in);
    vec3 yuv  = RGB2YUV * lin;
    float Y   = yuv.x;

    // 5-tap chroma blur (luma excluded)
    vec3 s = vec3(0.0);
    s += RGB2YUV * toLin(HOOKED_tex(uv + vec2( 0.0,  0.0)).rgb, gamma_in);
    s += RGB2YUV * toLin(HOOKED_tex(uv + vec2( px.x * r, 0.0)).rgb, gamma_in);
    s += RGB2YUV * toLin(HOOKED_tex(uv + vec2(-px.x * r, 0.0)).rgb, gamma_in);
    s += RGB2YUV * toLin(HOOKED_tex(uv + vec2(0.0,  px.y * r)).rgb, gamma_in);
    s += RGB2YUV * toLin(HOOKED_tex(uv + vec2(0.0, -px.y * r)).rgb, gamma_in);
    s *= 0.2; // 1/5 average

    // Chroma contrast boost
    vec2 UV  = yuv.yz;
    vec2 UVb = s.yz;
    vec2 diff = UV - UVb;
    vec2 add  = clamp(diff * amount, -clamp_c, clamp_c);

    vec3 yuv2 = vec3(Y, UV + add);
    vec3 out_lin  = YUV2RGB * yuv2;
    vec3 out_srgb = toGam(out_lin, gamma_out);

    return vec4(clamp(out_srgb, 0.0, 1.0), 1.0);
}
