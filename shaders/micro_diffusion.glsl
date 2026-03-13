//!PARAM md_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.6

//!PARAM md_low
//!TYPE float
//!MINIMUM 0.0001
//!MAXIMUM 0.02
0.002

//!PARAM md_high
//!TYPE float
//!MINIMUM 0.001
//!MAXIMUM 0.1
0.02

//!PARAM md_radius
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 2.0
0.75

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Micro Diffusion (Smoothing)
//!SAVE MAIN

float md_luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 hook() {

    vec2 px = HOOKED_pt;      // pixel size
    vec2 uv = HOOKED_pos;

    vec4 src = HOOKED_tex(uv);
    vec3 center = src.rgb;

    float Y = md_luma(center);

    // --- Gradient estimation (central difference) ---
    float Yx = md_luma(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb) -
               md_luma(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb);

    float Yy = md_luma(HOOKED_tex(uv + vec2(0.0, px.y)).rgb) -
               md_luma(HOOKED_tex(uv - vec2(0.0, px.y)).rgb);

    vec2 grad = vec2(Yx, Yy);
    float gradMag = length(grad);

    // --- Ramp detection mask ---
    float rampMask = smoothstep(md_low, md_high, gradMag) *
                     (1.0 - smoothstep(md_high, md_high * 2.0, gradMag));

    // Early exit if no ramp
    if (rampMask <= 0.0)
        return src;

    // --- Tangent direction (perpendicular to gradient) ---
    vec2 tangent = normalize(vec2(-grad.y, grad.x) + 1e-6);

    vec2 offset = tangent * px * md_radius;

    vec3 sample1 = HOOKED_tex(uv + offset).rgb;
    vec3 sample2 = HOOKED_tex(uv - offset).rgb;

    vec3 diffused = (sample1 + sample2) * 0.5;

    // --- Blend ---
    vec3 result = mix(center, diffused, rampMask * md_strength);

    return vec4(result, src.a);
}