//!PARAM lift
//!TYPE float
0.02

//!PARAM pivot
//!TYPE float
0.10

//!PARAM softness
//!TYPE float
3.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Shadow Lift (black-protected, chroma-safe, tone-map compatible)

vec4 hook() {
    vec3 col = HOOKED_tex(HOOKED_pos).rgb; // already linear in gpu-next

    // Compute luma
    float Y = dot(col, vec3(0.2126, 0.7152, 0.0722));

    // Smooth transition window around pivot
    float w = smoothstep(pivot - pivot / softness,
                         pivot + pivot / softness,
                         Y);

    // **Black floor protection** — don't lift near absolute black
    float floorProtect = smoothstep(0.0, pivot * 0.5, Y);

    // Final lifted luma
    float Y_lifted = mix(Y, Y + lift * (1.0 - w), floorProtect);

    // Reconstruct chroma-preserving RGB
    float scale = (Y > 1e-6) ? (Y_lifted / Y) : 1.0;
    vec3 outc = col * scale;

    return vec4(outc, 1.0);
}
