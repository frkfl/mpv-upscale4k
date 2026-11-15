//!PARAM dm_weight
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.30

//!PARAM dm_shift
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 20.0
0.50

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Diagonal Self-Merge

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;

    // Shift in the (+1,+1) diagonal direction, dm_shift pixels
    vec4 orig    = HOOKED_tex(uv);
    vec4 shifted = HOOKED_tex(uv + vec2(dm_shift) * px);

    // (orig + weight * shifted) / (1 + weight)
    // weight=0 → orig only, weight=1 → 50/50, weight=2 → 1/3 orig + 2/3 shifted
    return clamp((orig + dm_weight * shifted) / (1.0 + dm_weight), 0.0, 1.0);
}
