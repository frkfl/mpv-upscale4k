// CRT emulation by Mattias Gustavsson — organic layer only
// Original: crtemu.h — https://github.com/mattiasgustavsson/libs
//
// Stripped to optical/photochemical properties only.
// Removed: shadow mask, crawling scanlines, jitter, flicker, edge blackout.
// Kept:    barrel distortion, chromatic aberration, halation/bloom,
//          filmic tone curve, vignette, noise.
//
// Two-pass: bloom blur → render

// ─── Pass 1: Bloom blur ──────────────────────────────────────────────────────

//!PARAM cm_bloom_spread
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
2.0

//!HOOK MAIN
//!BIND HOOKED
//!SAVE CRT_BLUR
//!DESC [CRT organic] Bloom blur

vec3 bloom_sample(vec2 tc)
{
    return max(HOOKED_tex(tc).rgb, vec3(0.0));
}

vec4 hook()
{
    vec4 xo = vec4(-2.0, -1.0, 1.0, 2.0) * HOOKED_pt.x * cm_bloom_spread;
    vec4 yo = vec4(-2.0, -1.0, 1.0, 2.0) * HOOKED_pt.y * cm_bloom_spread;
    vec2 p  = HOOKED_pos;

    vec3 c = vec3(0.0);
    c += bloom_sample(p + vec2(xo.x, yo.x)) * 0.00366;
    c += bloom_sample(p + vec2(xo.y, yo.x)) * 0.01465;
    c += bloom_sample(p + vec2( 0.0, yo.x)) * 0.02564;
    c += bloom_sample(p + vec2(xo.z, yo.x)) * 0.01465;
    c += bloom_sample(p + vec2(xo.w, yo.x)) * 0.00366;

    c += bloom_sample(p + vec2(xo.x, yo.y)) * 0.01465;
    c += bloom_sample(p + vec2(xo.y, yo.y)) * 0.05861;
    c += bloom_sample(p + vec2( 0.0, yo.y)) * 0.09524;
    c += bloom_sample(p + vec2(xo.z, yo.y)) * 0.05861;
    c += bloom_sample(p + vec2(xo.w, yo.y)) * 0.01465;

    c += bloom_sample(p + vec2(xo.x,  0.0)) * 0.02564;
    c += bloom_sample(p + vec2(xo.y,  0.0)) * 0.09524;
    c += bloom_sample(p + vec2( 0.0,  0.0)) * 0.15018;
    c += bloom_sample(p + vec2(xo.z,  0.0)) * 0.09524;
    c += bloom_sample(p + vec2(xo.w,  0.0)) * 0.02564;

    c += bloom_sample(p + vec2(xo.x, yo.z)) * 0.01465;
    c += bloom_sample(p + vec2(xo.y, yo.z)) * 0.05861;
    c += bloom_sample(p + vec2( 0.0, yo.z)) * 0.09524;
    c += bloom_sample(p + vec2(xo.z, yo.z)) * 0.05861;
    c += bloom_sample(p + vec2(xo.w, yo.z)) * 0.01465;

    c += bloom_sample(p + vec2(xo.x, yo.w)) * 0.00366;
    c += bloom_sample(p + vec2(xo.y, yo.w)) * 0.01465;
    c += bloom_sample(p + vec2( 0.0, yo.w)) * 0.02564;
    c += bloom_sample(p + vec2(xo.z, yo.w)) * 0.01465;
    c += bloom_sample(p + vec2(xo.w, yo.w)) * 0.00366;

    return vec4(c, 1.0);
}

// ─── Pass 2: Render ──────────────────────────────────────────────────────────

//!PARAM cm_barrel
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.12

//!PARAM cm_chroma
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 3.0
1.0

//!PARAM cm_halation
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.30
0.05

//!PARAM cm_contrast
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.15

//!PARAM cm_vignette
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!PARAM cm_noise
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.05
0.015

//!PARAM cm_black_lift
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.05
0.01

//!HOOK MAIN
//!BIND HOOKED
//!BIND CRT_BLUR
//!DESC [CRT organic] Render

#define time       (1.5 * float(frame) / 60.0)
#define resolution HOOKED_size

// Work directly in gamma-encoded space — MAIN provides display-ready video.
// No linearization: pow(2.2) decode + filmic curve was causing yellow cast
// by mishandling blue compression in a space it wasn't designed for.
vec3 tsample(vec2 tc)
{
    return max(HOOKED_tex(tc).rgb, vec3(0.0)) + cm_black_lift;
}

vec3 tsample_blur(vec2 tc)
{
    return CRT_BLUR_tex(tc).rgb;
}

// Gentle S-curve in gamma space: lifts midtones slightly, leaves blacks/whites
// mostly intact. cm_contrast=0 → identity, cm_contrast=1 → visible punch.
vec3 scurve(vec3 col, float strength)
{
    vec3 s = col * col * (3.0 - 2.0*col); // smoothstep shape
    return mix(col, s, strength);
}

vec2 barrel(vec2 uv)
{
    uv = (uv - 0.5) * 2.0;
    uv *= 1.1;
    uv.x *= 1.0 + pow((abs(uv.y) / 5.0), 2.0);
    uv.y *= 1.0 + pow((abs(uv.x) / 4.0), 2.0);
    uv  = (uv / 2.0) + 0.5;
    return uv;
    // Removed: uv * 0.92 + 0.04 was a CRT bezel viewport scale, wrong here
}

float rand(vec2 co)
{
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 hook()
{
    vec2 uv = HOOKED_pos;

    // cm_barrel = 0 → no distortion, 1 → full curve
    vec2 curved = mix(barrel(uv), uv, 1.0 - cm_barrel);

    // Chromatic aberration — radial, zero at center, grows toward edges.
    // R pushed outward, B pushed inward — lateral lens aberration behaviour.
    // Scaled by HOOKED_pt so offset is in pixels, not UV fractions.
    // cm_chroma=1 -> ~2px at corner regardless of output resolution.
    vec2 ca = (curved - 0.5) * HOOKED_pt * 4.0 * cm_chroma;
    vec3 col;
    col.r = tsample(curved + ca).x;
    col.g = tsample(curved).y;
    col.b = tsample(curved - ca).z;

    // Luminance gate: bright pixels produce more halation
    float luma = clamp(col.r*0.299 + col.g*0.587 + col.b*0.114, 0.0, 1.0);
    float gate  = (1.0 - pow(1.0 - pow(luma, 2.0), 1.0)) * 0.85 + 0.15;

    // Halation — local bloom, ~1-2px offset per channel with slow drift.
    // Fixed: original offsets were 10-13px → frame-wide ghost, not halation.
    float t = time * 0.3;
    vec3 bloom_r = tsample_blur(curved + HOOKED_pt * vec2(
         1.0 + 0.8*sin(t*0.90 + curved.y*5.0),
         1.0 + 0.8*sin(t*1.30 + curved.x*3.0)
    )) * vec3(0.5, 0.25, 0.25);
    vec3 bloom_g = tsample_blur(curved + HOOKED_pt * vec2(
         0.5*sin(t*0.70 + curved.y*4.0),
        -1.2 + 0.5*cos(t*1.10)
    )) * vec3(0.25, 0.5, 0.25);
    vec3 bloom_b = tsample_blur(curved + HOOKED_pt * vec2(
        -1.5 + 0.6*sin(t*1.20 + curved.x*2.0),
         0.3*sin(t*0.80)
    )) * vec3(0.25, 0.25, 0.5);

    col += cm_halation * bloom_r * gate;
    col += cm_halation * bloom_g * gate;
    col += cm_halation * bloom_b * gate;

    // Gentle S-curve contrast in gamma space — color-neutral, no clipping.
    col = scurve(clamp(col, 0.0, 1.0), cm_contrast);

    // Vignette — center = 1.0 (no boost), edges darken proportionally.
    // Fixed: original formula boosted center to 1.36x, compounding the brightness
    // issue when scanlines and shadow mask were removed.
    float vig = pow(clamp(curved.x * curved.y * (1.0-curved.x) * (1.0-curved.y) * 16.0, 0.0, 1.0), 0.3);
    col *= mix(1.0, vig, cm_vignette);

    // Noise
    vec2 seed = curved * resolution;
    col -= cm_noise * pow(vec3(
        rand(seed + time),
        rand(seed + time * 2.0),
        rand(seed + time * 3.0)
    ), vec3(1.5));

    return vec4(max(col, vec3(0.0)), 1.0);
}