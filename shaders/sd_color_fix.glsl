//!PARAM contrast
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 2.0
1.30

//!PARAM saturation
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.10

//!PARAM gamma
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 3.0
1.20

//!HOOK MAIN
//!BIND HOOKED
//!DESC SD color / luminance correction (BT.601 reference)

vec3 to_bt601(vec3 c) {
    // Converts RGB assuming it was already in BT.601 range
    // just for normalization, no matrix transform required
    return c;
}

vec3 adjust_contrast(vec3 c, float contrast) {
    return (c - 0.5) * contrast + 0.5;
}

vec3 adjust_saturation(vec3 c, float sat) {
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    return mix(vec3(luma), c, sat);
}

vec3 adjust_gamma(vec3 c, float g) {
    return pow(c, vec3(1.0 / g));
}

vec4 hook() {
    vec3 color = HOOKED_tex(HOOKED_pos).rgb;
    color = to_bt601(color);

    // Apply pipeline: contrast → saturation → gamma
    color = adjust_contrast(color, contrast);
    color = adjust_saturation(color, saturation);
    color = adjust_gamma(color, gamma);

    return vec4(clamp(color, 0.0, 1.0), 1.0);
}
