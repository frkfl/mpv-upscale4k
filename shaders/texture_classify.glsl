//!PARAM tc_strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK MAIN
//!BIND HOOKED
//!SAVE texClass
//!DESC [Custom] Texture classifier

const float skinCb = 0.30;
const float skinCr = 0.35;
const float skinCbR = 0.10;
const float skinCrR = 0.12;
const float edgeGain = 1.5;

vec3 to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;

    // Source in linear
    vec3 lin = to_linear(HOOKED_tex(uv).rgb);

    // Luma & chromas (BT.2020-ish for consistency)
    float Y = dot(lin, vec3(0.2627, 0.6780, 0.0593));
    float Cb = (lin.b - Y) * 0.5 / 0.877 + 0.5;
    float Cr = (lin.r - Y) * 0.5 / 0.701 + 0.5;

    // Neighbor luma taps
    float tl = dot(to_linear(HOOKED_tex(uv + px * vec2(-1,-1)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float tc = dot(to_linear(HOOKED_tex(uv + px * vec2( 0,-1)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float tr = dot(to_linear(HOOKED_tex(uv + px * vec2( 1,-1)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float ml = dot(to_linear(HOOKED_tex(uv + px * vec2(-1, 0)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float mr = dot(to_linear(HOOKED_tex(uv + px * vec2( 1, 0)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float bl = dot(to_linear(HOOKED_tex(uv + px * vec2(-1, 1)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float bc = dot(to_linear(HOOKED_tex(uv + px * vec2( 0, 1)).rgb), vec3(0.2627, 0.6780, 0.0593));
    float br = dot(to_linear(HOOKED_tex(uv + px * vec2( 1, 1)).rgb), vec3(0.2627, 0.6780, 0.0593));

    // Sobel gradient (normalized)
    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);
    float grad = clamp(length(vec2(gx, gy)) * edgeGain * (1.0 / max(px.x + px.y, 1e-6)), 0.0, 1.0);

    // Orientation (normalized [0,1])
    float ang = atan(gy, gx);
    float angN = (ang + 3.14159265) / (6.2831853);

    // Local variance (normalized)
    float mean = (tl+tc+tr+ml+Y+mr+bl+bc+br)/9.0;
    float v = (tl-mean)*(tl-mean) + (tc-mean)*(tc-mean) + (tr-mean)*(tr-mean) +
              (ml-mean)*(ml-mean) + (Y-mean)*(Y-mean) + (mr-mean)*(mr-mean) +
              (bl-mean)*(bl-mean) + (bc-mean)*(bc-mean) + (br-mean)*(br-mean);
    v /= 9.0;
    float varN = clamp(v * 24.0, 0.0, 1.0);

    // Soft skin detector
    float dCb = (Cb - skinCb) / skinCbR;
    float dCr = (Cr - skinCr) / skinCrR;
    float skin = exp(-0.5*(dCb*dCb + dCr*dCr));
    skin *= smoothstep(0.05, 0.35, Y) * (1.0 - smoothstep(0.85, 1.0, Y));

    // Scale everything by strength
    vec4 tex_map = vec4(grad, varN, angN, skin) * tc_strength;

    return tex_map;
}