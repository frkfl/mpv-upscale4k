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
//!DESC Texture Balance Map (TBM)

// BT.2020 linear luma
float luma_bt2020(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

// RGB <-> YCBCr (BT.2020, full-range style, approximate)
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

// Sample luma from HOOKED
float sample_luma(vec2 uv) {
    return luma_bt2020(HOOKED_tex(uv).rgb);
}

// Simple multi-radius blur helpers (resolution-independent, approximate)
float blur_luma_radius(vec2 uv, float radius_px) {
    vec2 px = 1.0 / HOOKED_size.xy;
    vec2 step = px * radius_px;

    float w0 = 0.4;
    float w1 = 0.15;
    float w2 = 0.05;

    float c = sample_luma(uv) * w0;

    float s = 0.0;
    s += sample_luma(uv + vec2( step.x, 0.0)) * w1;
    s += sample_luma(uv + vec2(-step.x, 0.0)) * w1;
    s += sample_luma(uv + vec2(0.0,  step.y)) * w1;
    s += sample_luma(uv + vec2(0.0, -step.y)) * w1;

    s += sample_luma(uv + vec2( step.x,  step.y)) * w2;
    s += sample_luma(uv + vec2(-step.x,  step.y)) * w2;
    s += sample_luma(uv + vec2( step.x, -step.y)) * w2;
    s += sample_luma(uv + vec2(-step.x, -step.y)) * w2;

    float norm = w0 + 4.0 * w1 + 4.0 * w2;
    return (c + s) / norm;
}

float blur3(vec2 uv)  { return blur_luma_radius(uv, 1.0); }
float blur7(vec2 uv)  { return blur_luma_radius(uv, 3.0); }
float blur15(vec2 uv) { return blur_luma_radius(uv, 7.0); }

// Multi-scale acutance A (HF energy)
float acutance_raw(vec2 uv) {
    float L  = sample_luma(uv);
    float B3 = blur3(uv);
    float B7 = blur7(uv);
    float B15 = blur15(uv);

    float HF1 = abs(L   - B3);
    float HF2 = abs(B3  - B7);
    float HF3 = abs(B7  - B15);

    return 0.15 * HF1 + 0.65 * HF2 + 0.20 * HF3;
}

// Normalized acutance A_norm (0–1), global range approximation
float acutance_norm(vec2 uv) {
    float A = acutance_raw(uv);
    float A_low = tbm_a_low;
    float A_high = tbm_a_high;
    float inv_range = 1.0 / max(A_high - A_low, 1e-4);
    return clamp((A - A_low) * inv_range, 0.0, 1.0);
}

// Pseudo blue-noise-ish hash, temporally stable per pixel
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

// Bilateral blur of A_norm (T-map)
float bilateral_blur_A(vec2 uv, float centerA) {
    vec2 px = 1.0 / HOOKED_size.xy;

    float sigma_s = 6.0;
    float sigma_r = 0.15;
    float inv_two_sigma_s2 = 1.0 / (2.0 * sigma_s * sigma_s);
    float inv_two_sigma_r2 = 1.0 / (2.0 * sigma_r * sigma_r);

    float sum_w = 0.0;
    float sum_a = 0.0;

    for (int j = -3; j <= 3; j++) {
        for (int i = -3; i <= 3; i++) {
            vec2 d = vec2(float(i), float(j));
            float r2 = dot(d, d);
            float w_s = exp(-r2 * inv_two_sigma_s2);

            vec2 uv_n = uv + d * px;
            float a_n = acutance_norm(uv_n);
            float dr = a_n - centerA;
            float w_r = exp(-(dr * dr) * inv_two_sigma_r2);

            float w = w_s * w_r;
            sum_w += w;
            sum_a += a_n * w;
        }
    }

    return sum_a / max(sum_w, 1e-6);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec3 rgb = HOOKED_tex(uv).rgb;

    float Y, Cb, Cr;
    rgb_to_ycbcr_bt2020(rgb, Y, Cb, Cr);

    // 1. Local acutance (A-map) and normalization
    float A_n = acutance_norm(uv);

    // 2. Texture density normalization (T-map)
    float T = bilateral_blur_A(uv, A_n);
    float texture_need = T - A_n;
    texture_need = clamp(texture_need, -0.4, 0.6);

    // 3. Balanced micro-texture injection (M-map)
    float blue = blue_noise(uv);

    float tone = smoothstep(0.1, 0.9, Y);
    tone = pow(tone, 0.6);

    float M = blue * tone * texture_need * tbm_base_strength;

    // 4. Detail-consistent blending, luma-only
    float Y_balanced = clamp(Y + M, 0.0, 1.0);

    vec3 rgb_out = ycbcr_to_rgb_bt2020(Y_balanced, Cb, Cr);
    rgb_out = clamp(rgb_out, 0.0, 1.0);

    return vec4(rgb_out, 1.0);
}
