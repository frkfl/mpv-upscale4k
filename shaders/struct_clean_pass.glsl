#version 450
//!PARAM strength
//!TYPE float
1.00

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Structural Cleaning Reinforcement Pass (v1.2-Extended Deterministic Edition, w-floor fix)

#define RADIUS 4
#define SOBEL_LOW 0.01
#define SOBEL_HIGH 0.25
#define VAR_LOW 0.0005
#define VAR_HIGH 0.002
#define DELTA_CLAMP 0.08
#define W_EXP 0.85
#define W_FLOOR 0.15
#define CHROMA_MIX 0.75
#define EDGE_FALLOFF 0.7

vec3 fetch(vec2 uv) { return HOOKED_tex(uv).rgb; }

float luminance(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float median9(float v[9]) {
    for (int i = 0; i < 9; i++)
        for (int j = i + 1; j < 9; j++)
            if (v[j] < v[i]) { float t = v[i]; v[i] = v[j]; v[j] = t; }
    return v[4];
}

vec4 hook() {
    vec2 texel = 1.0 / HOOKED_size;
    vec2 uv = HOOKED_pos;
    vec3 color = fetch(uv);
    float Y = luminance(color);

    // Sobel gradient
    float gx = 0.0;
    float gy = 0.0;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
        float w_x[3] = float[3](-1.0, 0.0, 1.0);
        float w_y[3] = float[3](-1.0, -2.0, -1.0);
        float w_yy[3] = float[3](1.0, 2.0, 1.0);
        float l = luminance(fetch(uv + vec2(x, y) * texel));
        gx += l * w_x[x + 1] * ((y == 0) ? 2.0 : 1.0);
        gy += l * ((x == 0) ? 2.0 : 1.0) * ((y == -1) ? -1.0 : 1.0);
    }
    vec2 grad = vec2(gx, gy);
    float energy = length(grad);
    float P = clamp((energy - SOBEL_LOW) / (SOBEL_HIGH - SOBEL_LOW), 0.0, 1.0);

    // Variance gate
    float mean = 0.0, var = 0.0;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
        float l = luminance(fetch(uv + vec2(x, y) * texel));
        mean += l;
    }
    mean /= 9.0;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
        float l = luminance(fetch(uv + vec2(x, y) * texel));
        var += (l - mean) * (l - mean);
    }
    var /= 9.0;
    float gate = smoothstep(VAR_LOW, VAR_HIGH, var);
    float mask = P * (1.0 - gate) + P * 0.5 * gate;

    // Directional median cleaning
    vec2 dir = normalize(grad + 1e-5);
    float samples[9];
    samples[4] = Y;
    for (int i = 1; i <= 4; i++) {
        samples[4 + i] = luminance(fetch(uv + dir * float(i) * texel));
        samples[4 - i] = luminance(fetch(uv - dir * float(i) * texel));
    }
    float Y_clean = median9(samples);

    // Correction and reintegration
    float deltaY = clamp(Y_clean - Y, -DELTA_CLAMP, DELTA_CLAMP);
    float w = max(W_FLOOR, pow(P, W_EXP));
    float str = mix(1.0, EDGE_FALLOFF, gate);
    float Y_final = Y + deltaY * w * str * strength;
    vec3 compensated = color * (Y_final / (Y + 1e-5));
    vec3 color_final = mix(color, compensated, CHROMA_MIX);
    color_final = clamp(color_final, 0.0, 1.0);

#ifdef DEBUG_VIS
    return vec4(vec3(P), 1.0);
#elif defined(DEBUG_DIFF)
    return vec4(vec3(abs(deltaY) * 20.0), 1.0);
#else
    return vec4(color_final, 1.0);
#endif
}
