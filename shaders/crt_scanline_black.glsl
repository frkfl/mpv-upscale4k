// CRT black scanline - one darkened line every sl2_period output pixels.
// Darkness varies by luma zone: shadows/mids/highlights get independent control.
// This lets bright areas read as texture rather than hard black lines.
//
// sl2_period:   line spacing in output pixels (e.g. 4 = 1 line per 4px at 4K)
// sl2_strength: global multiplier (0.0 = off, 1.0 = full)
// sl2_dark:     darkness in shadows  (luma 0.0 - 0.5)
// sl2_mid:      darkness in midtones (luma ~0.5)
// sl2_bright:   darkness in highlights (luma 0.5 - 1.0)

//!PARAM sl2_period
//!TYPE float
//!MINIMUM 2.0
//!MAXIMUM 20.0
4.0

//!PARAM sl2_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM sl2_dark
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.80

//!PARAM sl2_mid
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.60

//!PARAM sl2_bright
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.30

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [CRT] Black scanline

vec4 hook() {
    vec4 col = HOOKED_tex(HOOKED_pos);

    float py    = floor(HOOKED_pos.y * HOOKED_size.y);
    float phase = mod(py, sl2_period);

    if (phase < 1.0) {
        float luma = dot(col.rgb, vec3(0.2126, 0.7152, 0.0722));

        float w_dark   = clamp(1.0 - 2.0 * luma, 0.0, 1.0);
        float w_bright = clamp(2.0 * luma - 1.0, 0.0, 1.0);
        float w_mid    = 1.0 - w_dark - w_bright;

        float darkness = sl2_dark * w_dark + sl2_mid * w_mid + sl2_bright * w_bright;
        darkness *= sl2_strength;

        col.rgb *= (1.0 - darkness);
    }

    return col;
}
