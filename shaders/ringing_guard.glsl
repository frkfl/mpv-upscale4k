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

//!HOOK MAIN
//!BIND HOOKED
//!DESC Unified anti-ringing (box + phase-gated lobe, FP16-safe)

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 hook() {
    vec2 uv = HOOKED_pos;
    ivec2 ts = textureSize(HOOKED_raw, 0);
    vec2 px = 1.0 / vec2(ts);

    // Work in linear light
    vec3 src = pow(HOOKED_tex(uv).rgb, vec3(gamma_in));
    float lc  = luma(src);

    // ---------------------------------------------------------------------
    // Box statistics (for box limiter + range normalization)
    // ---------------------------------------------------------------------
    float minL = 1.0, maxL = 0.0, sumL = 0.0;
    int cnt = 0;
    for (float y = -radius; y <= radius; y++) {
        for (float x = -radius; x <= radius; x++) {
            vec3 s = pow(HOOKED_tex(uv + vec2(x, y) * px).rgb, vec3(gamma_in));
            float l = luma(s);
            minL = min(minL, l);
            maxL = max(maxL, l);
            sumL += l;
            cnt++;
        }
    }
    float meanL  = sumL / float(cnt);
    float rangeL = max(maxL - minL, 1e-4);

    // ---------------------------------------------------------------------
    // Box limiter proposal
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

    // Phase gating: only act when oscillation opposes local mean direction
    float phase = sign(lap) * sign(lc - meanL);
    float phase_gate = step(0.0, -phase); // activate if out-of-phase

    float c2 = smoothstep(lobe_threshold, lobe_threshold * 4.0, dev_norm)
             * (1.0 - smoothstep(0.05, 0.25, grad))
             * phase_gate;

    float p2_raw = lc - lobe_strength * lap * 0.25;
    float d2 = clamp(p2_raw - lc, -delta_cap * rangeL, delta_cap * rangeL);
    float p2 = lc + d2;

    // ---------------------------------------------------------------------
    // Weighted blend (box + lobe) with priority
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
    // Apply only if significant change
    // ---------------------------------------------------------------------
    float apply = step(apply_threshold * rangeL, abs(target - lc));
    float newL  = mix(lc, target, apply);

    newL = clamp(newL, 1e-5, 1.05);

    float scale = newL / max(lc, 1e-5);
    vec3 outRGB = pow(clamp(src * scale, 0.0, 1.2), vec3(1.0 / gamma_out));

    return vec4(clamp(outRGB, 0.0, 1.0), 1.0);
}
