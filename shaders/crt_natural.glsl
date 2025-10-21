//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Natural CRT (scanline + triad mask) with color-preserving compensation
//!PARAM float scan_amp = 0.28      // 0..1   how deep the scanline darkening
//!PARAM float scan_curve = 1.35    // >=1    sharpness of scanline valley
//!PARAM float bloom_strength = 0.06// 0..0.2 small local glow
//!PARAM float bloom_radius = 1.25  // 0.5..2 footprint in pixels
//!PARAM float mask_strength = 0.18 // 0..0.4 RGB triad modulation
//!PARAM float mask_soft = 0.25     // 0..1   soften mask transitions
//!PARAM float chroma_preserve = 0.85 // 0..1 luma compensation preserving chroma
//!PARAM float sat_boost = 1.08     // 1.0 keeps original saturation
//!PARAM float black_lift = 0.012   // raises deep blacks a hair to avoid crush
//!PARAM float gamma_in = 2.20      // source EOTF approximation
//!PARAM float gamma_out = 2.20     // display EOTF target

// Utilities
float luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3  toLinear(vec3 c, float g){ return pow(max(c, 0.0), vec3(g>0.0? 1.0/g : 1.0)); }
vec3  toGamma (vec3 c, float g){ return pow(max(c, 0.0), vec3(g>0.0? g : 1.0)); }

float smoothMaskStep(float x, float w){
    // smooth, wide transition for mask stripes to avoid chroma loss
    float a = clamp((x - 0.5*(1.0-w))/w, 0.0, 1.0);
    return a*a*(3.0 - 2.0*a);
}

vec4 hook(){
    vec2  uv   = HOOKED_pos;
    vec2  px   = 1.0 / HOOKED_size.xy;

    // 1) Linearize and get original luminance
    vec3 rgb  = HOOKED_tex(uv).rgb;
    vec3 lin  = toLinear(rgb, gamma_in);
    float Y0  = max(1e-6, luma(lin));

    // 2) Scanlines (per-row modulation in linear light)
    //    Use subpixel Y coordinate; sin^2 gives soft valleys
    float yPix     = uv.y * HOOKED_size.y;
    float fracY    = fract(yPix);
    float wave     = sin(3.14159265 * fracY);
    float scanW    = 1.0 - scan_amp * pow(wave*wave, scan_curve);
    vec3  sl_col   = lin * scanW;

    // 3) Tiny local bloom (cheap 5-tap)
    vec3  blur = sl_col;
    float r = bloom_radius;
    vec3  s1 = HOOKED_tex(uv + vec2( px.x*r, 0.0)).rgb;
    vec3  s2 = HOOKED_tex(uv + vec2(-px.x*r, 0.0)).rgb;
    vec3  s3 = HOOKED_tex(uv + vec2(0.0,  px.y*r)).rgb;
    vec3  s4 = HOOKED_tex(uv + vec2(0.0, -px.y*r)).rgb;
    // linearize neighbors to blend consistently
    s1 = toLinear(s1, gamma_in); s2 = toLinear(s2, gamma_in);
    s3 = toLinear(s3, gamma_in); s4 = toLinear(s4, gamma_in);
    vec3  avg  = (sl_col*2.0 + s1 + s2 + s3 + s4) / 6.0;
    vec3  withBloom = mix(sl_col, avg, bloom_strength);

    // 4) Shadow mask (RGB triad). Period ~ 3 subpixels across X.
    //    We soften the mask to avoid heavy desaturation.
    float triad = mod(floor(uv.x * HOOKED_size.x), 3.0);
    // base triad multipliers
    vec3 m;
    if (triad < 0.5)       m = vec3(1.0, 0.65, 0.65);
    else if (triad < 1.5)  m = vec3(0.65, 1.0, 0.65);
    else                   m = vec3(0.65, 0.65, 1.0);

    // Soften the mask spatially to reduce chroma loss
    float fx = fract(uv.x * HOOKED_size.x * (1.0/3.0)); // phase within triad
    float soft = mix(1.0, smoothMaskStep(fx, clamp(mask_soft, 0.0, 1.0)), mask_soft);
    vec3  mask = mix(vec3(1.0), m, mask_strength * soft);

    vec3 masked = withBloom * mask;

    // 5) Color-preserving compensation:
    //    Scanlines+mask reduce Y; compensate luma while preserving chroma.
    float Y1 = max(1e-6, luma(masked));
    float gain = mix(1.0, Y0 / Y1, clamp(chroma_preserve, 0.0, 1.0));
    vec3  comp = masked * gain;

    // 6) Gentle saturation boost (after compensation)
    float Yc = luma(comp);
    vec3  satCol = mix(vec3(Yc), comp, sat_boost);

    // 7) Slight black lift to mimic CRT pedestal, avoiding crushed colors
    satCol = max(satCol, vec3(black_lift));

    // 8) Back to display gamma
    vec3 outc = toGamma(satCol, gamma_out);
    return vec4(outc, 1.0);
}
