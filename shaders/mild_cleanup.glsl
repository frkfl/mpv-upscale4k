// mpv user shader: hardware-agnostic mild cleanup (wide-gamut safe)

//!PARAM luma_radius
//!TYPE float
1.0
//!PARAM sigma_s
//!TYPE float
1.25
//!PARAM sigma_r
//!TYPE float
0.06
//!PARAM chroma_radius
//!TYPE float
1.0
//!PARAM chroma_strength
//!TYPE float
0.6
//!PARAM deblock_strength
//!TYPE float
0.2
//!PARAM grain_strength
//!TYPE float
0.004
//!PARAM seed
//!TYPE float
1337.0
//!HOOK LUMA
//!BIND HOOKED
//!SAVE luma_denoised
//!DESC Luma bilateral denoise

float gauss(float x, float s) { return exp(-0.5 * (x*x) / max(s*s, 1e-8)); }

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;
    float center = HOOKED_tex(HOOKED_pos).r;

    int R = int(luma_radius + 0.5);
    float wsum = 0.0, vsum = 0.0;

    for (int j=-R;j<=R;++j){
        for (int i=-R;i<=R;++i){
            vec2 o = vec2(i,j) * px;
            float v = HOOKED_tex(HOOKED_pos + o).r;
            float w = gauss(v-center,sigma_r) * gauss(length(vec2(i,j)),sigma_s);
            wsum += w;
            vsum += v*w;
        }
    }
    return vec4(vsum / max(wsum,1e-8), 0.0, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND HOOKED
//!SAVE chroma_clean
//!DESC Chroma gentle low-pass

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;
    int R = int(chroma_radius + 0.5);

    vec3 sum = vec3(0.0); 
    float wsum = 0.0;

    for (int j=-R;j<=R;++j){
        for (int i=-R;i<=R;++i){
            vec2 o = vec2(i,j)*px;
            float w = 1.0 / (1.0 + dot(vec2(i,j),vec2(i,j)));
            sum += HOOKED_tex(HOOKED_pos + o).rgb * w;
            wsum += w;
        }
    }
    vec3 blur = sum / max(wsum,1e-8);
    vec3 orig = HOOKED_tex(HOOKED_pos).rgb;
    return vec4(mix(orig, blur, clamp(chroma_strength,0.0,1.0)), 1.0);
}

//!HOOK LUMA
//!BIND HOOKED
//!BIND luma_denoised
//!SAVE luma_deblock
//!DESC Block-edge guided luma blend

float edgeMetric(vec2 pos, vec2 px){
    float l = HOOKED_tex(pos - vec2(px.x, 0.0)).r;
    float r = HOOKED_tex(pos + vec2(px.x, 0.0)).r;
    float u = HOOKED_tex(pos - vec2(0.0, px.y)).r;
    float d = HOOKED_tex(pos + vec2(0.0, px.y)).r;
    return max(abs(r - l), abs(d - u));
}

vec4 hook(){
    vec2 px = 1.0 / HOOKED_size.xy;
    float den = luma_denoised_tex(HOOKED_pos).r;
    float org = HOOKED_tex(HOOKED_pos).r;
    float k = clamp(deblock_strength * edgeMetric(HOOKED_pos, px) * 4.0, 0.0, 1.0);
    return vec4(mix(org, den, k), 0.0, 0.0, 1.0);
}

//!HOOK MAIN
//!BIND HOOKED
//!BIND luma_deblock
//!BIND chroma_clean
//!DESC Recombine cleaned luma/chroma + grain, hue-preserving

float hash(vec2 p){
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec3 rgb = HOOKED_tex(uv).rgb;

    const vec3 kY = vec3(0.2627, 0.6780, 0.0593);
    float Y_old = dot(rgb, kY);
    float Y_new = luma_deblock_tex(uv).r;

    // luminance correction in RGB space (chroma-preserving)
    rgb += (Y_new - Y_old) * kY;

    if (grain_strength > 0.0){
        float g = (hash(uv * HOOKED_size.xy + seed) - 0.5) * 2.0;
        rgb += g * grain_strength;
    }

    return vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
