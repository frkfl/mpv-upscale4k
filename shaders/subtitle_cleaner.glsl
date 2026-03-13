//!PARAM sc_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.65

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Subtitle Cleaner
//!SAVE MAIN

float sc_luma(vec3 c)
{
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 hook()
{
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    vec4 center = HOOKED_tex(uv);
    vec3 c = center.rgb;

    float Y = sc_luma(c);

    vec3 l = HOOKED_tex(uv + vec2(-px.x, 0.0)).rgb;
    vec3 r = HOOKED_tex(uv + vec2( px.x, 0.0)).rgb;
    vec3 u = HOOKED_tex(uv + vec2(0.0, -px.y)).rgb;
    vec3 d = HOOKED_tex(uv + vec2(0.0,  px.y)).rgb;

    vec3 ul = HOOKED_tex(uv + vec2(-px.x, -px.y)).rgb;
    vec3 ur = HOOKED_tex(uv + vec2( px.x, -px.y)).rgb;
    vec3 dl = HOOKED_tex(uv + vec2(-px.x,  px.y)).rgb;
    vec3 dr = HOOKED_tex(uv + vec2( px.x,  px.y)).rgb;

    float Yl = sc_luma(l);
    float Yr = sc_luma(r);
    float Yu = sc_luma(u);
    float Yd = sc_luma(d);

    // relaxed bright detection
    float bright = step(0.60, Y);

    // detect dark outline
    float dark_near = step(min(min(Yl, Yr), min(Yu, Yd)), 0.35);

    // edge magnitude
    float edge = max(max(abs(Y - Yl), abs(Y - Yr)),
                     max(abs(Y - Yu), abs(Y - Yd)));

    float edge_mask = smoothstep(0.08, 0.25, edge);

    // subtitle mask
    float mask = bright * dark_near * edge_mask;

    // 8-tap smoothing (slightly stronger but still small radius)
    vec3 sc_blur =
        (l + r + u + d +
         ul + ur + dl + dr) * 0.125;

    vec3 result = mix(c, sc_blur, mask * sc_strength);

    return vec4(result, center.a);
}