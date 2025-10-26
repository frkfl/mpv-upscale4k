//!PARAM strength
//!TYPE float
1.25

//!PARAM radius
//!TYPE float
1.5

//!PARAM gamma_in
//!TYPE float
1.0

//!PARAM gamma_out
//!TYPE float
1.0

//!PARAM lobe_strength
//!TYPE float
0.65

//!PARAM lobe_threshold
//!TYPE float
0.015

//!PARAM lobe_priority
//!TYPE float
0.65

//!PARAM delta_cap
//!TYPE float
0.50

//!PARAM apply_threshold
//!TYPE float
0.02

//!PARAM noise_strength
//!TYPE float
0.003

//!HOOK MAIN
//!BIND HOOKED
//!DESC Unified anti-ringing (box + phase-gated lobe + adaptive temporal micro-noise)

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Fast hash-based high-frequency noise
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    ivec2 ts = textureSize(HOOKED_raw, 0);
    vec2 px = 1.0 / vec2(ts);

    // --- Temporal noise phase ---
    float t = mod(float(frame), 8192.0);
    float noise_phase = hash12(vec2(t * 0.013, t * 0.007));

    // --- Load source and linearize ---
    vec3 src = pow(HOOKED_tex(uv).rgb, vec3(gamma_in));
    float lc = luma(src);

    // --- Adaptive noise amplitude: fade in midtones only ---
    float adapt = smoothstep(0.1, 0.4, lc) * (1.0 - smoothstep(0.65, 0.95, lc));

    // --- Pre-mix decorrelating noise ---
    float n_pre = (hash12(uv * vec2(ts) + noise_phase * 17.17) - 0.5) * 2.0;
    float noise_pre = n_pre * noise_strength * adapt;
    lc += noise_pre;

    // ---------------------------------------------------------------------
    // Box statistics (edge-aware)
    // ---------------------------------------------------------------------
    float minL = 1.0, maxL = 0.0, sumL = 0.0;
    int cnt = 0;
    for (float y = -radius; y <= radius; y++) {
        for (float x = -radius; x <= radius; x++) {
            vec2 offs = vec2(x, y) * px;
            vec3 s = pow(HOOKED_tex(uv + offs).rgb, vec3(gamma_in));
            float l = luma(s) + (hash12(uv + offs * 13.1) - 0.5) * noise_strength * 0.5;
            minL = min(minL, l);
            maxL = max(maxL, l);
            sumL += l;
            cnt++;
        }
    }
    float meanL  = sumL / float(cnt);
    float rangeL = max(maxL - minL, 1e-4);

    // ---------------------------------------------------------------------
    // Box limiter
    // ---------------------------------------------------------------------
    float low   = mix(lc, minL, strength);
    float high  = mix(lc, maxL, strength);
    float p1    = clamp(lc, low, high);

    float d1 = clamp(p1 - lc, -delta_cap * rangeL, delta_cap * rangeL);
    p1 = lc + d1;

    float outside = max(max(lc - maxL, 0.0), max(minL - lc, 0.0));
    float c1 = smoothstep(0.05 * rangeL, 0.6 * rangeL, outside);

    // ---------------------------------------------------------------------
    // Lobe limiter (phase-gated)
    // ---------------------------------------------------------------------
    float Ll = luma(HOOKED_tex(uv - vec2(px.x, 0.0)).rgb);
    float Rr = luma(HOOKED_tex(uv + vec2(px.x, 0.0)).rgb);
    float Uu = luma(HOOKED_tex(uv - vec2(0.0, px.y)).rgb);
    float Dd = luma(HOOKED_tex(uv + vec2(0.0, px.y)).rgb);

    float dx = (Rr - Ll) * 0.5;
    float dy = (Dd - Uu) * 0.5;
    float grad = sqrt(dx * dx + dy * dy);
    float lap = (Ll + Rr + Uu + Dd) - 4.0 * lc;

    float dev_norm = abs(lap) / max(rangeL, 1e-4);
    float phase_rel = sign(lap) * sign(lc - meanL);
    float phase_gate = step(0.0, -phase_rel);

    float c2 = smoothstep(lobe_threshold, lobe_threshold * 4.0, dev_norm)
             * (1.0 - smoothstep(0.05, 0.25, grad))
             * phase_gate;

    float p2_raw = lc - lobe_strength * lap * 0.25;
    float d2 = clamp(p2_raw - lc, -delta_cap * rangeL, delta_cap * rangeL);
    float p2 = lc + d2;

    // ---------------------------------------------------------------------
    // Weighted blend (box + lobe)
    // ---------------------------------------------------------------------
    float w1 = c1 * (1.0 - lobe_priority);
    float w2 = c2 * (0.5 + 0.5 * lobe_priority);
    float ws = w1 + w2;

    float target = lc;
    if (ws > 1e-6) {
        float a1 = w1 / ws;
        float a2 = w2 / ws;
        target = lc + a1 * (p1 - lc) + a2 * (p2 - lc);
    }

    // ---------------------------------------------------------------------
    // Apply and clamp
    // ---------------------------------------------------------------------
    float apply = step(apply_threshold * rangeL, abs(target - lc));
    float newL  = mix(lc, target, apply);
    newL = clamp(newL, 1e-5, 1.05);

    // ---------------------------------------------------------------------
    // Recombine and add post-mix adaptive noise
    // ---------------------------------------------------------------------
    float scale = newL / max(lc, 1e-5);
    vec3 outRGB = pow(clamp(src * scale, 0.0, 1.2), vec3(1.0 / gamma_out));

    vec3 n3 = vec3(hash12(uv * vec2(231.1, 91.7) + noise_phase) - 0.5);
    float n_post_amp = noise_strength * 1.5 * adapt;
    outRGB += n3 * n_post_amp;

    return vec4(clamp(outRGB, 0.0, 1.0), 1.0);
}
