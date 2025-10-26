// ============================================================================
//  perceptual_downscale_refine.glsl
//  Enhances contrast and tone fidelity after mpv handles scaling.
//  Always runs (no width/height override).
// ============================================================================

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Perceptual refinement for mpv scale=1920:1200

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec3 c = HOOKED_tex(uv).rgb;

    // Mild tone re-balance
    c = pow(c, vec3(0.92));  // soften midtones, boost perceptual light

    // Local microcontrast
    vec2 px = 1.0 / HOOKED_size;
    vec3 avg = 0.25 * (
        textureLod(HOOKED_raw, uv + vec2(px.x, 0.0), 0.0).rgb +
        textureLod(HOOKED_raw, uv - vec2(px.x, 0.0), 0.0).rgb +
        textureLod(HOOKED_raw, uv + vec2(0.0, px.y), 0.0).rgb +
        textureLod(HOOKED_raw, uv - vec2(0.0, px.y), 0.0).rgb
    );

    c = mix(avg, c, 1.10);

    // Soft contrast cap (for VHS flattening)
    c = smoothstep(0.02, 0.98, c);

    return vec4(clamp(c, 0.0, 1.0), 1.0);
}
