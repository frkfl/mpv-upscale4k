// FidelityFX Super Resolution 1.0 (EASU + RCAS) for mpv (vo=gpu-next / vo=gpu)
//
// Ported from AMD FidelityFX SDK, ffx_fsr1.h ("ffxFsrEasuFloat" / "FsrRcasF"):
//   https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK
//   Copyright (C) 2026 Advanced Micro Devices, Inc.
//   MIT License (see below).
//
// The math in the EASU/RCAS passes below is a line-for-line translation of
// AMD's reference implementation from HLSL/FFX-GPU pseudo-language into plain
// GLSL for mpv's custom shader (HOOK-block) format, using unpacked per-tap
// sampling instead of AMD's SIMD-packed gather optimization (same result,
// more texture fetches, much simpler to read/verify).
//
// --------------------------------------------------------------------------
// MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// --------------------------------------------------------------------------
//
// Usage:
//   mpv --glsl-shaders=FSR.glsl --scale=bilinear --cscale=bilinear video.mkv
//
// FSR only makes sense combined with a plain (non-sharpening, non-fancy)
// base scaler, since EASU itself replaces mpv's upscale entirely. Also make
// sure the window/output is actually larger than the video (fullscreen a
// lower-resolution file, or use --autofit/--geometry), otherwise EASU's
// WHEN guard will simply skip both passes.
//
// Tunables: edit RCAS_SHARPNESS_STOPS below (0.0 = sharpest, higher = softer).

//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!WHEN OUTPUT.w MAIN.w > OUTPUT.h MAIN.h > *
//!DESC FidelityFX Super Resolution 1.0 (EASU, edge-adaptive upscale)

vec3 easu_tex(vec2 texel) {
    return HOOKED_tex((texel + vec2(0.5)) * HOOKED_pt).rgb;
}

float easu_luma2(vec3 c) {
    // Cheap luma*2 approximation (matches AMD reference).
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

void easu_set(inout vec2 dir, inout float len, float w,
              float lA, float lB, float lC, float lD, float lE) {
    float dc = lD - lC;
    float cb = lC - lB;
    float lenX = max(abs(dc), abs(cb));
    lenX = 1.0 / max(lenX, 1e-8);
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
    lenX *= lenX;
    len += lenX * w;

    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = 1.0 / max(lenY, 1e-8);
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
    lenY *= lenY;
    len += lenY * w;
}

void easu_tap(inout vec3 aC, inout float aW, vec2 offset, vec2 dir, vec2 len2,
              float lob, float clp, vec3 c) {
    vec2 v;
    v.x = offset.x * dir.x + offset.y * dir.y;
    v.y = offset.x * (-dir.y) + offset.y * dir.x;
    v *= len2;
    float d2 = min(v.x * v.x + v.y * v.y, clp);
    float wB = (2.0 / 5.0) * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = (25.0 / 16.0) * wB - (25.0 / 16.0 - 1.0);
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

vec4 hook() {
    // Position of the 'f' tap (upper-left of the working 2x2 block), and the
    // fractional offset of the output sample within it.
    vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;

    // 12-tap neighborhood:
    //     b c
    //   e f g h
    //   i j k l
    //     n o
    vec3 b = easu_tex(fp + vec2(0.0, -1.0));
    vec3 c = easu_tex(fp + vec2(1.0, -1.0));
    vec3 e = easu_tex(fp + vec2(-1.0, 0.0));
    vec3 f = easu_tex(fp + vec2(0.0, 0.0));
    vec3 g = easu_tex(fp + vec2(1.0, 0.0));
    vec3 h = easu_tex(fp + vec2(2.0, 0.0));
    vec3 i = easu_tex(fp + vec2(-1.0, 1.0));
    vec3 j = easu_tex(fp + vec2(0.0, 1.0));
    vec3 k = easu_tex(fp + vec2(1.0, 1.0));
    vec3 l = easu_tex(fp + vec2(2.0, 1.0));
    vec3 n = easu_tex(fp + vec2(0.0, 2.0));
    vec3 o = easu_tex(fp + vec2(1.0, 2.0));

    float bL = easu_luma2(b), cL = easu_luma2(c);
    float eL = easu_luma2(e), fL = easu_luma2(f), gL = easu_luma2(g), hL = easu_luma2(h);
    float iL = easu_luma2(i), jL = easu_luma2(j), kL = easu_luma2(k), lL = easu_luma2(l);
    float nL = easu_luma2(n), oL = easu_luma2(o);

    // Gradient direction/length, sampled around each of the 4 central taps
    // (f, g, j, k), weighted by bilinear proximity to the output sample.
    vec2 dir = vec2(0.0);
    float len = 0.0;
    easu_set(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL); // around f
    easu_set(dir, len, pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);         // around g
    easu_set(dir, len, (1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);         // around j
    easu_set(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);                 // around k

    // Normalize direction (fall back to +X when the local gradient is ~0).
    vec2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool zro = dirR < (1.0 / 32768.0);
    dirR = zro ? 1.0 : inversesqrt(dirR);
    dir.x = zro ? 1.0 : dir.x;
    dir *= dirR;

    len = len * 0.5;
    len *= len;

    float stretch = (dir.x * dir.x + dir.y * dir.y) / max(abs(dir.x), abs(dir.y));
    vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = 1.0 / lob;

    // Clamp window (min/max of the 4 nearest taps) to prevent ringing.
    vec3 min4 = min(min(min(j, k), g), f);
    vec3 max4 = max(max(max(j, k), g), f);

    vec3 aC = vec3(0.0);
    float aW = 0.0;
    easu_tap(aC, aW, vec2(0.0, -1.0) - pp, dir, len2, lob, clp, b);
    easu_tap(aC, aW, vec2(1.0, -1.0) - pp, dir, len2, lob, clp, c);
    easu_tap(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, i);
    easu_tap(aC, aW, vec2(0.0, 1.0) - pp, dir, len2, lob, clp, j);
    easu_tap(aC, aW, vec2(0.0, 0.0) - pp, dir, len2, lob, clp, f);
    easu_tap(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, e);
    easu_tap(aC, aW, vec2(1.0, 1.0) - pp, dir, len2, lob, clp, k);
    easu_tap(aC, aW, vec2(2.0, 1.0) - pp, dir, len2, lob, clp, l);
    easu_tap(aC, aW, vec2(2.0, 0.0) - pp, dir, len2, lob, clp, h);
    easu_tap(aC, aW, vec2(1.0, 0.0) - pp, dir, len2, lob, clp, g);
    easu_tap(aC, aW, vec2(1.0, 2.0) - pp, dir, len2, lob, clp, o);
    easu_tap(aC, aW, vec2(0.0, 2.0) - pp, dir, len2, lob, clp, n);

    vec3 pix = clamp(aC / aW, min4, max4);
    return vec4(pix, HOOKED_tex(HOOKED_pos).a);
}

//!HOOK MAIN
//!BIND HOOKED
//!DESC FidelityFX Super Resolution 1.0 (RCAS, contrast-adaptive sharpen)

// 0.0 = maximum sharpness, higher = softer (in stops, each +1.0 halves it).
#define RCAS_SHARPNESS_STOPS 0.0

vec4 hook() {
    // 3x3 plus-shaped neighborhood:
    //     b
    //   d e f
    //     h
    vec3 b = HOOKED_texOff(vec2(0.0, -1.0)).rgb;
    vec3 d = HOOKED_texOff(vec2(-1.0, 0.0)).rgb;
    vec4 ee = HOOKED_texOff(vec2(0.0, 0.0));
    vec3 e = ee.rgb;
    vec3 f = HOOKED_texOff(vec2(1.0, 0.0)).rgb;
    vec3 h = HOOKED_texOff(vec2(0.0, 1.0)).rgb;

    float bL = b.b * 0.5 + (b.r * 0.5 + b.g);
    float dL = d.b * 0.5 + (d.r * 0.5 + d.g);
    float eL = e.b * 0.5 + (e.r * 0.5 + e.g);
    float fL = f.b * 0.5 + (f.r * 0.5 + f.g);
    float hL = h.b * 0.5 + (h.r * 0.5 + h.g);

    // Min/max of the ring, used both as the sharpen limiter and (via eL) to
    // detect whether the center tap is already a local extremum (noise).
    vec3 mn4 = min(min(min(b, d), f), h);
    vec3 mx4 = max(max(max(b, d), f), h);
    float minL = min(min(min(bL, dL), fL), hL);

    // Limiters (need to stay high precision to avoid tonality shifts).
    float lowerLimMul = clamp(eL / max(minL, 1e-8), 0.0, 1.0);
    vec3 hitMin = mn4 / max(4.0 * mx4, 1e-8) * lowerLimMul;
    vec3 hitMax = (vec3(1.0) - mx4) / (4.0 * mn4 - 4.0 - 1e-8);
    vec3 lobeRGB = max(-hitMin, hitMax);
    float lobe = max(-(0.25 - 1.0 / 16.0), min(max(max(lobeRGB.r, lobeRGB.g), lobeRGB.b), 0.0)) * exp2(-float(RCAS_SHARPNESS_STOPS));

    float rcpL = 1.0 / (4.0 * lobe + 1.0);
    vec3 pix = (lobe * (b + d + f + h) + e) * rcpL;

    return vec4(pix, ee.a);
}
