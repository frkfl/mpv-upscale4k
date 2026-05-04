// Bayer 8x8 ordered RGB dither.
// Applies structured chromatic dither to break flat digital appearance.
// R/G/B channels are offset horizontally within the Bayer matrix to
// simulate CRT phosphor triad spacing at sub-pixel scale.
// At 4K the 8px matrix period is below visual acuity at viewing distance;
// downstream grain shuffles the static geometry frame to frame.
//
// bd_amplitude:     dither strength in linear light (~0.01 subtle, 0.02 visible)
// bd_chroma_offset: horizontal Bayer offset per channel (0 = luma-only, 2 = triad)
// bd_mix:           blend between source (0.0) and dithered (1.0)

//!PARAM bd_amplitude
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.05
0.015

//!PARAM bd_chroma_offset
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 4.0
2.0

//!PARAM bd_mix
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.5

//!HOOK MAIN
//!BIND HOOKED
//!DESC [CRT] Bayer RGB dither

const int bayer8x8[64] = int[64](
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
);

float bayer_val(ivec2 pos) {
    int idx = (pos.y & 7) * 8 + (pos.x & 7);
    return float(bayer8x8[idx]) / 63.0 - 0.5;
}

vec4 hook() {
    vec4 col  = HOOKED_tex(HOOKED_pos);
    vec3 src  = col.rgb;
    ivec2 px  = ivec2(HOOKED_pos * HOOKED_size);
    int   off = int(bd_chroma_offset);

    col.r += bd_amplitude * bayer_val(px);
    col.g += bd_amplitude * bayer_val(px + ivec2(off, 0));
    col.b += bd_amplitude * bayer_val(px + ivec2(off * 2, 0));

    col.rgb = mix(src, clamp(col.rgb, 0.0, 1.0), bd_mix);
    return col;
}
