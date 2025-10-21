
// structured_grain.glsl
// Adds mostly blue-noise + a small oriented, class-aware component.
//   - Skin (A) -> low-freq, anisotropic micro texture
//   - Hair/cloth proxy -> more anisotropy if edges+variance are high
//
//!HOOK MAIN
//!BIND HOOKED
//!BIND texClass
//!DESC texture-aware structured grain (skin/cloth/hair proxy)

// --- user params (tweak live via query args if you like) ---
uniform float strength      = 0.035;  // overall grain power (linear)
uniform float blue_ratio    = 0.85;   // 0..1 (more blue-noise vs. oriented)
uniform float grain_px      = 1.2;    // base grain scale in pixels
uniform float skin_orient   = 0.15;   // oriented fraction for skin
uniform float cloth_orient  = 0.35;   // oriented fraction for non-skin textures
uniform float luma_weight   = 0.85;   // apply mostly to luma

// simple hash -> pseudo blue-noise-ish by local high-pass
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float blue(vec2 uv) {
    // combine a few hashed taps and high-pass them slightly
    float n0 = hash(uv);
    float n1 = hash(uv + 17.0);
    float n2 = hash(uv + 43.0);
    float n  = (n0 + n1 + n2)/3.0;
    // high-pass by subtracting a tiny local average
    float n3 = (hash(uv+vec2(1,0))+hash(uv+vec2(-1,0))+hash(uv+vec2(0,1))+hash(uv+vec2(0,-1)))/4.0;
    return clamp(n - n3, -1.0, 1.0);
}

vec3 to_linear(vec3 c){
    return mix(c/12.92, pow((c+0.055)/1.055, vec3(2.4)), step(0.04045, c));
}
vec3 to_srgb(vec3 c){
    return mix(c*12.92, 1.055*pow(c, vec3(1.0/2.4)) - 0.055, step(0.0031308, c));
}

void main(){
    vec2 pt = HOOKED_pos;
    vec2 px = HOOKED_pt;
    vec3 srgb = HOOKED_tex(pt).rgb;
    vec3 lin  = to_linear(srgb);

    // aux signals
    vec4 aux  = texClass_tex(pt); // R=edge, G=var, B=angle, A=skin
    float edge = aux.r;
    float varA = aux.g;
    float angN = aux.b;
    float skin = aux.a;

    // classify coarse texture type
    float hairCloth = smoothstep(0.35, 0.75, mix(edge, varA, 0.6)); // high edges/variance -> hair/cloth proxy

    // build base blue-like noise (stable in screen space)
    vec2 gUV = pt / px / grain_px; // scale with pixel size
    float nBlue = blue(gUV);

    // build oriented component: project a tiny streak along angle
    float theta = angN * (2.0*3.14159265);
    vec2 dir = vec2(cos(theta), sin(theta));
    float nA = hash(gUV + dir*0.73);
    float nB = hash(gUV - dir*0.41);
    float oriented = (nA - nB); // directional contrast

    // class-aware mix
    float orientAmt = mix(cloth_orient, skin_orient, skin); // less orientation on skin
    float n = mix(nBlue, oriented, orientAmt);

    // strength modulation by texture + midtones
    // compute luma
    float Y = dot(lin, vec3(0.2126,0.7152,0.0722));
    float mid = smoothstep(0.12, 0.85, Y) * (1.0 - smoothstep(0.45, 0.95, Y));
    float texAmt = mix(0.2, 1.0, mix(varA, edge, 0.5));
    float k = strength * mix(1.0, texAmt, 0.6) * (0.6 + 0.4*mid);

    // luma-only bias (to avoid hue drift)
    vec3 lumaDir = vec3(0.2126,0.7152,0.0722);
    float deltaY = n * k * luma_weight;
    lin += deltaY * lumaDir;

    // a touch of chroma texture for cloth/hair (not for skin)
    float chromaK = (1.0 - skin) * (1.0 - blue_ratio) * strength * 0.25;
    lin.r += chromaK * n * 0.5;
    lin.b -= chromaK * n * 0.5;

    // mild energy conservation (keep mean steady)
    lin = clamp(lin, 0.0, 1.0);

    vec3 outc = to_srgb(lin);
    HOOKED = vec4(outc, 1.0);
}
