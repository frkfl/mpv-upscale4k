//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Mild temporal blend (TXAA-lite)
//!PARAM float blend_strength = 0.08   // 0.05–0.10 typical
//!PARAM float motion_threshold = 0.15 // 0.10–0.20 typical

/*
 * Blends current frame with the previous one to calm micro-shimmer after upscaling/sharpening.
 * Uses a crude luma-based motion check to reduce trails in moving areas.
 */
vec4 hook() {
    vec4 cur  = HOOKED_tex(HOOKED_pos);
    vec4 prev = PREV_tex(HOOKED_pos);

    // approximate motion from luma difference
    float luma_cur  = dot(cur.rgb,  vec3(0.299, 0.587, 0.114));
    float luma_prev = dot(prev.rgb, vec3(0.299, 0.587, 0.114));
    float motion = abs(luma_cur - luma_prev);

    // less blending when motion is high
    float w = blend_strength * (1.0 - smoothstep(0.0, motion_threshold, motion));

    vec3 blended = mix(cur.rgb, prev.rgb, w);
    return vec4(blended, cur.a);
}

