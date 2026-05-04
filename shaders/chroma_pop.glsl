//!PARAM cp_amount
//!TYPE float
0.12

//!PARAM cp_radius
//!TYPE float
1.2

//!PARAM cp_clamp_c
//!TYPE float
0.06

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Chroma Pop

// BT.2020 RGB↔YCbCr matrices (linear domain, column-major)
const mat3 RGB2YUV = mat3(
     0.2627, -0.1396,  0.5000,  // column 0: R -> Y, Cb, Cr
     0.6780, -0.3604, -0.4598,  // column 1: G -> Y, Cb, Cr
     0.0593,  0.5000, -0.0402   // column 2: B -> Y, Cb, Cr
);
const mat3 YUV2RGB = mat3(
    1.0,        1.0,       1.0,       // column 0
    0.0,       -0.1645,    1.8814,    // column 1
    1.4746,    -0.5714,    0.0        // column 2
);

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;
    float r = cp_radius;

    // Input is linear BT.2020 (MAIN, gpu-next)
    vec3 lin = HOOKED_tex(uv).rgb;
    vec3 yuv = RGB2YUV * lin;
    float Y  = yuv.x;

    // 5-tap chroma blur (luma excluded)
    vec3 s = vec3(0.0);
    s += RGB2YUV * HOOKED_tex(uv + vec2( 0.0,       0.0)).rgb;
    s += RGB2YUV * HOOKED_tex(uv + vec2( px.x * r,  0.0)).rgb;
    s += RGB2YUV * HOOKED_tex(uv + vec2(-px.x * r,  0.0)).rgb;
    s += RGB2YUV * HOOKED_tex(uv + vec2( 0.0,  px.y * r)).rgb;
    s += RGB2YUV * HOOKED_tex(uv + vec2( 0.0, -px.y * r)).rgb;
    s *= 0.2; // 1/5 average

    // Chroma contrast boost
    vec2 UV   = yuv.yz;
    vec2 UVb  = s.yz;
    vec2 diff = UV - UVb;
    vec2 add  = clamp(diff * cp_amount, -cp_clamp_c, cp_clamp_c);

    vec3 yuv2    = vec3(Y, UV + add);
    vec3 out_lin = YUV2RGB * yuv2;

    return vec4(max(out_lin, 0.0), 1.0);
}
