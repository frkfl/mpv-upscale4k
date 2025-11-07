//!HOOK OUTPUT
//!BIND HOOKED_raw
//!SAVE texClass
//!DESC Texture classification (edge/variance/orientation/skin)

// parameter tuning (normal BT.709 skin cluster)
const float skinCb = 0.30;
const float skinCr = 0.35;
const float skinCbR = 0.10;
const float skinCrR = 0.12;
const float edgeGain = 1.5;

vec3 to_linear(vec3 c) {
    return mix(c/12.92, pow((c+0.055)/1.055, vec3(2.4)), step(0.04045, c));
}

void main() {
    vec2 pt = HOOKED_pos;
    vec2 px = HOOKED_pt; // 1 / resolution

    // Source → linear once
    vec3 lin = to_linear(HOOKED_raw_tex(pt).rgb);

    // Luma
    float Y = dot(lin, vec3(0.2126, 0.7152, 0.0722));

    // Cb/Cr (normalized)
    float Cb = (lin.b - Y)*0.5/0.877 + 0.5;
    float Cr = (lin.r - Y)*0.5/0.701 + 0.5;

    // Neighbor Y taps (relinearize once, but reusing same function)
    float tl = dot(to_linear(HOOKED_tex(pt+px*vec2(-1,-1)).rgb), vec3(0.2126,0.7152,0.0722));
    float tc = dot(to_linear(HOOKED_tex(pt+px*vec2( 0,-1)).rgb), vec3(0.2126,0.7152,0.0722));
    float tr = dot(to_linear(HOOKED_tex(pt+px*vec2( 1,-1)).rgb), vec3(0.2126,0.7152,0.0722));
    float ml = dot(to_linear(HOOKED_tex(pt+px*vec2(-1, 0)).rgb), vec3(0.2126,0.7152,0.0722));
    float mr = dot(to_linear(HOOKED_tex(pt+px*vec2( 1, 0)).rgb), vec3(0.2126,0.7152,0.0722));
    float bl = dot(to_linear(HOOKED_tex(pt+px*vec2(-1, 1)).rgb), vec3(0.2126,0.7152,0.0722));
    float bc = dot(to_linear(HOOKED_tex(pt+px*vec2( 0, 1)).rgb), vec3(0.2126,0.7152,0.0722));
    float br = dot(to_linear(HOOKED_tex(pt+px*vec2( 1, 1)).rgb), vec3(0.2126,0.7152,0.0722));

    // Sobel gradient
    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);

    // Normalize for resolution → stable at low res
    float grad = clamp(length(vec2(gx, gy)) * edgeGain * (1.0 / max(px.x + px.y, 1e-6)), 0.0, 1.0);

    // Safe orientation angle
    float ang = atan(gy, gx);
    float angN = (ang + 3.14159265) / (6.2831853);

    // Local variance
    float mean = (tl+tc+tr+ml+Y+mr+bl+bc+br)/9.0;
    float v = (tl-mean)*(tl-mean)+(tc-mean)*(tc-mean)+(tr-mean)*(tr-mean)+
              (ml-mean)*(ml-mean)+(Y-mean)*(Y-mean)+(mr-mean)*(mr-mean)+
              (bl-mean)*(bl-mean)+(bc-mean)*(bc-mean)+(br-mean)*(br-mean);
    v /= 9.0;
    float varN = clamp(v * 24.0, 0.0, 1.0);

    // Soft skin detector, adaptive to luminance so dark/bright scenes don't go "grey"
    float dCb = (Cb - skinCb) / skinCbR;
    float dCr = (Cr - skinCr) / skinCrR;
    float skin = exp(-0.5*(dCb*dCb + dCr*dCr));
    skin *= smoothstep(0.05, 0.35, Y) * (1.0 - smoothstep(0.85, 1.0, Y));

    // Output auxiliary map
    texClass = vec4(grad, varN, angN, skin);

    // DO NOT MODIFY HOOKED! (prevents visible tinting)
    // leave HOOKED untouched
}
