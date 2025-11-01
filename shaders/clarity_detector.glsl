#version 450
//!PARAM sigma
//!TYPE float
0.5

//!PARAM r_low
//!TYPE float
0.15

//!PARAM r_high
//!TYPE float
0.45

//!PARAM m_lo
//!TYPE float
0.02

//!PARAM m_hi
//!TYPE float
0.25

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Structure Clarity Detector (Y-preblur, curvature, chroma-luma coherence)

#define EPS 1e-6

// Luma from linear RGB (BT.709)
float luma709(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

// Derive Cb/Cr (BT.709), normalized to [0,1] from linear RGB
vec2 cbcr709(vec3 rgb, float Y) {
    float Cb = (rgb.b - Y) / 1.8556 + 0.5;
    float Cr = (rgb.r - Y) / 1.5748 + 0.5;
    return clamp(vec2(Cb, Cr), 0.0, 1.0);
}

// 3-tap separable Gaussian weights from sigma
vec3 gauss3(float s) {
    s = max(s, 0.001);
    float w1 = exp(-0.5 * (1.0 / s) * (1.0 / s));
    float w0 = 1.0;
    float n = w0 + 2.0 * w1;
    return vec3(w1, w0, w1) / n;
}

// Sample luma pre-smoothed (separable 3-tap, sigma ~ 0.5 px default)
float luma_smoothed(vec2 uv, vec2 texel, float s) {
    vec3 w = gauss3(s);
    // horizontal
    float yh = w.x * luma709(HOOKED_tex(uv - vec2(texel.x, 0.0)).rgb) +
               w.y * luma709(HOOKED_tex(uv).rgb) +
               w.z * luma709(HOOKED_tex(uv + vec2(texel.x, 0.0)).rgb);
    // vertical
    float yv = w.x * yh + // reuse center row weight for minor speed; do proper vertical
               0.0;       // (placeholder to keep compiler happy, replaced below)

    // Do proper vertical using fresh samples (cannot reuse yh correctly here)
    float yv_true = w.x * luma709(HOOKED_tex(uv - vec2(0.0, texel.y)).rgb) +
                    w.y * yh /* center uses already horizontally blurred */ +
                    w.z * luma709(HOOKED_tex(uv + vec2(0.0, texel.y)).rgb);
    return yv_true;
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 texel = 1.0 / HOOKED_size.xy;

    vec3 rgb = HOOKED_tex(uv).rgb;

    // 2.1 Luma pre-smoothing
    float Y_s = luma_smoothed(uv, texel, sigma);

    // Chroma (from original rgb, not blurred)
    float Y0 = luma709(rgb);
    vec2 CbCr = cbcr709(rgb, Y0);
    float Cx = 0.5 * (CbCr.x + CbCr.y);

    // Finite differences for luma (central)
    float Yx_p = luma709(HOOKED_tex(uv + vec2(texel.x, 0.0)).rgb);
    float Yx_m = luma709(HOOKED_tex(uv - vec2(texel.x, 0.0)).rgb);
    float Yy_p = luma709(HOOKED_tex(uv + vec2(0.0, texel.y)).rgb);
    float Yy_m = luma709(HOOKED_tex(uv - vec2(0.0, texel.y)).rgb);

    // Use smoothed luma for gradient magnitude; approximate via mixed sampling
    float Ys_x_p = luma_smoothed(uv + vec2(texel.x, 0.0), texel, sigma);
    float Ys_x_m = luma_smoothed(uv - vec2(texel.x, 0.0), texel, sigma);
    float Ys_y_p = luma_smoothed(uv + vec2(0.0, texel.y), texel, sigma);
    float Ys_y_m = luma_smoothed(uv - vec2(0.0, texel.y), texel, sigma);

    vec2 gY = 0.5 * vec2(Ys_x_p - Ys_x_m, Ys_y_p - Ys_y_m);
    float m = length(gY);

    // Normalized gradient direction (fallback to x-axis if flat)
    vec2 dir = (m > EPS) ? (gY / m) : vec2(1.0, 0.0);

    // 3.1 Directional second derivative along gradient
    float Yp1 = luma709(HOOKED_tex(uv + dir * texel).rgb);
    float Ym1 = luma709(HOOKED_tex(uv - dir * texel).rgb);
    float Ypp = Yp1 + Ym1 - 2.0 * Y_s;      // curvature
    float dYdir = 0.5 * (Yp1 - Ym1);        // directional gradient magnitude proxy

    // 3.2 Curvature ratio r_w
    float r_w = abs(Ypp) / (abs(dYdir) + EPS);
    r_w = clamp(r_w, 0.0, 2.0);

    // 3.3 Chroma–luma coherence
    // Chroma gradients (central) of Cx = (Cb+Cr)/2
    float Cx_x_p = 0.5 * (cbcr709(HOOKED_tex(uv + vec2(texel.x, 0.0)).rgb, Yx_p).x +
                          cbcr709(HOOKED_tex(uv + vec2(texel.x, 0.0)).rgb, Yx_p).y);
    float Cx_x_m = 0.5 * (cbcr709(HOOKED_tex(uv - vec2(texel.x, 0.0)).rgb, Yx_m).x +
                          cbcr709(HOOKED_tex(uv - vec2(texel.x, 0.0)).rgb, Yx_m).y);
    float Cx_y_p = 0.5 * (cbcr709(HOOKED_tex(uv + vec2(0.0, texel.y)).rgb, Yy_p).x +
                          cbcr709(HOOKED_tex(uv + vec2(0.0, texel.y)).rgb, Yy_p).y);
    float Cx_y_m = 0.5 * (cbcr709(HOOKED_tex(uv - vec2(0.0, texel.y)).rgb, Yy_m).x +
                          cbcr709(HOOKED_tex(uv - vec2(0.0, texel.y)).rgb, Yy_m).y);

    vec2 gC = 0.5 * vec2(Cx_x_p - Cx_x_m, Cx_y_p - Cx_y_m);

    // Alignment c = |cos(theta)|
    float gY_len = max(length(gY), EPS);
    float gC_len = max(length(gC), EPS);
    float c = abs(dot(gY, gC) / (gY_len * gC_len));
    c = clamp(c, 0.0, 1.0);

    // 3.4 Edge magnitude suppression s
    float s = 1.0 - smoothstep(m_lo, m_hi, m);

    // 4. Clarity potential
    float P = s * smoothstep(r_low, r_high, r_w) * c;
    P = clamp(P, 0.0, 1.0);

    // 5. Output
    #if defined(DEBUG_CLARITY)
        vec3 dbg;
        if (c < 0.3)      dbg = vec3(0.0, 0.0, 1.0);      // Blue: color-bleed edge
        else if (P > 0.5) dbg = vec3(1.0, 1.0, 0.0);      // Yellow: recoverable structure
        else if (s < 0.2) dbg = vec3(1.0, 0.0, 0.0);      // Red: strong suppressed edges
        else              dbg = vec3(0.0);
        return vec4(dbg, 1.0);
    #else
        return vec4(vec3(P), 1.0);
    #endif
}
