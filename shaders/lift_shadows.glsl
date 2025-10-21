//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Shadow Lift (gentle, perceptual)
//!PARAM float lift = 0.02
//!PARAM float pivot = 0.10
//!PARAM float softness = 3.0

vec4 hook() {
    vec3 c = HOOKED_tex(HOOKED_pos).rgb;
    vec3 y = pow(c, vec3(2.2)); // linearize
    float L = dot(y, vec3(0.2126, 0.7152, 0.0722));
    float w = smoothstep(pivot - pivot/softness, pivot + pivot/softness, L);
    y = mix(y + lift*(1.0 - w), y, w);
    return vec4(pow(y, vec3(1.0/2.2)), 1.0);
}

