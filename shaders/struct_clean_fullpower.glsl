#version 450
//!PARAM strength
//!TYPE float
1.0

//!PARAM radius
//!TYPE float
3.0

//!PARAM edge_protect
//!TYPE float
0.7

//!PARAM chroma_weight
//!TYPE float
0.6

//!PARAM temporal_alpha
//!TYPE float
0.8

//!PARAM global_gain
//!TYPE float
1.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Structural Cleaning Reinforcement Pass (Full-Power, Perceptual)

// Debug modes (compile-time only)
#define DEBUG_NONE       0
#define DEBUG_NOISE      1
#define DEBUG_EDGE       2
#define DEBUG_COMPOSITE  3
#ifndef DEBUG_MODE
#define DEBUG_MODE DEBUG_NONE
#endif

// Safety caps (Section 2/9)
#define CAP_STRENGTH 3.0
#define CAP_RADIUS   5.0
#define CAP_EDGE_PROTECT 1.0
#define CAP_CHROMA_WEIGHT 1.0
#define CAP_TEMPORAL 1.0
#define CAP_GLOBAL_GAIN 3.0
#define MIN_RADIUS   1.0

// Helpers
float saturate(float x){ return clamp(x, 0.0, 1.0); }
vec3  clamp01(vec3 v){ return clamp(v, 0.0, 1.0); }
vec3 fetchRGB(sampler2D t, vec2 uv){ return texture(t, uv).rgb; }

// Rec.601 linear RGB <-> YCbCr in [0..1]
vec3 RGB_to_YCbCr(vec3 c){
    float Y  = dot(c, vec3(0.299, 0.587, 0.114));
    float Cb = (c.b - Y) * 0.564 + 0.5;
    float Cr = (c.r - Y) * 0.713 + 0.5;
    return vec3(Y, Cb, Cr);
}
vec3 YCbCr_to_RGB(vec3 ycc){
    float Y = ycc.x, Cb = ycc.y, Cr = ycc.z;
    float R = Y + 1.403 * (Cr - 0.5);
    float G = Y - 0.344 * (Cb - 0.5) - 0.714 * (Cr - 0.5);
    float B = Y + 1.773 * (Cb - 0.5);
    return vec3(R, G, B);
}

// Sample a single Y/Cb/Cr channel with hardware bilinear
float sampleYCC(sampler2D tex, vec2 uv, int chan){
    vec3 ycc = RGB_to_YCbCr(fetchRGB(tex, uv));
    return (chan==0) ? ycc.x : (chan==1) ? ycc.y : ycc.z;
}

// Sobel on Y (3x3)
struct SobelOut { vec2 g; float mag; };
SobelOut sobelY(sampler2D tex, vec2 uv, vec2 px){
    float a = sampleYCC(tex, uv + vec2(-1,-1)*px, 0);
    float b = sampleYCC(tex, uv + vec2( 0,-1)*px, 0);
    float c = sampleYCC(tex, uv + vec2( 1,-1)*px, 0);
    float d = sampleYCC(tex, uv + vec2(-1, 0)*px, 0);
    float f = sampleYCC(tex, uv + vec2( 1, 0)*px, 0);
    float g = sampleYCC(tex, uv + vec2(-1, 1)*px, 0);
    float h = sampleYCC(tex, uv + vec2( 0, 1)*px, 0);
    float i = sampleYCC(tex, uv + vec2( 1, 1)*px, 0);

    float Gx = (c + 2.0*f + i) - (a + 2.0*d + g);
    float Gy = (g + 2.0*h + i) - (a + 2.0*b + c);
    vec2 g2 = vec2(Gx, Gy);
    return SobelOut(g2, length(g2));
}

// 5x5 Gaussian mean/variance on Y with sigma = radius (Section 4)
void gaussian5x5_stats(sampler2D tex, vec2 uv, vec2 px, float sigma, out float meanY, out float varY){
    float s2 = max(sigma, MIN_RADIUS); // avoid zero/denorm
    s2 = s2 * s2;
    float wsum = 0.0;
    float m = 0.0;
    float m2 = 0.0;
    for(int y=-2;y<=2;y++){
        for(int x=-2;x<=2;x++){
            float w = exp(-(float(x*x + y*y)) / (2.0*s2));
            float Y = sampleYCC(tex, uv + vec2(x,y)*px, 0);
            wsum += w;
            m  += w * Y;
            m2 += w * Y * Y;
        }
    }
    m  /= max(wsum, 1e-6);
    m2 /= max(wsum, 1e-6);
    meanY = m;
    varY  = max(m2 - m*m, 0.0);
}

// Weighted median over a square window up to 11x11 (radius<=5).
// We pre-allocate arrays of length 121 and fill first N items.
float weightedMedianSquare(sampler2D tex, vec2 uv, vec2 px, int chan, int rad, float range_scale, float var_local, float rad_param){
    const int MAXN = 121;
    float vals[MAXN];
    float wts[MAXN];
    int idx = 0;

    float denom = 0.03 + var_local;
    float inv_r = 1.0 / max(rad_param, 1e-6);

    float center = sampleYCC(tex, uv, chan);

    for(int j=-5;j<=5;j++){
        for(int i=-5;i<=5;i++){
            if (abs(i) > rad || abs(j) > rad) continue;
            vec2 o = vec2(i,j);
            float v = sampleYCC(tex, uv + o*px, chan);
            float wr = exp(-abs(v - center) / denom);
            float ws = exp(-length(o) * inv_r);
            float w  = wr * ws;
            vals[idx] = v;
            wts[idx]  = w;
            idx++;
        }
    }

    // Sort by value (ascending) while carrying weights (simple insertion sort)
    for(int a=0;a<idx;a++){
        int k = a;
        for(int b=a+1;b<idx;b++){
            if (vals[b] < vals[k]) k = b;
        }
        if (k != a){
            float tv = vals[a]; vals[a] = vals[k]; vals[k] = tv;
            float tw = wts[a];  wts[a]  = wts[k];  wts[k]  = tw;
        }
    }

    // Cumulative weight to 0.5
    float W = 0.0;
    for(int n=0;n<idx;n++) W += wts[n];
    float half = 0.5 * W;
    float acc = 0.0;
    for(int n=0;n<idx;n++){
        acc += wts[n];
        if (acc >= half) return vals[n];
    }
    return vals[max(idx-1,0)];
}

// 3x3 mean absolute difference (motion metric)
float motion3x3_Y(sampler2D curr, sampler2D prev, vec2 uv, vec2 px){
    float acc = 0.0;
    for(int y=-1;y<=1;y++)
    for(int x=-1;x<=1;x++){
        vec2 u = uv + vec2(x,y)*px;
        float yc = sampleYCC(curr, u, 0);
        float yp = sampleYCC(prev, u, 0);
        acc += abs(yc - yp);
    }
    return acc / 9.0;
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Clamp parameters to safety
    float Strength   = clamp(strength,        0.0, CAP_STRENGTH);
    float RadiusF    = clamp(radius,          MIN_RADIUS, CAP_RADIUS);
    int   Rad        = int(floor(RadiusF + 0.5));
    Rad = clamp(Rad, 1, 5);
    float EdgeProtect= clamp(edge_protect,    0.0, CAP_EDGE_PROTECT);
    float CbCrWeight = clamp(chroma_weight,   0.0, CAP_CHROMA_WEIGHT);
    float TempAlpha  = clamp(temporal_alpha,  0.0, CAP_TEMPORAL);
    float GlobalGain = clamp(global_gain,     0.0, CAP_GLOBAL_GAIN);

    // -- 3) Preprocessing: RGB -> YCbCr
    vec3 rgb_in = fetchRGB(HOOKED_tex, uv);
    vec3 ycc_in = RGB_to_YCbCr(rgb_in);
    float Yorig = ycc_in.x;
    float Cborig = ycc_in.y;
    float Crorig = ycc_in.z;

    // -- 4) Local Energy Field Estimation
    float meanY, varY;
    gaussian5x5_stats(HOOKED_tex, uv, px, RadiusF, meanY, varY);

    SobelOut sb = sobelY(HOOKED_tex, uv, px);
    float grad_mag = sb.mag;

    float noise_p = saturate( (varY / (meanY + 1e-4)) * (1.0 - grad_mag) );

    float edge_mask = exp(-grad_mag * 10.0);
    float E = mix(1.0, edge_mask, EdgeProtect);
    float N = noise_p * E; // cleaning weight

    // -- 5) Adaptive Bilateral-Median Cleaning
    float Y_med  = weightedMedianSquare(HOOKED_tex, uv, px, 0, Rad, 1.0, varY, RadiusF);
    float Cb_med = weightedMedianSquare(HOOKED_tex, uv, px, 1, Rad, 1.0, varY, RadiusF);
    float Cr_med = weightedMedianSquare(HOOKED_tex, uv, px, 2, Rad, 1.0, varY, RadiusF);

    float k = saturate(N * Strength);
    float Y_clean  = mix(Yorig,  Y_med,  k);
    float Cb_clean = mix(Cborig, Cb_med, CbCrWeight * k);
    float Cr_clean = mix(Crorig, Cr_med, CbCrWeight * k);

    // -- 6) Temporal Stabilization (always active)
    vec3 prev_rgb = fetchRGB(PREV_tex, uv);
    vec3 prev_ycc = RGB_to_YCbCr(prev_rgb);
    float motion = motion3x3_Y(HOOKED_tex, PREV_tex, uv, px);
    float alpha = clamp(TempAlpha / (1.0 + Strength), 0.0, 1.0);
    bool cond_b = (motion < 0.05);
    float cond  = cond_b ? 1.0 : 0.0;

    float Yt  = mix(Y_clean,  mix(prev_ycc.x, Y_clean, 1.0 - alpha), cond); // cond ? mix(prev, clean, 1-alpha) : clean
    float Cbt = mix(Cb_clean, mix(prev_ycc.y, Cb_clean, 1.0 - alpha), cond);
    float Crt = mix(Cr_clean, mix(prev_ycc.z, Cr_clean, 1.0 - alpha), cond);

    // -- 7) Global Gain & Recomposition
    float Yf  = Yorig  + GlobalGain * (Yt  - Yorig);
    float Cbf = Cborig + GlobalGain * (Cbt - Cborig);
    float Crf = Crorig + GlobalGain * (Crt - Crorig);

    vec3 rgb_out = YCbCr_to_RGB(vec3(Yf, Cbf, Crf));
    vec3 out_rgb = 0.5 + 0.5 * tanh(2.0 * (rgb_out - 0.5));
    out_rgb = clamp01(out_rgb);

#if DEBUG_MODE == DEBUG_NOISE
    return vec4(vec3(N), 1.0);
#elif DEBUG_MODE == DEBUG_EDGE
    return vec4(vec3(E), 1.0);
#elif DEBUG_MODE == DEBUG_COMPOSITE
    vec3 split = (uv.x < 0.5) ? rgb_in : out_rgb;
    return vec4(split, 1.0);
#else
    return vec4(out_rgb, 1.0);
#endif
}
