// DVD MPEG-2 Luma DCT Deblock
// Hooks the native LUMA plane (720×480 NTSC, 720×576 PAL).
// MPEG-2 DCT in 8×8 luma blocks → boundaries at every 8 luma pixels.
// Blends across block boundaries where the step is small (artifact, not edge).

//!PARAM dcld_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.60

//!PARAM dcld_threshold
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.20
0.06

//!HOOK LUMA
//!BIND HOOKED
//!DESC [DVD] MPEG-2 luma DCT deblock

vec4 hook() {
    vec2  uv    = HOOKED_pos;
    vec2  pt    = HOOKED_pt;
    vec2  px    = uv * HOOKED_size;
    vec2  bpos  = mod(px, 8.0);
    float dh    = min(bpos.x, 8.0 - bpos.x);
    float dv    = min(bpos.y, 8.0 - bpos.y);

    if (dh >= 1.5 && dv >= 1.5) return HOOKED_tex(uv);

    float luma   = HOOKED_tex(uv).r;
    float result = luma;

    if (dh < 1.5) {
        // bpos.x < 4 → first half of block → boundary is to the LEFT → sx = -1
        // bpos.x ≥ 4 → second half          → boundary is to the RIGHT → sx = +1
        float sx    = (bpos.x < 4.0) ? -1.0 : 1.0;
        float nb    = HOOKED_tex(uv + vec2(sx * pt.x, 0.0)).r;
        float blend = step(abs(luma - nb), dcld_threshold) * dcld_strength;
        result = mix(result, (luma + nb) * 0.5, blend);
    }

    if (dv < 1.5) {
        float sy    = (bpos.y < 4.0) ? -1.0 : 1.0;
        float nb    = HOOKED_tex(uv + vec2(0.0, sy * pt.y)).r;
        float blend = step(abs(result - nb), dcld_threshold) * dcld_strength;
        result = mix(result, (result + nb) * 0.5, blend);
    }

    return vec4(result, 0.0, 0.0, 1.0);
}
