//!PARAM mc_radius
//!TYPE float
1.0

//!PARAM mc_amount
//!TYPE float
0.12

//!PARAM mc_threshold
//!TYPE float
0.02

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Micro-Contrast addition

// Input is linear BT.2020 (MAIN, gpu-next)
float luma(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    float r = mc_radius;

    vec3 c  = HOOKED_tex(uv).rgb;
    vec3 n  = HOOKED_tex(uv + vec2( 0.0,      -px.y * r)).rgb;
    vec3 s  = HOOKED_tex(uv + vec2( 0.0,       px.y * r)).rgb;
    vec3 e  = HOOKED_tex(uv + vec2( px.x * r,  0.0     )).rgb;
    vec3 w  = HOOKED_tex(uv + vec2(-px.x * r,  0.0     )).rgb;
    vec3 ne = HOOKED_tex(uv + vec2( px.x * r, -px.y * r)).rgb;
    vec3 nw = HOOKED_tex(uv + vec2(-px.x * r, -px.y * r)).rgb;
    vec3 se = HOOKED_tex(uv + vec2( px.x * r,  px.y * r)).rgb;
    vec3 sw = HOOKED_tex(uv + vec2(-px.x * r,  px.y * r)).rgb;

    vec3 blur = (c + n + s + e + w + ne + nw + se + sw) * (1.0 / 9.0);
    vec3 diff = c - blur;

    float gate = smoothstep(mc_threshold, 3.0 * mc_threshold, abs(luma(diff)));

    vec3 boosted = c + diff * (mc_amount * gate);

    return vec4(boosted, 1.0);
}