// DVD MPEG-2 Chroma DCT Deblock
// Hooks the native CHROMA plane (360×240 for NTSC, 360×288 for PAL).
// MPEG-2 DCT operates in 8×8 chroma blocks → boundaries at every 8 chroma pixels
// = every 16×16 luma pixels = the chunky colour patches visible on fine texture.
//
// At each boundary: if the Cb/Cr step is small (encoding artifact) AND luma
// shows no real edge there, blend the two pixels across the line.
// Luma gate prevents smearing real colour edges (e.g. clothing colour change).

//!PARAM dccd_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.80

//!PARAM dccd_threshold
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.20
0.08

//!PARAM dccd_luma_gate
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.15
0.04

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!DESC [DVD] MPEG-2 chroma DCT deblock

vec4 hook() {
    vec2 uv   = HOOKED_pos;
    vec2 pt   = HOOKED_pt;
    vec2 px   = uv * HOOKED_size;
    vec2 bpos = mod(px, 8.0);
    float dh  = min(bpos.x, 8.0 - bpos.x);
    float dv  = min(bpos.y, 8.0 - bpos.y);

    if (dh >= 1.5 && dv >= 1.5) return HOOKED_tex(uv);

    vec2 c      = HOOKED_tex(uv).rg;
    vec2 result = c;

    // Vertical block-line boundaries (horizontal direction)
    if (dh < 1.5) {
        float sx = (bpos.x < 4.0) ? -1.0 : 1.0;
        vec2  nb = HOOKED_tex(uv + vec2(sx * pt.x, 0.0)).rg;

        float l0 = LUMA_tex(uv).r;
        float l1 = LUMA_tex(uv + vec2(sx * LUMA_pt.x, 0.0)).r;
        float lgate = 1.0 - smoothstep(dccd_luma_gate, dccd_luma_gate * 3.0, abs(l0 - l1));

        vec2 blend = vec2(
            step(abs(c.r - nb.r), dccd_threshold),
            step(abs(c.g - nb.g), dccd_threshold)
        ) * lgate * dccd_strength;

        result = mix(result, (c + nb) * 0.5, blend);
    }

    // Horizontal block-line boundaries (vertical direction)
    if (dv < 1.5) {
        float sy = (bpos.y < 4.0) ? -1.0 : 1.0;
        vec2  nb = HOOKED_tex(uv + vec2(0.0, sy * pt.y)).rg;

        float l0 = LUMA_tex(uv).r;
        float l1 = LUMA_tex(uv + vec2(0.0, sy * LUMA_pt.y)).r;
        float lgate = 1.0 - smoothstep(dccd_luma_gate, dccd_luma_gate * 3.0, abs(l0 - l1));

        vec2 blend = vec2(
            step(abs(result.r - nb.r), dccd_threshold),
            step(abs(result.g - nb.g), dccd_threshold)
        ) * lgate * dccd_strength;

        result = mix(result, (result + nb) * 0.5, blend);
    }

    return vec4(result, 0.0, 1.0);
}
