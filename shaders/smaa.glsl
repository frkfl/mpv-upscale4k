//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Simple SMAA-lite edge smoother for mpv
//!PARAM float edge_strength = 0.4   // 0.2–0.5 typical
//!PARAM float corner_strength = 0.25 // reduces stair-steps
//!PARAM float gamma = 1.0            // 1.0 = neutral

/*
 * A simplified single-pass approximation of SMAA.
 * Detects edges via luminance contrast and blends adjacent pixels to smooth them.
 * Works well after upscalers and before sharpen/grain.
 */

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float edge(vec2 uv, vec2 off) {
    vec3 a = HOOKED_tex(uv).rgb;
    vec3 b = HOOKED_tex(uv + off).rgb;
    return abs(dot(a - b, LUMA));
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 texel = 1.0 / vec2(HOOKED_size.xy);

    // sample local edges
    float eN = edge(uv, vec2(0.0, -texel.y));
    float eS = edge(uv, vec2(0.0,  texel.y));
    float eE = edge(uv, vec2( texel.x, 0.0));
    float eW = edge(uv, vec2(-texel.x, 0.0));
    float eNE = edge(uv, vec2( texel.x, -texel.y));
    float eSW = edge(uv, vec2(-texel.x,  texel.y));

    float horiz = eE + eW + 0.5 * (eNE + eSW);
    float vert  = eN + eS + 0.5 * (eNE + eSW);
    float edge_intensity = pow(max(horiz, vert), gamma);

    // main sample and four-neighbor blend
    vec4 c  = HOOKED_tex(uv);
    vec4 cx = (HOOKED_tex(uv + vec2(texel.x, 0.0)) + HOOKED_tex(uv - vec2(texel.x, 0.0))) * 0.5;
    vec4 cy = (HOOKED_tex(uv + vec2(0.0, texel.y)) + HOOKED_tex(uv - vec2(0.0, texel.y))) * 0.5;
    vec4 cd = (HOOKED_tex(uv + vec2(texel.x, texel.y)) + HOOKED_tex(uv - vec2(texel.x, texel.y))) * 0.5;

    // weights
    float w_main   = 1.0 - edge_intensity * edge_strength;
    float w_linear = edge_intensity * edge_strength * 0.5;
    float w_diag   = edge_intensity * corner_strength * 0.5;

    vec3 blended = (c.rgb * w_main +
                    cx.rgb * w_linear +
                    cy.rgb * w_linear +
                    cd.rgb * w_diag) /
                   (w_main + 2.0 * w_linear + w_diag);

    return vec4(blended, c.a);
}
