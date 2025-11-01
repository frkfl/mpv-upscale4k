//!PARAM strength
//!TYPE float
0.65

//!PARAM sigma
//!TYPE float
1.0

//!PARAM delta_max
//!TYPE float
0.02

//!PARAM threshold_low
//!TYPE float
0.02

//!PARAM threshold_high
//!TYPE float
0.15

//!PARAM multiscale_ratio
//!TYPE float
0.60

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Line Cleaner & Structural Preparation (v1.1) — anisotropic micro-line suppressor

//#define DEBUG_GRAY

// ------------------------------------------------------------
// Helpers (declare BEFORE use to satisfy glslang)
// ------------------------------------------------------------
vec3 rgb_to_ycbcr601(vec3 c) {
    float Y  = 0.299*c.r + 0.587*c.g + 0.114*c.b;
    float Cb = (c.b - Y)*0.565 + 0.5;
    float Cr = (c.r - Y)*0.713 + 0.5;
    return vec3(Y, Cb, Cr);
}
vec3 ycbcr601_to_rgb(float Y, float Cb, float Cr) {
    float R = Y + 1.402*(Cr - 0.5);
    float B = Y + 1.772*(Cb - 0.5);
    float G = (Y - 0.114*B - 0.299*R) / 0.587;
    return vec3(R, G, B);
}
vec2 texel() { return 1.0 / HOOKED_size.xy; }

float fetchY(vec2 uv) {
    return rgb_to_ycbcr601(HOOKED_tex(uv).rgb).x;
}

// Sobel gradient at scale step 's' (in pixels)
vec2 sobel_grad(vec2 uv, float s) {
    vec2 t = texel() * s;
    float tl = fetchY(uv + vec2(-t.x, -t.y));
    float tc = fetchY(uv + vec2( 0.0, -t.y));
    float tr = fetchY(uv + vec2( t.x, -t.y));
    float ml = fetchY(uv + vec2(-t.x,  0.0));
    float mr = fetchY(uv + vec2( t.x,  0.0));
    float bl = fetchY(uv + vec2(-t.x,  t.y));
    float bc = fetchY(uv + vec2( 0.0,  t.y));
    float br = fetchY(uv + vec2( t.x,  t.y));

    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);
    return vec2(gx, gy);
}

// Local variance in a 3x3 window
float local_variance3(vec2 uv) {
    vec2 t = texel();
    float m = 0.0, m2 = 0.0;
    for (int j=-1;j<=1;++j)
    for (int i=-1;i<=1;++i) {
        float y = fetchY(uv + vec2(float(i)*t.x, float(j)*t.y));
        m  += y;
        m2 += y*y;
    }
    m  *= 1.0/9.0;
    m2 *= 1.0/9.0;
    return max(m2 - m*m, 0.0);
}

// Compute rawMask at an arbitrary coordinate (for neighborhood percentile approx)
float rawMask_at(vec2 uv) {
    vec2 g = sobel_grad(uv, 1.0);
    float gradMag = length(g);
    float aniso = abs(abs(g.x) - abs(g.y)) / (abs(g.x) + abs(g.y) + 1e-5);
    return clamp(aniso * smoothstep(threshold_low, threshold_high, gradMag), 0.0, 1.0);
}

// Smooth maximum (log-sum-exp) of rawMask over 5x5, k controls sharpness
float smooth_max25_rawMask(vec2 uv, float k) {
    vec2 t = texel();
    float acc = 0.0;
    const int R = 2;
    for (int j=-R;j<=R;++j)
    for (int i=-R;i<=R;++i) {
        vec2 off = vec2(float(i)*t.x, float(j)*t.y);
        float r = rawMask_at(uv + off);
        acc += exp(k * r);
    }
    float meanExp = acc / 25.0;
    return log(meanExp) / k;
}

// Oriented 5-sample median along a line
float median5(float a, float b, float c, float d, float e) {
    float t;
    if (a > b) { t=a; a=b; b=t; }
    if (d > e) { t=d; d=e; e=t; }
    if (a > c) { t=a; a=c; c=t; }
    if (b > c) { t=b; b=c; c=t; }
    if (a > d) { t=a; a=d; d=t; }
    if (c > d) { t=c; c=d; d=t; }
    if (b > e) { t=b; b=e; e=t; }
    if (b > c) { t=b; b=c; c=t; }
    return c;
}

// ------------------------------------------------------------
// Main hook
// ------------------------------------------------------------
vec4 hook() {
    vec2 uv = HOOKED_pos;

    // 1) RGB -> YCbCr601
    vec3 base_rgb = HOOKED_tex(uv).rgb; // linear RGB
    vec3 ycc = rgb_to_ycbcr601(base_rgb);
    float Y  = ycc.x;
    float Cb = ycc.y;
    float Cr = ycc.z;

    // 2) Orientation & anisotropy
    vec2 g1 = sobel_grad(uv, 1.0);
    float gradMag1 = length(g1);
    float anisotropy = abs(abs(g1.x) - abs(g1.y)) / (abs(g1.x) + abs(g1.y) + 1e-5);

    // 3) Multi-scale confirmation
    vec2 g2 = sobel_grad(uv, 2.0);
    float gradMag2 = length(g2);
    float ratio = gradMag2 / (gradMag1 + 1e-5);
    if (ratio > multiscale_ratio) {
        anisotropy *= 0.5;
    }

    // 4) Micro-line mask with neighborhood normalization
    float rawMask = clamp(anisotropy * smoothstep(threshold_low, threshold_high, gradMag1), 0.0, 1.0);
    float M90_local = smooth_max25_rawMask(uv, 6.0);
    float mask = clamp(rawMask / (M90_local + 1e-5), 0.0, 1.0);

    // Scene guards
    float var3 = local_variance3(uv);
    if ((Y > 0.92 || Y < 0.05) && var3 < 0.002) mask *= 0.5;
    if (ratio > multiscale_ratio) mask *= 0.5;

    // Global strength
    mask = clamp(mask * strength, 0.0, 1.0);

    // 5) Directional cleaning (perpendicular oriented median)
    vec2 dir = normalize(g1 + 1e-8);
    vec2 perp = normalize(vec2(-dir.y, dir.x));
    float stepPx = clamp(sigma, 0.75, 1.5);
    vec2 step = perp * texel() * stepPx;

    float s0 = fetchY(uv - 2.0*step);
    float s1 = fetchY(uv - 1.0*step);
    float s2 = Y;
    float s3 = fetchY(uv + 1.0*step);
    float s4 = fetchY(uv + 2.0*step);
    float cleanedY = median5(s0, s1, s2, s3, s4);

    float deltaY = clamp(cleanedY - Y, -delta_max, delta_max);
    float Y_clean = Y + deltaY * mask;

    // 6) Recombine RGB & mask-weighted blend
    vec3 cleaned_rgb = ycbcr601_to_rgb(Y_clean, Cb, Cr);
    float w = pow(mask, 0.6);
    vec3 result = mix(base_rgb, cleaned_rgb, w);

    // 7) Optional debug visualization / Output
#ifdef DEBUG_VIS
    vec3 debug_color;
    debug_color.r = clamp(mask, 0.0, 1.0);
    debug_color.g = clamp(anisotropy, 0.0, 1.0);
    debug_color.b = clamp(mask * 0.7 + anisotropy * 0.3, 0.0, 1.0);
    return vec4(debug_color, 1.0);
#elif defined(DEBUG_GRAY)
    float debug_luma = clamp(mask * 0.7 + anisotropy * 0.3, 0.0, 1.0);
    return vec4(vec3(debug_luma), 1.0);
#else
    return vec4(clamp(result, 0.0, 1.0), 1.0);
#endif
}
