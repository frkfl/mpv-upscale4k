//!PARAM fmtr_clean
//!TYPE float
0.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC [Custom] Aggressive midband subtraction

vec3 blurN(vec2 uv, vec2 px, float r)
{
    vec3 sum = vec3(0.0);

    sum += HOOKED_tex(uv + px * vec2(-r,-r)).rgb;
    sum += HOOKED_tex(uv + px * vec2( 0.0,-r)).rgb;
    sum += HOOKED_tex(uv + px * vec2( r,-r)).rgb;

    sum += HOOKED_tex(uv + px * vec2(-r, 0.0)).rgb;
    sum += HOOKED_tex(uv + px * vec2( 0.0, 0.0)).rgb;
    sum += HOOKED_tex(uv + px * vec2( r, 0.0)).rgb;

    sum += HOOKED_tex(uv + px * vec2(-r, r)).rgb;
    sum += HOOKED_tex(uv + px * vec2( 0.0, r)).rgb;
    sum += HOOKED_tex(uv + px * vec2( r, r)).rgb;

    return sum / 9.0;
}

vec4 hook()
{
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;

    vec3 orig = HOOKED_tex(uv).rgb;

    if (fmtr_clean == 0.0)
        return vec4(orig, 1.0);

    // Radius scales directly with fmtr_clean
    float r = 1.0 + fmtr_clean * 2.0;

    vec3 base = blurN(uv, px, r);

    // Midband residual
    vec3 residual = orig - base;

    // Direct linear subtraction — NO COMPRESSION
    vec3 result = orig - residual * fmtr_clean;

    return vec4(result, 1.0);
}
