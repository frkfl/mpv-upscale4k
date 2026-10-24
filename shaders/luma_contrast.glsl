// Black point / levels correction at OUTPUT resolution.
// Removes a DC lift from the shadow end without touching highlights.
// Formula: output = (input - black_in) / (1.0 - black_in)
//
// At input=black_in → 0.0 (true black restored)
// At input=1.0      → 1.0 (white untouched)
// In between: proportionally less correction the brighter the pixel.
//
// lcon_black: the lifted black level to remap to 0. ~0.04–0.08 for typical pedestal.
// lcon_white: input white point (1.0 = no white crush).

//!PARAM lcon_black
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 0.20
0.0

//!PARAM lcon_white
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.0
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Black point / levels correction

vec4 hook() {
    vec4 col = HOOKED_tex(HOOKED_pos);
    vec3 out_rgb = clamp((col.rgb - vec3(lcon_black)) / (lcon_white - lcon_black), 0.0, 1.0);
    return vec4(out_rgb, col.a);
}
