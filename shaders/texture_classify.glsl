
// texture_classify.glsl
// Builds an aux map in RGBA:
//   R = edge magnitude (0..1)
//   G = local variance (0..1) ~ "texture amount"
//   B = orientation angle (0..1) = (atan2(gy,gx)+pi)/(2pi)
//   A = soft skin mask (YCbCr ellipse)
//
//!HOOK MAIN
//!BIND HOOKED
//!SAVE texClass
//!DESC texture classification (edge/var/orient/skin)

// --- params you might tune ---
#define CS_BT709 1
const float skinCb = 0.30;   // approx center (normalized 0..1)
const float skinCr = 0.35;   // approx center (normalized 0..1)
const float skinCbR= 0.10;   // ellipse radii
const float skinCrR= 0.12;
const float edgeGain = 1.5;  // boosts edge/variance metrics

vec3 to_linear(vec3 c) { // sRGB-ish
    return mix(c/12.92, pow((c+0.055)/1.055, vec3(2.4)), step(0.04045, c));
}

void main() {
    vec2 pt = HOOKED_pos;
    vec2 px = HOOKED_pt; // 1/textureSize

    // Source (assume display-referred, convert to linear once)
    vec3 srgb = HOOKED_tex(pt).rgb;
    vec3 lin  = to_linear(srgb);

    // YCbCr (BT.709 matrix in linear domain)
    float Y  = 0.2126*lin.r + 0.7152*lin.g + 0.0722*lin.b;
    float Cb = (lin.b - Y)*0.5/0.877 + 0.5; // cheap normalized Cb/Cr
    float Cr = (lin.r - Y)*0.5/0.701 + 0.5;

    // Sobel gradient on Y
    float tl = to_linear(HOOKED_tex(pt+px*vec2(-1,-1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2(-1,-1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2(-1,-1)).rgb).b*0.0722;
    float tc = to_linear(HOOKED_tex(pt+px*vec2( 0,-1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2( 0,-1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2( 0,-1)).rgb).b*0.0722;
    float tr = to_linear(HOOKED_tex(pt+px*vec2( 1,-1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2( 1,-1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2( 1,-1)).rgb).b*0.0722;
    float ml = to_linear(HOOKED_tex(pt+px*vec2(-1, 0)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2(-1, 0)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2(-1, 0)).rgb).b*0.0722;
    float mr = to_linear(HOOKED_tex(pt+px*vec2( 1, 0)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2( 1, 0)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2( 1, 0)).rgb).b*0.0722;
    float bl = to_linear(HOOKED_tex(pt+px*vec2(-1, 1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2(-1, 1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2(-1, 1)).rgb).b*0.0722;
    float bc = to_linear(HOOKED_tex(pt+px*vec2( 0, 1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2( 0, 1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2( 0, 1)).rgb).b*0.0722;
    float br = to_linear(HOOKED_tex(pt+px*vec2( 1, 1)).rgb).r*0.2126 + to_linear(HOOKED_tex(pt+px*vec2( 1, 1)).rgb).g*0.7152 + to_linear(HOOKED_tex(pt+px*vec2( 1, 1)).rgb).b*0.0722;

    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);
    float grad = clamp(length(vec2(gx, gy))*edgeGain, 0.0, 1.0);
    float ang  = atan(gy, gx); // -pi..pi
    float angN = (ang + 3.14159265) / (2.0*3.14159265); // 0..1

    // Local 3x3 variance on Y (quick)
    float mean = (tl+tc+tr+ml+Y+mr+bl+bc+br)/9.0;
    float v = ( (tl-mean)*(tl-mean)+(tc-mean)*(tc-mean)+(tr-mean)*(tr-mean)+
                (ml-mean)*(ml-mean)+(Y -mean)*(Y -mean)+(mr-mean)*(mr-mean)+
                (bl-mean)*(bl-mean)+(bc-mean)*(bc-mean)+(br-mean)*(br-mean) )/9.0;
    float varN = clamp(v*24.0, 0.0, 1.0); // scaled to taste

    // Soft skin ellipse in Cb/Cr
    float dCb = (Cb - skinCb) / skinCbR;
    float dCr = (Cr - skinCr) / skinCrR;
    float skin = exp(-0.5*(dCb*dCb + dCr*dCr)); // 0..1 soft

    vec4 outv = vec4(grad, varN, angN, skin);
    texClass = outv;
    HOOKED = outv; // visualize if you want; otherwise, ignore
}
