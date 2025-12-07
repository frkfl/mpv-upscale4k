//!PARAM tbm_base_strength
//!TYPE float
0.012

//!PARAM tbm_a_low
//!TYPE float
0.020

//!PARAM tbm_a_high
//!TYPE float
0.350

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Texture Balance Map (TBM-lite v3, plane-aware)

// BT.2020 luma (assume roughly linear-ish here)
float luma_bt2020(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

// RGB <-> YCBCr (BT.2020, full-range-ish)
void rgb_to_ycbcr_bt2020(vec3 rgb, out float Y, out float Cb, out float Cr) {
    Y  = luma_bt2020(rgb);
    Cb = (rgb.b - Y) / 1.8814;
    Cr = (rgb.r - Y) / 1.4746;
}

vec3 ycbcr_to_rgb_bt2020(float Y, float Cb, float Cr) {
    float R = Cr * 1.4746 + Y;
    float B = Cb * 1.8814 + Y;
    float G = (Y - 0.2627 * R - 0.0593 * B) / 0.6780;
    return vec3(R, G, B);
}

float sample_luma(vec2 uv) {
    return luma_bt2020(HOOKED_tex(uv).rgb);
}

// Simple 3×3 blur for coarse luma
float blur3(vec2 uv) {
    vec2 px = 1.0 / HOOKED_size.xy;

    float w0 = 0.25;
    float w1 = 0.125;

    float c = sample_luma(uv) * w0;

    float s = 0.0;
    s += sample_luma(uv + vec2( px.x, 0.0)) * w1;
    s += sample_luma(uv + vec2(-px.x, 0.0)) * w1;
    s += sample_luma(uv + vec2(0.0,  px.y)) * w1;
    s += sample_luma(uv + vec2(0.0, -px.y)) * w1;

    s += sample_luma(uv + vec2( px.x,  px.y)) * w1 * 0.5;
    s += sample_luma(uv + vec2(-px.x,  px.y)) * w1 * 0.5;
    s += sample_luma(uv + vec2( px.x, -px.y)) * w1 * 0.5;
    s += sample_luma(uv + vec2(-px.x, -px.y)) * w1 * 0.5;

    return c + s;
}

// Acutance: HF vs coarse blur
float acutance_norm(vec2 uv) {
    float L  = sample_luma(uv);
    float B3 = blur3(uv);
    float HF = abs(L - B3);

    float A_low  = tbm_a_low;
    float A_high = tbm_a_high;
    float inv_range = 1.0 / max(A_high - A_low, 1e-4);
    return clamp((HF - A_low) * inv_range, 0.0, 1.0);
}

// Pseudo blue-noise-ish hash
float hash21(vec2 p) {
    p = fract(p * vec2(0.1031, 0.11369));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

float blue_noise(vec2 uv) {
    vec2 p = floor(uv * HOOKED_size.xy);
    float n = hash21(p);
    return n * 2.0 - 1.0;
}

// Simple 3×3 smoothing of A_norm
float smooth_A(vec2 uv, float centerA) {
    vec2 px = 1.0 / HOOKED_size.xy;

    float sum = centerA;
    float w   = 1.0;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            if (i == 0 && j == 0) continue;
            vec2 uv_n = uv + vec2(float(i), float(j)) * px;
            float a_n = acutance_norm(uv_n);
            sum += a_n;
            w   += 1.0;
        }
    }

    return sum / w;
}

// Gradient + curvature to find "plane-ish" zones (smooth-but-curved)
void gradient_and_curvature(vec2 uv, out float grad_mag, out float lap) {
    vec2 px = 1.0 / HOOKED_size.xy;

    float Lc  = sample_luma(uv);
    float Lx1 = sample_luma(uv + vec2( px.x, 0.0));
    float Lx2 = sample_luma(uv + vec2(-px.x, 0.0));
    float Ly1 = sample_luma(uv + vec2(0.0,  px.y));
    float Ly2 = sample_luma(uv + vec2(0.0, -px.y));

    float dx = Lx1 - Lx2;
    float dy = Ly1 - Ly2;

    grad_mag = length(vec2(dx, dy));
    lap      = abs(Lx1 + Lx2 + Ly1 + Ly2 - 4.0 * Lc);
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;
    vec3 rgb = HOOKED_tex(uv).rgb;

    float Y, Cb, Cr;
    rgb_to_ycbcr_bt2020(rgb, Y, Cb, Cr);

    // 1. Local texture amount
    float A_n = acutance_norm(uv);      // 0 = flat, 1 = very textured
    float A_s = smooth_A(uv, A_n);

    // 2. Plane mask: smooth-but-curved surfaces
    float grad, lap;
    gradient_and_curvature(uv, grad, lap);

    // "Mid" gradients: ignore totally flat + extreme edges
    float g_mid = smoothstep(0.02, 0.08, grad) *
                  (1.0 - smoothstep(0.12, 0.25, grad));

    // Low curvature (no edge, no bump)
    float curv_low = 1.0 - smoothstep(0.02, 0.08, lap);

    // Strong when: little texture, medium gradient, low curvature
    float plane_mask = (1.0 - A_n) * g_mid * curv_low;

    // 3. Texture need:
    //    - basic: flat areas (1 - A_n)
    //    - balance a bit with neighborhood (1 - A_s)
    //    - extra on plane-ish zones (nose bridge, forehead)
    float need_flat   = 1.0 - A_n;
    float need_region = 1.0 - A_s;
    float texture_need = 0.6 * need_flat + 0.4 * need_region + 0.7 * plane_mask;

    // Tone gating: avoid deep blacks and hot highlights
    float tone = smoothstep(0.08, 0.85, Y);
    texture_need *= tone;

    texture_need = clamp(texture_need, 0.0, 1.5);

    // 4. Balanced micro-texture injection (blue noise)
    float blue = blue_noise(uv);
    float M = blue * texture_need * tbm_base_strength;

    // 5. Apply luma-only perturbation
    float Y_balanced = clamp(Y + M, 0.0, 1.0);

    vec3 rgb_out = ycbcr_to_rgb_bt2020(Y_balanced, Cb, Cr);
    rgb_out = clamp(rgb_out, 0.0, 1.0);

    return vec4(rgb_out, 1.0);
}
