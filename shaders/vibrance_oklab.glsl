//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Vibrance (OkLab, luma-preserving, skin-protect)
//!PARAM float vibrance = 0.18   // 0..0.5 overall vibrance
//!PARAM float skin_protect = 0.60 // 0..1 weaken boost near skin hues
//!PARAM float skin_hue = 0.07   // ~0.07 = ~25° (orange); tweak 0.05..0.10
//!PARAM float skin_width = 0.06 // hue half-width around skin_hue
//!PARAM float mid_bias = 0.20   // 0..0.6 mid-sat emphasis
//!PARAM float gamma_in = 2.20
//!PARAM float gamma_out = 2.20

// sRGB <-> linear helpers
vec3 toLin(vec3 c,float g){return pow(max(c,0.0),vec3(g>0.0?1.0/g:1.0));}
vec3 toGam(vec3 c,float g){return pow(max(c,0.0),vec3(g>0.0?g:1.0));}

// sRGB linear -> OkLab (from Björn Ottosson, inlined)
mat3 M1 = mat3( 0.4122214708, 0.5363325363, 0.0514459929,
                0.2119034982, 0.6806995451, 0.1073969566,
                0.0883024619, 0.2817188376, 0.6299787005);
mat3 M2 = mat3( 0.2104542553, 0.7936177850, -0.0040720468,
                1.9779984951,-2.4285922050,  0.4505937099,
                0.0259040371, 0.7827717662, -0.8086757660);

vec3 linear_srgb_to_oklab(vec3 c){
    vec3 lms = pow(M1*c, vec3(1.0/3.0));
    return M2*lms;
}
vec3 oklab_to_linear_srgb(vec3 LLab){
    // inverse (approx): compose matrices explicitly
    // From oklab.com inverse: OkLab -> LMS -> linear sRGB
    float L = LLab.x, a = LLab.y, b = LLab.z;
    float l = (L + 0.3963377774*a + 0.2158037573*b);
    float m = (L - 0.1055613458*a - 0.0638541728*b);
    float s = (L - 0.0894841775*a - 1.2914855480*b);
    l = l*l*l; m = m*m*m; s = s*s*s;
    mat3 Mi = mat3( 4.0767416621,-3.3077115913, 0.2309699292,
                    -1.2684380046, 2.6097574011,-0.3413193965,
                     0.0041960863,-0.7034186147, 1.6996226760);
    return Mi*vec3(l,m,s);
}

float safe_hue(vec3 rgb_lin){
    // simple HSV hue in linear domain (good enough for gating skin)
    float M = max(max(rgb_lin.r,rgb_lin.g),rgb_lin.b);
    float m = min(min(rgb_lin.r,rgb_lin.g),rgb_lin.b);
    float C = max(M - m, 1e-6);
    vec3 n = (rgb_lin - m)/C;
    float h = (M==rgb_lin.r)? (n.g - n.b) :
              (M==rgb_lin.g)? (2.0 + n.b - n.r) :
                              (4.0 + n.r - n.g);
    h = fract((h/6.0)+1.0);
    return h; // 0..1
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec3 srgb = HOOKED_tex(uv).rgb;
    vec3 lin  = toLin(srgb, gamma_in);

    // OkLab split
    vec3 lab = linear_srgb_to_oklab(lin);
    float L = lab.x;
    float a = lab.y;
    float b = lab.z;

    // chroma in OkLab
    float C = length(vec2(a,b));
    float sat = C / max(L, 1e-4); // quick perceptual sat proxy

    // mid-sat weighting (emphasize mid saturation more)
    float mid = smoothstep(0.0, 1.0, sat/(sat+0.5));
    mid = mix(1.0, mid, mid_bias);

    // skin protection (soft notch around skin hue)
    float h = safe_hue(lin);
    float dh = abs(h - skin_hue); dh = min(dh, 1.0 - dh);
    float skin_gate = 1.0 - skin_protect * exp(-0.5*pow(dh/max(skin_width,1e-3), 2.0));

    float k = vibrance * mid * skin_gate;

    // push a,b radially, keep L (luma-ish) constant
    float scale = 1.0 + k;
    vec3 lab2 = vec3(L, a*scale, b*scale);

    vec3 out_lin = oklab_to_linear_srgb(lab2);
    vec3 out_srgb = toGam(out_lin, gamma_out);
    return vec4(clamp(out_srgb, 0.0, 1.0), 1.0);
}

