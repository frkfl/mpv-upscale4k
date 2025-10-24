
//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Skin Tone Tamer (OkLab L-aware sat compression)
//!PARAM float strength = 0.35   // 0..0.7 global compression in skin band
//!PARAM float hue_center = 0.07 // ~25° (orange). 0..1 HSV-like hue
//!PARAM float hue_width  = 0.12 // width around center; 0.08..0.16 typical
//!PARAM float L_low = 0.45      // start compressing above this lightness (lighter browns)
//!PARAM float L_high = 0.85     // full effect by this lightness
//!PARAM float mid_bias = 0.6    // emphasize mid-sat more than very low/high sat
//!PARAM float gamma_in = 1.0
//!PARAM float gamma_out = 1.0

vec3 toLin(vec3 c,float g){return pow(max(c,0.0),vec3(g>0.0?1.0/g:1.0));}
vec3 toGam(vec3 c,float g){return pow(max(c,0.0),vec3(g>0.0?g:1.0));}

// sRGB linear <-> OkLab (Björn Ottosson)
mat3 M1 = mat3( 0.4122214708, 0.5363325363, 0.0514459929,
                0.2119034982, 0.6806995451, 0.1073969566,
                0.0883024619, 0.2817188376, 0.6299787005);
mat3 M2 = mat3( 0.2104542553, 0.7936177850, -0.0040720468,
                1.9779984951,-2.4285922050,  0.4505937099,
                0.0259040371, 0.7827717662, -0.8086757660);
mat3 Mi = mat3( 4.0767416621,-3.3077115913, 0.2309699292,
               -1.2684380046, 2.6097574011,-0.3413193965,
                0.0041960863,-0.7034186147, 1.6996226760);

vec3 linear_srgb_to_oklab(vec3 c){
    vec3 lms = pow(M1*c, vec3(1.0/3.0));
    return M2*lms;
}
vec3 oklab_to_linear_srgb(vec3 LLab){
    float L = LLab.x, a = LLab.y, b = LLab.z;
    float l = (L + 0.3963377774*a + 0.2158037573*b);
    float m = (L - 0.1055613458*a - 0.0638541728*b);
    float s = (L - 0.0894841775*a - 1.2914855480*b);
    l = l*l*l; m = m*m*m; s = s*s*s;
    return Mi*vec3(l,m,s);
}

// quick hue in [0,1] from linear RGB (HSV-like, sufficient for gating)
float hue_of(vec3 lin){
    float M = max(max(lin.r, lin.g), lin.b);
    float m = min(min(lin.r, lin.g), lin.b);
    float C = max(M - m, 1e-6);
    vec3 n = (lin - m)/C;
    float h = (M==lin.r)? (n.g - n.b) :
              (M==lin.g)? (2.0 + n.b - n.r) :
                          (4.0 + n.r - n.g);
    h = fract((h/6.0)+1.0);
    return h;
}

vec4 hook(){
    vec3 srgb = HOOKED_tex(HOOKED_pos).rgb;
    vec3 lin  = toLin(srgb, gamma_in);

    vec3 lab = linear_srgb_to_oklab(lin);
    float L = clamp(lab.x, 0.0, 1.0);
    float a = lab.y, b = lab.z;

    // skin hue gate (centered on orange)
    float h = hue_of(lin);
    float dh = abs(h - hue_center); dh = min(dh, 1.0 - dh);
    float hue_gate = smoothstep(hue_width, 0.0, dh); // 1 in center, 0 outside band

    // lightness gate (target lighter browns / fairer tones)
    float L_gate = clamp( (L - L_low) / max(L_high - L_low, 1e-3), 0.0, 1.0);

    // chroma & mid-sat emphasis
    float C = length(vec2(a,b));
    float sat_mid = C / (C + 0.25);
    sat_mid = mix(1.0, sat_mid, mid_bias);

    // compression factor
    float k = strength * hue_gate * L_gate * sat_mid;

    // radial compression in a-b plane (preserve hue angle, reduce radius)
    float C2 = C * (1.0 - k);
    float scale = (C > 1e-6) ? (C2 / C) : 1.0;

    vec3 lab2 = vec3(L, a*scale, b*scale);
    vec3 out_lin = oklab_to_linear_srgb(lab2);
    return vec4(toGam(clamp(out_lin,0.0,1.0), gamma_out), 1.0);
}
