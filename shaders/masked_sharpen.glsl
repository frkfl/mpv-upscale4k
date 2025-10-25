//!PARAM strength
//!TYPE float
0.28

//!PARAM clamp_amt
//!TYPE float
0.035

//!PARAM edge_low
//!TYPE float
0.03

//!PARAM edge_high
//!TYPE float
0.25

//!PARAM flat_protect
//!TYPE float
0.7

//!PARAM motion_gate
//!TYPE float
0.5

//!PARAM gamma_in
//!TYPE float
1.0

//!PARAM gamma_out
//!TYPE float
1.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Masked anti-halo luma-only sharpen with motion gating

// BT.709 luma weights
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

// Compute luma
float luma(vec3 c) { return dot(c, LUMA); }

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Fetch neighborhood
    vec3 c00 = HOOKED_tex(uv).rgb;
    vec3 cx1 = HOOKED_tex(uv + vec2( px.x, 0)).rgb;
    vec3 cx0 = HOOKED_tex(uv + vec2(-px.x, 0)).rgb;
    vec3 cy1 = HOOKED_tex(uv + vec2(0,  px.y)).rgb;
    vec3 cy0 = HOOKED_tex(uv + vec2(0, -px.y)).rgb;
    vec3 cxy1= HOOKED_tex(uv + vec2( px.x,  px.y)).rgb;
    vec3 cxy0= HOOKED_tex(uv + vec2(-px.x, -px.y)).rgb;

    // Luma values
    float y  = luma(c00);
    float yx1= luma(cx1), yx0=luma(cx0);
    float yy1= luma(cy1), yy0=luma(cy0);
    float yxy1=luma(cxy1), yxy0=luma(cxy0);

    // Edge measure: Sobel-like
    float gx = (yx1 - yx0) * 0.5 + (yxy1 - yxy0) * 0.25;
    float gy = (yy1 - yy0) * 0.5 + (yxy1 - yxy0) * 0.25;
    float edge = sqrt(gx * gx + gy * gy);

    // Local high-pass
    float blur = y * 0.4 + (yx1 + yx0 + yy1 + yy0) * 0.15;
    float hi = y - blur;

    // Clamp correction
    float corr = clamp(hi, -clamp_amt, clamp_amt);

    // Edge band mask
    float band = smoothstep(edge_low, edge_high, edge) *
                 (1.0 - smoothstep(edge_high, edge_high * 2.0, edge));

    // Flat area protection
    float var = abs(y - ((yx1 + yx0 + yy1 + yy0) * 0.25));
    float flat = 1.0 - smoothstep(0.0, 0.08, var);
    float protect = mix(1.0, flat, flat_protect);

    // Motion gating (previous frame luma)
    float yprev = luma(PREV_tex(uv).rgb);
    float motion = clamp(abs(y - yprev) * 4.0, 0.0, 1.0);
    float gate = mix(1.0, 1.0 - motion, motion_gate);

    // Total sharpen gain
    float gain = strength * band * protect * gate;
    float y_out = y + corr * gain;

    // Reapply luma delta to RGB
    float dy = y_out - y;
    vec3 out_rgb = c00 + dy;

    return vec4(out_rgb, 1.0);
}
