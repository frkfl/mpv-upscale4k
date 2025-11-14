#version 450

//!PARAM base_strength
//!TYPE float
0.015

//!PARAM acutance_gain
//!TYPE float
4.0

//!PARAM max_boost
//!TYPE float
0.6

//!PARAM max_cut
//!TYPE float
0.3

//!PARAM tone_low
//!TYPE float
0.08

//!PARAM tone_high
//!TYPE float
0.90

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Texture Balance Map (local acutance equalizer)

vec3 fetch_rgb(vec2 uv) {
    return HOOKED_tex(uv).rgb;
}

float luma_bt2020(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

vec4 hook() {
    vec2 uv  = HOOKED_pos;
    vec2 px  = 1.0 / HOOKED_size.xy;

    vec3 rgb = fetch_rgb(uv);
    float Y0 = luma_bt2020(rgb);

    // Multi-scale local blurs via concentric averages
    float b1 = 0.0;
    float b2 = 0.0;
    float b3 = 0.0;

    // Radius 1 sample cross
    {
        float acc = Y0;
        acc += luma_bt2020(fetch_rgb(uv + vec2( px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(-px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0,  px.y)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0, -px.y)));
        b1 = acc / 5.0;
    }

    // Radius 2 sample cross
    {
        float acc = Y0;
        acc += luma_bt2020(fetch_rgb(uv + vec2( 2.0 * px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(-2.0 * px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0,  2.0 * px.y)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0, -2.0 * px.y)));
        b2 = acc / 5.0;
    }

    // Radius 4 sample cross
    {
        float acc = Y0;
        acc += luma_bt2020(fetch_rgb(uv + vec2( 4.0 * px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(-4.0 * px.x, 0.0)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0,  4.0 * px.y)));
        acc += luma_bt2020(fetch_rgb(uv + vec2(0.0, -4.0 * px.y)));
        b3 = acc / 5.0;
    }

    float HF1 = abs(Y0 - b1);
    float HF2 = abs(b1 - b2);
    float HF3 = abs(b2 - b3);

    float A = 0.15 * HF1 + 0.65 * HF2 + 0.20 * HF3;

    float A_norm = clamp(A * acutance_gain, 0.0, 1.0);

    // Neighborhood texture density (smoothed acutance)
    float T = 0.0;
    {
        float w_sum = 0.0;
        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                vec2 offs = vec2(float(dx), float(dy)) * px * 2.0;
                float w = 1.0;
                if (abs(dx) + abs(dy) == 0) w = 2.0;
                float Ay = clamp(
                    (0.15 * abs(luma_bt2020(fetch_rgb(uv + offs)) -
                                luma_bt2020(fetch_rgb(uv + offs + vec2(px.x, 0.0)))) +
                     0.65 * HF2 +
                     0.20 * HF3) * acutance_gain,
                    0.0, 1.0);
                T += Ay * w;
                w_sum += w;
            }
        }
        T /= max(w_sum, 1e-4);
    }

    float texture_need = T - A_norm;
    float max_cut_clamped = max_cut;
    float max_boost_clamped = max_boost;
    texture_need = clamp(texture_need, -max_cut_clamped, max_boost_clamped);

    // Blue-noise based microtexture
    vec2 ip = HOOKED_pos * HOOKED_size.xy;
    float n = hash21(ip + vec2(17.13, 47.79)) * 2.0 - 1.0;

    float tone = smoothstep(tone_low, tone_high, Y0);
    float M = n * tone * texture_need * base_strength;

    float Y_new = clamp(Y0 + M, 0.0, 1.0);
    float dY = Y_new - Y0;
    vec3 out_rgb = clamp(rgb + vec3(dY), 0.0, 1.0);

    return vec4(out_rgb, 1.0);
}
