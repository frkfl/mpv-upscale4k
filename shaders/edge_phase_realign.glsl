//!PARAM strength
//!TYPE float
1.0

//!PARAM edge_lo
//!TYPE float
0.06

//!PARAM edge_hi
//!TYPE float
0.18

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

//!PARAM skin_protect
//!TYPE float
0.5

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Edge Stabilization & Phase Re-Alignment Pass (deterministic)

#define DEBUG_NONE        0
#define DEBUG_EDGEMASK    1
#define DEBUG_PHASE       2
#define DEBUG_TANGENT     3
#define DEBUG_COMPOSITE   4
#ifndef DEBUG_MODE
#define DEBUG_MODE DEBUG_NONE
#endif

// Safety bounds
#define E_MIN_THRESHOLD 0.02
#define PHASE_MAX_CAP 0.8
#define AMP_NORM_CAP  0.5
#define TANG_SMOOTH_CAP 0.5
#define STRENGTH_CAP 2.0

// Helpers
vec3 fetchRGB(sampler2D tex, vec2 uv) { return texture(tex, uv).rgb; }
float saturate(float x){ return clamp(x, 0.0, 1.0); }

// RGB <-> YCbCr (Rec.601-derived, [0..1] domain, linear)
vec3 RGB_to_YCbCr(vec3 c) {
    float Y  = dot(c, vec3(0.299, 0.587, 0.114));
    float Cb = (c.b - Y) * 0.564 + 0.5;
    float Cr = (c.r - Y) * 0.713 + 0.5;
    return vec3(Y, Cb, Cr);
}
vec3 YCbCr_to_RGB(vec3 ycc) {
    float Y = ycc.x, Cb = ycc.y, Cr = ycc.z;
    float R = Y + 1.403 * (Cr - 0.5);
    float G = Y - 0.344 * (Cb - 0.5) - 0.714 * (Cr - 0.5);
    float B = Y + 1.773 * (Cb - 0.5);
    return vec3(R, G, B);
}

// Sobel on luma
struct SobelOut { vec2 g; float mag; float ang; float norm; };
SobelOut sobelLuma(sampler2D tex, vec2 uv, vec2 px) {
    float tl = texture(tex, uv + (-px +  px*vec2(0.0,1.0))).r; // dummy init
    // Sample luma only
    float a = RGB_to_YCbCr(fetchRGB(tex, uv + vec2(-1,-1)*px)).x;
    float b = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 0,-1)*px)).x;
    float c = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 1,-1)*px)).x;
    float d = RGB_to_YCbCr(fetchRGB(tex, uv + vec2(-1, 0)*px)).x;
    float e = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 0, 0)*px)).x;
    float f = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 1, 0)*px)).x;
    float g = RGB_to_YCbCr(fetchRGB(tex, uv + vec2(-1, 1)*px)).x;
    float h = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 0, 1)*px)).x;
    float i = RGB_to_YCbCr(fetchRGB(tex, uv + vec2( 1, 1)*px)).x;

    float Gx = (c + 2.0*f + i) - (a + 2.0*d + g);
    float Gy = (g + 2.0*h + i) - (a + 2.0*b + c);
    vec2 g2 = vec2(Gx, Gy);
    float mag = length(g2);
    float ang = atan(g2.y, g2.x);
    float norm = mag / (mag + 0.001);
    return SobelOut(g2, mag, ang, norm);
}

// 3x3 min/max (morphology) over scalar channel sampled from tex via func
float min3x3(sampler2D tex, vec2 uv, vec2 px, bool useLuma) {
    float m = 1e9;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec3 c = fetchRGB(tex, uv + vec2(x,y)*px);
        float v = useLuma ? RGB_to_YCbCr(c).x : c.r;
        m = min(m, v);
    }
    return m;
}
float max3x3(sampler2D tex, vec2 uv, vec2 px, bool useLuma) {
    float m = -1e9;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec3 c = fetchRGB(tex, uv + vec2(x,y)*px);
        float v = useLuma ? RGB_to_YCbCr(c).x : c.r;
        m = max(m, v);
    }
    return m;
}

// Non-maximum suppression along gradient angle
float nms_along(vec2 grad, float mag, sampler2D tex, vec2 uv, vec2 px) {
    vec2 n = (length(grad) > 0.0) ? normalize(grad) : vec2(1.0, 0.0);
    float m1 = RGB_to_YCbCr(fetchRGB(tex, uv + n*px)).x;
    float m2 = RGB_to_YCbCr(fetchRGB(tex, uv - n*px)).x;
    // Compare gradient magnitude via central difference on neighbors
    SobelOut s1 = sobelLuma(tex, uv + n*px, px);
    SobelOut s2 = sobelLuma(tex, uv - n*px, px);
    float keep = (mag >= s1.mag && mag >= s2.mag) ? 1.0 : 0.0;
    return keep;
}

// 3x3 Gaussian blur on scalar field sampled from YCbCr channels baked in tex
float blur3x3_scalar(float center, sampler2D tex, vec2 uv, vec2 px, int chan) {
    // Weights:
    // 1 2 1
    // 2 4 2  / 16
    // 1 2 1
    float acc = 0.0, wsum = 0.0;
    int wx[9] = int[9](-1,0,1,-1,0,1,-1,0,1);
    int wy[9] = int[9](-1,-1,-1,0,0,0,1,1,1);
    float ww[9] = float[9](1,2,1,2,4,2,1,2,1);
    for (int k=0;k<9;k++){
        vec3 rgb = fetchRGB(tex, uv + vec2(wx[k],wy[k])*px);
        vec3 ycc = RGB_to_YCbCr(rgb);
        float v = (chan==0)? ycc.x : (chan==1)? ycc.y : ycc.z;
        acc += v * ww[k];
        wsum += ww[k];
    }
    return acc / wsum;
}

// Sample scalar channel from YCbCr with bilinear hardware filtering
float sampleChannel(sampler2D tex, vec2 uv, int chan){
    vec3 ycc = RGB_to_YCbCr(fetchRGB(tex, uv));
    return (chan==0)? ycc.x : (chan==1)? ycc.y : ycc.z;
}

// Median helpers
float median13(float v[13]){
    for(int i=0;i<13;i++) for(int j=i+1;j<13;j++) if(v[j]<v[i]){float t=v[i];v[i]=v[j];v[j]=t;}
    return v[6];
}
float meanN(float a[6]){
    float s=0.0; for(int i=0;i<6;i++) s+=a[i]; return s/6.0;
}

// Directional peak offset via max |d/dn| within ±3 px (subpixel via picking argmax among taps)
float peakOffsetAlongNormal(sampler2D tex, vec2 uv, vec2 n, vec2 px, int chan){
    float maxv = -1.0;
    int arg = 0;
    float prev = sampleChannel(tex, uv - 2.0*n*px, chan);
    float curr = sampleChannel(tex, uv - 1.0*n*px, chan);
    for(int i=-3;i<=3;i++){
        float p = sampleChannel(tex, uv + float(i)*n*px, chan);
        float nextp = sampleChannel(tex, uv + float(i+1)*n*px, chan);
        float deriv = abs(nextp - p);
        if (deriv > maxv){ maxv = deriv; arg = i; }
        prev = curr; curr = p;
    }
    return float(arg); // in pixels along n
}

// 1D Gaussian along tangent with edge-stop across normal
vec3 tangentGaussian(sampler2D tex, vec2 uv, vec2 t, vec2 n, vec2 px){
    // radius 2, sigma=1
    float w0 = exp(-0.0*0.5);
    float w1 = exp(-1.0*0.5);
    float w2 = exp(-4.0*0.5);
    float norm = w2*2.0 + w1*2.0 + w0;
    vec3 acc = vec3(0.0);
    float wsum = 0.0;

    vec3 c0 = fetchRGB(tex, uv);
    float Y0 = RGB_to_YCbCr(c0).x;

    for(int i=-2;i<=2;i++){
        vec2 o = float(i)*t*px;
        vec3 c = fetchRGB(tex, uv + o);
        float Yi = RGB_to_YCbCr(c).x;
        // Edge-stop across normal: approximate local contrast via normal difference
        float dY = abs( sampleChannel(tex, uv + o + n*px, 0) - sampleChannel(tex, uv + o - n*px, 0) );
        float stop = exp(-abs(dY) * 20.0);
        float wg = (i==0)? w0 : (abs(i)==1? w1 : w2);
        float w = wg * stop;
        acc += c * w;
        wsum += w;
    }
    return acc / max(wsum, 1e-6);
}

vec4 hook() {
    vec2 px = 1.0 / HOOKED_size.xy;
    vec2 uv = HOOKED_pos;

    // Parameters with safety caps
    float Strength = clamp(strength, 0.0, STRENGTH_CAP);
    float EdgeLo   = edge_lo;
    float EdgeHi   = edge_hi;
    float PhaseMax = clamp(phase_max, 0.0, PHASE_MAX_CAP);
    float AmpNorm  = clamp(amp_norm, 0.0, AMP_NORM_CAP);
    float TangSm   = clamp(tangential_smooth, 0.0, TANG_SMOOTH_CAP);
    float TempA    = clamp(temporal_alpha, 0.0, 1.0);
    float SkinProt = saturate(skin_protect);

    // --- 1) Convert
    vec3 rgb_in = fetchRGB(HOOKED_tex, uv);
    vec3 ycc    = RGB_to_YCbCr(rgb_in);
    float Y = ycc.x, Cb = ycc.y, Cr = ycc.z;

    // --- 2) Sobel / Orientation
    SobelOut s = sobelLuma(HOOKED_tex, uv, px);

    // --- 3) Edge Mask E
    float E_raw = smoothstep(EdgeLo, EdgeHi, s.norm);
    // open (min then max), close (max then min) on E_raw sampled from a temp synth using Y as carrier
    // emulate by direct neighborhood ops on E_raw by recomputing E on neighbors
    float Emin = 1e9, Emax = -1e9;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec2 uvn = uv + vec2(x,y)*px;
        float En = smoothstep(EdgeLo, EdgeHi, sobelLuma(HOOKED_tex, uvn, px).norm);
        Emin = min(Emin, En);
        Emax = max(Emax, En);
    }
    // open: min then max
    float E_open_max = -1e9;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec2 uvn = uv + vec2(x,y)*px;
        float En = smoothstep(EdgeLo, EdgeHi, sobelLuma(HOOKED_tex, uvn, px).norm);
        E_open_max = max(E_open_max, En);
    }
    // close: max then min
    float E_close_min = 1e9;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec2 uvn = uv + vec2(x,y)*px;
        float En = smoothstep(EdgeLo, EdgeHi, sobelLuma(HOOKED_tex, uvn, px).norm);
        E_close_min = min(E_close_min, En);
    }
    float E_morph = clamp(E_open_max + (E_close_min - E_open_max)*0.5, 0.0, 1.0);

    // Non-maximum suppression
    float keep = nms_along(s.g, s.mag, HOOKED_tex, uv, px);
    float E = saturate(E_morph * keep);
    E *= step(E_MIN_THRESHOLD, E);

    // --- 4) Skin Protection Mask P
    // Skin ellipse in YCbCr after slight blur
    float Yb  = blur3x3_scalar(Y, HOOKED_tex, uv, px, 0);
    float Cbb = blur3x3_scalar(Cb, HOOKED_tex, uv, px, 1);
    float Crb = blur3x3_scalar(Cr, HOOKED_tex, uv, px, 2);
    float S = pow(Cbb-0.47,2.0)/pow(0.05,2.0) + pow(Crb-0.33,2.0)/pow(0.07,2.0);
    float skin = step(S, 1.0) * step(0.25, Yb) * step(Yb, 0.85);
    float P = mix(1.0, 1.0 - 0.5*SkinProt, skin);

    // --- 5) Local Edge Model
    vec2 n = (s.mag > 0.0) ? normalize(s.g) : vec2(1.0,0.0);
    vec2 t = vec2(-n.y, n.x);

    // Means on left/right along normal (±3 px)
    float leftY[3]; float rightY[3];
    float leftCb[3]; float rightCb[3];
    float leftCr[3]; float rightCr[3];
    for (int i=1;i<=3;i++){
        leftY[i-1]  = sampleChannel(HOOKED_tex, uv - float(i)*n*px, 0);
        rightY[i-1] = sampleChannel(HOOKED_tex, uv + float(i)*n*px, 0);
        leftCb[i-1]  = sampleChannel(HOOKED_tex, uv - float(i)*n*px, 1);
        rightCb[i-1] = sampleChannel(HOOKED_tex, uv + float(i)*n*px, 1);
        leftCr[i-1]  = sampleChannel(HOOKED_tex, uv - float(i)*n*px, 2);
        rightCr[i-1] = sampleChannel(HOOKED_tex, uv + float(i)*n*px, 2);
    }
    float meanLeftY  = (leftY[0]+leftY[1]+leftY[2])/3.0;
    float meanRightY = (rightY[0]+rightY[1]+rightY[2])/3.0;

    float amp_local = meanRightY - meanLeftY;

    // Edge center by peak |dY/dn|
    float center_off_Y = peakOffsetAlongNormal(HOOKED_tex, uv, n, px, 0);
    float center_off_Cb = peakOffsetAlongNormal(HOOKED_tex, uv, n, px, 1);
    float center_off_Cr = peakOffsetAlongNormal(HOOKED_tex, uv, n, px, 2);

    float phase_offset_Cb = center_off_Cb - center_off_Y;
    float phase_offset_Cr = center_off_Cr - center_off_Y;

    // --- 6) Chroma Phase Realignment
    float phiCb = clamp(phase_offset_Cb, -PhaseMax, PhaseMax);
    float phiCr = clamp(phase_offset_Cr, -PhaseMax, PhaseMax);
    float Cb_shift = sampleChannel(HOOKED_tex, uv + phiCb * n * px, 1);
    float Cr_shift = sampleChannel(HOOKED_tex, uv + phiCr * n * px, 2);
    float phaseBlend = E * P * 0.85 * Strength;
    Cb = mix(Cb, Cb_shift, phaseBlend);
    Cr = mix(Cr, Cr_shift, phaseBlend);

    // --- 7) Luma Amplitude Normalization
    // Tangential median of amp_local within ±6 px
    float amps[13];
    for(int k=-6;k<=6;k++){
        vec2 uvt = uv + float(k) * t * px;
        // compute local amp at uvt
        float lL[3]; float lR[3];
        for (int i=1;i<=3;i++){
            lL[i-1] = sampleChannel(HOOKED_tex, uvt - float(i)*n*px, 0);
            lR[i-1] = sampleChannel(HOOKED_tex, uvt + float(i)*n*px, 0);
        }
        float aLocal = (lR[0]+lR[1]+lR[2])/3.0 - (lL[0]+lL[1]+lL[2])/3.0;
        amps[k+6] = aLocal;
    }
    float amp_med = median13(amps);
    float amp_target = mix(amp_local, amp_med, AmpNorm);

    float meanSides = 0.5 * (meanLeftY + meanRightY);
    float delta = Y - meanSides;
    float Y_norm = meanSides + clamp(delta, -0.05, 0.05);

    float ampBlend = E * P * 0.65 * Strength;
    Y = mix(Y, Y_norm, ampBlend);

    // --- 8) Tangential Smoothing (1D Gaussian along t)
    vec3 rgb_tan = tangentGaussian(HOOKED_tex, uv, t, n, px);
    vec3 ycc_tan = RGB_to_YCbCr(rgb_tan);
    float w_tan = E * P * TangSm * 0.8 * Strength;
    Y  = mix(Y,  ycc_tan.x, w_tan);
    Cb = mix(Cb, ycc_tan.y, w_tan);
    Cr = mix(Cr, ycc_tan.z, w_tan);

    // --- 9) Temporal Settle using PREV
    vec3 prev_rgb = fetchRGB(PREV_tex, uv);
    vec3 prev_ycc = RGB_to_YCbCr(prev_rgb);
    // Curr and Prev metrics
    SobelOut s_prev = sobelLuma(PREV_tex, uv, px);
    float dtheta = abs(s.ang - s_prev.ang);
    // wrap angle to [0,pi]
    dtheta = mod(dtheta + 3.14159265, 6.2831853) - 3.14159265;
    dtheta = abs(dtheta);

    // motion: mean abs(Y_curr - Y_prev) in 3x3
    float mot = 0.0;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec2 uvo = uv + vec2(x,y)*px;
        float yc = RGB_to_YCbCr(fetchRGB(HOOKED_tex, uvo)).x;
        float yp = RGB_to_YCbCr(fetchRGB(PREV_tex,   uvo)).x;
        mot += abs(yc - yp);
    }
    mot /= 9.0;

    float Eprev = smoothstep(EdgeLo, EdgeHi, s_prev.norm);
    float cond = (E > 0.5 && Eprev > 0.5 && dtheta < 0.52 && mot < 0.05) ? 1.0 : 0.0;

    float Alpha = TempA * Strength;

    // Apply per-channel EMA
    float Yp = prev_ycc.x;
    float Cbp= prev_ycc.y;
    float Crp= prev_ycc.z;

    float Y_out  = mix(Y,  mix(Y,  Yp,  Alpha), cond);
    float Cb_out = mix(Cb, mix(Cb, Cbp, Alpha), cond);
    float Cr_out = mix(Cr, mix(Cr, Crp, Alpha), cond);

    // --- 10) Compose Output
    vec3 ycc_out = vec3(Y_out, Cb_out, Cr_out);
    vec3 rgb_out = YCbCr_to_RGB(ycc_out);
    // Soft roll-off clamp
    vec3 out_rgb = 0.5 + 0.5 * tanh(2.0 * (rgb_out - 0.5));
    out_rgb = clamp(out_rgb, 0.0, 1.0);

#if DEBUG_MODE == DEBUG_EDGEMASK
    return vec4(vec3(E), 1.0);
#elif DEBUG_MODE == DEBUG_PHASE
    {
        float ph = 0.5*(abs(phase_offset_Cb)+abs(phase_offset_Cr)) / max(PhaseMax, 1e-6);
        return vec4(vec3(saturate(ph)), 1.0);
    }
#elif DEBUG_MODE == DEBUG_TANGENT
    return vec4(vec3(w_tan), 1.0);
#elif DEBUG_MODE == DEBUG_COMPOSITE
    vec3 rgb_orig = rgb_in;
    vec3 rgb_mix = (uv.x < 0.5) ? rgb_orig : out_rgb;
    return vec4(rgb_mix, 1.0);
#else
    return vec4(out_rgb, 1.0);
#endif
}
