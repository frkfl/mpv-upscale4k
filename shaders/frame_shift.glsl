//!PARAM fsh_x
//!TYPE float
//!MINIMUM -20.0
//!MAXIMUM 20.0
0.0

//!PARAM fsh_y
//!TYPE float
//!MINIMUM -20.0
//!MAXIMUM 20.0
0.5

//!PARAM fsh_every
//!TYPE int
//!MINIMUM 1
//!MAXIMUM 16
2

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC [Custom] Frame Shift

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;

    if (frame % uint(fsh_every) == 0u) {
        uv += vec2(fsh_x, fsh_y) * px;
    }

    return HOOKED_tex(uv);
}
