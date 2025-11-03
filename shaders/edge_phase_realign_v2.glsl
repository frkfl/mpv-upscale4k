//!PARAM strength
//!TYPE float
1.0

//!PARAM edge_gain
//!TYPE float
1.0

//!PARAM edge_exp
//!TYPE float
1.0

//!PARAM phase_max
//!TYPE float
0.6

//!PARAM amp_norm
//!TYPE float
0.35

//!PARAM tangential_smooth
//!TYPE float
0.45

//!PARAM temporal_alpha
//!TYPE float
1.0

//!PARAM global_gain
//!TYPE float
1.0

//!PARAM skin_protect
//!TYPE float
0.5

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Edge Stabilization & Perceptual Phase Re-Alignment v2 (deterministic, perceptually tunable)

#define DEBUG_NONE       0
#define DEBUG_EDGE       1
#define DEBUG_PHASE      2
#define DEBUG_TANGENT    3
#define DEBUG_COMPOSITE  4
#ifndef DEBUG_MODE
#define DEBUG_MODE DEBUG_NONE
#endif

// Safety limits (Section 12)
#define LIMIT_EDGE_GAIN        4.0
#define LIMIT_EDGE_EXP         3.0
#define LIMIT_PHASE_MAX        0.8
#define LIMIT_AMP_NORM         0.5
#define LIMIT_TANGENTIAL       0.5
#define LIMIT_TEMPORAL_ALPHA   1.0
#define LIMIT_GLOBAL_GAIN      3.0
#define LIMIT_STRENGTH         2.0

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

// Sobel filter on Y
struct SobelOut { vec2 g; float mag; float ang; float gnorm; };
SobelOut sobelY(sampler2D tex, vec2 uv, vec2 px){
    float a = sampleYCC(tex, uv + vec2(-1,-1)*px, 0);
    float b = sampleYCC(tex, uv + vec2( 0,-1)*px, 0);
    float c = sampleYCC(tex, uv + vec2( 1,-1)*px, 0);
    float d = sampleYCC(tex, uv + vec2(-1, 0)*px, 0);
    float e = sampleYCC(tex, uv + vec2( 0, 0)*px, 0);
    float f = sampleYCC(tex, uv + vec2( 1, 0)*px, 0);
    float g = sampleYCC(tex, uv + vec2(-1, 1)*px, 0);
    float h = sampleYCC(tex, uv + vec2( 0, 1)*px, 0);
    float i = sampleYCC(tex, uv + vec2( 1, 1)*px, 0);

    float Gx = (c + 2.0*f + i) - (a + 2.0*d + g);
    float Gy = (g + 2.0*h + i) - (a + 2.0*b + c);
    vec2 g2 = vec2(Gx, Gy);
    float mag = length(g2);
    float ang = atan(g2.y, g2.x);
    float gnorm = mag / (mag + 0.001);
    return SobelOut(g2, mag, ang, gnorm);
}

// 3x3 Gaussian blur for scalar field derived from YCbCr
float blur3x3_scalar(sampler2D tex, vec2 uv, vec2 px, int chan){
    // Weights (1 2 1 / 2 4 2 / 1 2 1) / 16
    int ox[9] = int[9](-1,0,1,-1,0,1,-1,0,1);
    int oy[9] = int[9](-1,-1,-1,0,0,0,1,1,1);
    float w[9] = float[9](1,2,1,2,4,2,1,2,1);
    float acc=0.0, wsum=0.0;
    for(int k=0;k<9;k++){
        float v = sampleYCC(tex, uv + vec2(ox[k],oy[k])*px, chan);
        acc += v * w[k];
        wsum += w[k];
    }
    return acc / wsum;
}

// Skin protection mask (blurred)
float skinMask(sampler2D tex, vec2 uv, vec2 px, float skin_protect_val){
    float Y  = blur3x3_scalar(tex, uv, px, 0);
    float Cb = blur3x3_scalar(tex, uv, px, 1);
    float Cr = blur3x3_scalar(tex, uv, px, 2);
    float S = pow(Cb - 0.47, 2.0) / (0.05*0.05) + pow(Cr - 0.33, 2.0) / (0.07*0.07);
    float skin = step(S, 1.0) * step(0.25, Y) * step(Y, 0.85);
    float P = mix(1.0, 1.0 - 0.5 * skin_protect_val, skin);
    // Blur P with fixed 3x3 Gaussian
    // Reconstruct P neighborhood from original (approx by using same ellipse on neighbors)
    float acc=0.0, wsum=0.0;
    int ox[9] = int[9](-1,0,1,-1,0,1,-1,0,1);
    int oy[9] = int[9](-1,-1,-1,0,0,0,1,1,1);
    float w[9] = float[9](1,2,1,2,4,2,1,2,1);
    for(int k=0;k<9;k++){
        vec2 u = uv + vec2(ox[k],oy[k])*px;
        float Yn  = blur3x3_scalar(tex, u, px, 0); // soft prefilter for robustness
        float Cbn = blur3x3_scalar(tex, u, px, 1);
        float Crn = blur3x3_scalar(tex, u, px, 2);
        float Sn = pow(Cbn - 0.47, 2.0) / (0.05*0.05) + pow(Crn - 0.33, 2.0) / (0.07*0.07);
        float sk = step(Sn, 1.0) * step(0.25, Yn) * step(Yn, 0.85);
        float Pn = mix(1.0, 1.0 - 0.5 * skin_protect_val, sk);
        acc += Pn * w[k];
        wsum += w[k];
    }
    return acc / max(wsum, 1e-6);
}

// Find chroma gradient peak offset along normal within ±3 px via sign change of derivative
float phaseOffsetSignChange(sampler2D tex, vec2 uv, vec2 n, vec2 px, int chan){
    float best_off = 0.0;
    float prev = sampleYCC(tex, uv - 3.0*n*px, chan);
    float curr = sampleYCC(tex, uv - 2.0*n*px, chan);
    float prev_d = curr - prev;
    for(int i=-2;i<=2;i++){
        float a = sampleYCC(tex, uv + float(i)*n*px, chan);
        float b = sampleYCC(tex, uv + float(i+1)*n*px, chan);
        float d = b - a;
        // Detect sign change between prev_d and d -> estimate crossing near i+0.5
        if (prev_d * d <= 0.0){
            best_off = float(i) + 0.5; // subpixel proxy (deterministic)
            break;
        }
        prev_d = d;
    }
    return best_off;
}

// 1D Gaussian along tangent with edge-stop across normal (applied per RGB, then converted)
vec3 tangentSmoothRGB(sampler2D tex, vec2 uv, vec2 t, vec2 n, vec2 px){
    float w0 = 1.0;
    float w1 = exp(-0.5);
    float w2 = exp(-2.0);
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for(int i=-2;i<=2;i++){
        vec2 o = float(i)*t*px;
        vec3 c = fetchRGB(tex, uv + o);
        float dY = abs(sampleYCC(tex, uv + o + n*px, 0) - sampleYCC(tex, uv + o - n*px, 0));
        float stop = exp(-abs(dY) * 20.0);
        float wg = (i==0)? w0 : (abs(i)==1 ? w1 : w2);
        float w = wg * stop;
        acc += c * w;
        wsum += w;
    }
    return acc / max(wsum, 1e-6);
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Clamp parameters to safety limits
    float Strength   = clamp(strength,           0.0, LIMIT_STRENGTH);
    float EdgeGain   = clamp(edge_gain,          0.0, LIMIT_EDGE_GAIN);
    float EdgeExp    = clamp(edge_exp,           0.0, LIMIT_EDGE_EXP);
    float PhaseMax   = clamp(phase_max,          0.0, LIMIT_PHASE_MAX);
    float AmpNorm    = clamp(amp_norm,           0.0, LIMIT_AMP_NORM);
    float TangSmooth = clamp(tangential_smooth,  0.0, LIMIT_TANGENTIAL);
    float TempAlpha  = clamp(temporal_alpha,     0.0, LIMIT_TEMPORAL_ALPHA);
    float GlobalGain = clamp(global_gain,        0.0, LIMIT_GLOBAL_GAIN);
    float SkinProt   = saturate(skin_protect);

    // Original input
    vec3 rgb_in  = fetchRGB(HOOKED_tex, uv);
    vec3 ycc_in  = RGB_to_YCbCr(rgb_in);
    float Y0 = ycc_in.x, Cb0 = ycc_in.y, Cr0 = ycc_in.z;

    // 4) Gradient & Orientation
    SobelOut s = sobelY(HOOKED_tex, uv, px);
    float G_norm = s.gnorm;
    float E = pow(G_norm / 0.06, EdgeExp);
    E = clamp(E * EdgeGain, 0.0, 2.0);

    // 5) Skin Protection Mask P (blurred)
    float P = skinMask(HOOKED_tex, uv, px, SkinProt);

    // 6) Chroma Phase Realignment
    vec2 n = (s.mag > 0.0) ? normalize(s.g) : vec2(1.0, 0.0);
    vec2 t = vec2(-n.y, n.x);

    float offCb = phaseOffsetSignChange(HOOKED_tex, uv, n, px, 1);
    float offCr = phaseOffsetSignChange(HOOKED_tex, uv, n, px, 2);

    float phiCb = clamp(offCb, -PhaseMax, +PhaseMax);
    float phiCr = clamp(offCr, -PhaseMax, +PhaseMax);

    float Cb_shift = sampleYCC(HOOKED_tex, uv + phiCb * n * px, 1);
    float Cr_shift = sampleYCC(HOOKED_tex, uv + phiCr * n * px, 2);

    float blendPhase = saturate(E * P * Strength);
    float Cb = mix(Cb0, Cb_shift, blendPhase);
    float Cr = mix(Cr0, Cr_shift, blendPhase);

    // 7) Luma Amplitude Normalization (median amp along tangent ±6 px)
    // Local left/right means for current pixel
    float lL = ( sampleYCC(HOOKED_tex, uv - 1.0*n*px, 0)
               + sampleYCC(HOOKED_tex, uv - 2.0*n*px, 0)
               + sampleYCC(HOOKED_tex, uv - 3.0*n*px, 0) ) / 3.0;
    float lR = ( sampleYCC(HOOKED_tex, uv + 1.0*n*px, 0)
               + sampleYCC(HOOKED_tex, uv + 2.0*n*px, 0)
               + sampleYCC(HOOKED_tex, uv + 3.0*n*px, 0) ) / 3.0;
    float amp_local = lR - lL;

    float amps[13];
    for(int k=-6;k<=6;k++){
        vec2 uvt = uv + float(k) * t * px;
        float L  = ( sampleYCC(HOOKED_tex, uvt - 1.0*n*px, 0)
                   + sampleYCC(HOOKED_tex, uvt - 2.0*n*px, 0)
                   + sampleYCC(HOOKED_tex, uvt - 3.0*n*px, 0) ) / 3.0;
        float R  = ( sampleYCC(HOOKED_tex, uvt + 1.0*n*px, 0)
                   + sampleYCC(HOOKED_tex, uvt + 2.0*n*px, 0)
                   + sampleYCC(HOOKED_tex, uvt + 3.0*n*px, 0) ) / 3.0;
        amps[k+6] = R - L;
    }
    // median of 13
    for(int i=0;i<13;i++) for(int j=i+1;j<13;j++) if(amps[j]<amps[i]){ float tmp=amps[i]; amps[i]=amps[j]; amps[j]=tmp; }
    float amp_med = amps[6];
    float amp_target = mix(amp_local, amp_med, AmpNorm);

    float meanSides = 0.5*(lL + lR);
    float Y = Y0;
    float delta = Y - meanSides;
    float Y_norm = meanSides + clamp(delta, -0.05, 0.05);
    float blendAmp = saturate(E * P * Strength);
    Y = mix(Y, Y_norm, blendAmp);

    // 8) Tangential Smoothing (σ=1, radius=2) with edge-stop
    vec3 rgb_tan = tangentSmoothRGB(HOOKED_tex, uv, t, n, px);
    vec3 ycc_tan = RGB_to_YCbCr(rgb_tan);
    float w_tan = E * P * TangSmooth;
    Y  = mix(Y,  ycc_tan.x, saturate(w_tan));
    Cb = mix(Cb, ycc_tan.y, saturate(w_tan));
    Cr = mix(Cr, ycc_tan.z, saturate(w_tan));

    // 9) Temporal Stabilization (EMA) on Y, Cb, Cr
    vec3 prev_rgb = fetchRGB(PREV_tex, uv);
    vec3 prev_ycc = RGB_to_YCbCr(prev_rgb);
    SobelOut sp = sobelY(PREV_tex, uv, px);
    float dtheta = abs(s.ang - sp.ang);
    dtheta = mod(dtheta + 3.14159265, 6.2831853) - 3.14159265; dtheta = abs(dtheta);

    // motion = mean |Y_curr - Y_prev| in 3x3
    float mot = 0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){
        vec2 u = uv + vec2(x,y)*px;
        float yc = sampleYCC(HOOKED_tex, u, 0);
        float yp = sampleYCC(PREV_tex,   u, 0);
        mot += abs(yc - yp);
    }
    mot /= 9.0;

    float E_curr = E;
    float E_prev = clamp(pow(sp.gnorm / 0.06, EdgeExp) * EdgeGain, 0.0, 2.0);

    float alpha = clamp(TempAlpha / (Strength + 1.0), 0.0, 1.0);
    bool condb = (E_curr>0.5 && E_prev>0.5 && dtheta<0.52 && mot<0.05);
    float cond = condb ? 1.0 : 0.0;

    float Y_out  = mix(Y,  mix(Y,  prev_ycc.x, alpha), cond);
    float Cb_out = mix(Cb, mix(Cb, prev_ycc.y, alpha), cond);
    float Cr_out = mix(Cr, mix(Cr, prev_ycc.z, alpha), cond);

    // 🔟 Global Gain and Recomposition
    // Perceptual gain on deviations from original
    float Y_corr  = Y0  + GlobalGain * (Y_out  - Y0);
    float Cb_corr = Cb0 + GlobalGain * (Cb_out - Cb0);
    float Cr_corr = Cr0 + GlobalGain * (Cr_out - Cr0);

    vec3 rgb_corr = YCbCr_to_RGB(vec3(Y_corr, Cb_corr, Cr_corr));
    vec3 out_rgb = 0.5 + 0.5 * tanh(2.0 * (rgb_corr - 0.5));
    out_rgb = clamp01(out_rgb);

#if DEBUG_MODE == DEBUG_EDGE
    return vec4(vec3(clamp(E,0.0,2.0)*0.5), 1.0);
#elif DEBUG_MODE == DEBUG_PHASE
    {
        float ph = 0.5 * (abs(offCb) + abs(offCr)) / max(PhaseMax, 1e-6);
        return vec4(vec3(saturate(ph)), 1.0);
    }
#elif DEBUG_MODE == DEBUG_TANGENT
    return vec4(vec3(saturate(w_tan)), 1.0);
#elif DEBUG_MODE == DEBUG_COMPOSITE
    vec3 split = (uv.x < 0.5) ? rgb_in : out_rgb;
    return vec4(split, 1.0);
#else
    return vec4(out_rgb, 1.0);
#endif
}
