//!PARAM strength_phase
//!TYPE float
1.0

//!PARAM strength_tone
//!TYPE float
0.7

//!PARAM edge_threshold
//!TYPE float
0.08

//!PARAM shadow_threshold
//!TYPE float
0.20

//!PARAM motion_threshold
//!TYPE float
0.06

//!PARAM debug_mode
//!TYPE float
0.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Front-End Normalization Pass — Deterministic, Perceptual-Grade

// ---- Helpers & Color Transforms (Rec.601/709 YCbCr in [0..1]) ----
float saturate(float x){ return clamp(x, 0.0, 1.0); }
vec3  clamp01(vec3 v){ return clamp(v, 0.0, 1.0); }
vec3  texRGB(sampler2D t, vec2 uv){ return texture(t, uv).rgb; }

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

// ---- Sampling & Filters ----
struct SobelOut { vec2 g; float mag; float ang; };
SobelOut sobelY(sampler2D tex, vec2 uv, vec2 px){
    float a = dot(texRGB(tex, uv + vec2(-1,-1)*px), vec3(0.299,0.587,0.114));
    float b = dot(texRGB(tex, uv + vec2( 0,-1)*px), vec3(0.299,0.587,0.114));
    float c = dot(texRGB(tex, uv + vec2( 1,-1)*px), vec3(0.299,0.587,0.114));
    float d = dot(texRGB(tex, uv + vec2(-1, 0)*px), vec3(0.299,0.587,0.114));
    float f = dot(texRGB(tex, uv + vec2( 1, 0)*px), vec3(0.299,0.587,0.114));
    float g = dot(texRGB(tex, uv + vec2(-1, 1)*px), vec3(0.299,0.587,0.114));
    float h = dot(texRGB(tex, uv + vec2( 0, 1)*px), vec3(0.299,0.587,0.114));
    float i = dot(texRGB(tex, uv + vec2( 1, 1)*px), vec3(0.299,0.587,0.114));
    float Gx = (c + 2.0*f + i) - (a + 2.0*d + g);
    float Gy = (g + 2.0*h + i) - (a + 2.0*b + c);
    vec2 gg = vec2(Gx, Gy);
    float mag = length(gg);
    float ang = atan(gg.y, gg.x);
    return SobelOut(gg, mag, ang);
}

float mean3x3Y(sampler2D tex, vec2 uv, vec2 px){
    float acc = 0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++)
        acc += dot(texRGB(tex, uv + vec2(x,y)*px), vec3(0.299,0.587,0.114));
    return acc / 9.0;
}
float var3x3Y(sampler2D tex, vec2 uv, vec2 px){
    float m = mean3x3Y(tex, uv, px);
    float acc = 0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){
        float Y = dot(texRGB(tex, uv + vec2(x,y)*px), vec3(0.299,0.587,0.114));
        acc += (Y - m)*(Y - m);
    }
    return acc / 9.0;
}

// Gaussian 5x5 with sigma
vec3 gaussian5x5_rgb(sampler2D tex, vec2 uv, vec2 px, float sigma){
    sigma = max(sigma, 1e-6);
    float s2 = sigma*sigma;
    vec3 acc = vec3(0.0); float wsum = 0.0;
    for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++){
        vec2 o = vec2(x,y);
        float w = exp(-(dot(o,o))/(2.0*s2));
        acc += texRGB(tex, uv + o*px) * w;
        wsum += w;
    }
    return acc / max(wsum, 1e-6);
}

// Detect chroma gradient peak offset along normal (±3 px) via sign change
float phaseOffset_sign(sampler2D tex, vec2 uv, vec2 n, vec2 px, int chan){ // chan: 1=Cb, 2=Cr
    float prev = RGB_to_YCbCr(texRGB(tex, uv - 3.0*n*px))[chan];
    float curr = RGB_to_YCbCr(texRGB(tex, uv - 2.0*n*px))[chan];
    float prevd = curr - prev;
    float best = 0.0;
    for(int i=-2;i<=2;i++){
        float a = RGB_to_YCbCr(texRGB(tex, uv + float(i)*n*px))[chan];
        float b = RGB_to_YCbCr(texRGB(tex, uv + float(i+1)*n*px))[chan];
        float d = b - a;
        if(prevd * d <= 0.0){ best = float(i) + 0.5; break; }
        prevd = d;
    }
    return best; // in px along n
}

// One-way bleed mask: signed asymmetry of luma across the edge normal
float bleed_asymmetry(sampler2D tex, vec2 uv, vec2 n, vec2 px){
    float Lm = 0.0, Rp = 0.0;
    for(int k=1;k<=3;k++){
        Lm += dot(texRGB(tex, uv - float(k)*n*px), vec3(0.299,0.587,0.114));
        Rp += dot(texRGB(tex, uv + float(k)*n*px), vec3(0.299,0.587,0.114));
    }
    Lm /= 3.0; Rp /= 3.0;
    return saturate((Rp - Lm) * 4.0) - saturate((Lm - Rp) * 4.0); // signed bias
}

// ---- Main Pass ----
vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Inputs
    vec3 rgb_now  = texRGB(HOOKED_tex, uv);
    vec3 rgb_prev = texRGB(PREV_tex,   uv);

    // Work in YCbCr (preserve source range; no remap)
    vec3 ycc0 = RGB_to_YCbCr(rgb_now);
    float Y = ycc0.x, Cb = ycc0.y, Cr = ycc0.z;

    // ---- Edge metrics & masks ----
    SobelOut s = sobelY(HOOKED_tex, uv, px);
    float G = s.mag;
    float edge_lo = edge_threshold;                 // anchor
    float E = smoothstep(edge_lo*0.5, edge_lo, G);  // edge presence [0..1]
    vec2 n = (G > 0.0) ? normalize(s.g) : vec2(1.0,0.0);
    vec2 t = vec2(-n.y, n.x);

    // ---- A) Phase realignment & Y<->C unmix (driven by strength_phase) ----
    float sp = max(strength_phase, 0.0);
    float phase_radius = sqrt(sp);                  // grows with √strength_phase
    float phase_cap = clamp(phase_radius, 0.0, 3.0);
    // Phase offsets (px) measured along normal
    float offCb = phaseOffset_sign(HOOKED_tex, uv, n, px, 1);
    float offCr = phaseOffset_sign(HOOKED_tex, uv, n, px, 2);
    float phiCb = clamp(offCb, -phase_cap, phase_cap);
    float phiCr = clamp(offCr, -phase_cap, phase_cap);

    // Edge protection relaxes as sp rises (so you can overdrive)
    float edge_protect_relax = 1.0 / (1.0 + 0.5*sp); // 1→0 with strength
    float edge_guard = mix(1.0, 1.0 - E, edge_protect_relax); // less guard at strong sp
    float chroma_align_k = saturate(0.65 * (1.0 - edge_guard) + 0.25 * saturate(sp*0.2));

    // Apply subpixel chroma shift (deterministic bilinear)
    float Cb_shift = RGB_to_YCbCr(texRGB(HOOKED_tex, uv + phiCb * n * px)).y;
    float Cr_shift = RGB_to_YCbCr(texRGB(HOOKED_tex, uv + phiCr * n * px)).z;
    Cb = mix(Cb, Cb_shift, chroma_align_k);
    Cr = mix(Cr, Cr_shift, chroma_align_k);

    // One-way bleed damping (directional along normal)
    float asym = bleed_asymmetry(HOOKED_tex, uv, n, px); // + means right brighter
    float bleed_k = saturate(sp * 0.25) * (1.0 - 0.75*E); // protect strong edges
    // Damp chroma on the "receiving" side of bright→dark transitions
    float damp = mix(1.0, 0.8, bleed_k*abs(asym));
    Cb *= damp; Cr *= damp;

    // Y<->C unmixing (reduce crosstalk)
    float unmix_k = saturate(sp * 0.12);
    float Y_from_C = (Cr - 0.5)*0.06 + (Cb - 0.5)*(-0.04);
    float Cb_from_Y = (Y - 0.5)*0.04;
    float Cr_from_Y = (Y - 0.5)*0.05;
    Y  -= unmix_k * Y_from_C;
    Cb -= unmix_k * Cb_from_Y;
    Cr -= unmix_k * Cr_from_Y;

    // Analog band-limit / denoise: chroma wider than luma, edge-aware
    float sigmaC = 0.3 + 0.25 * sqrt(sp); // chroma broadens faster
    float sigmaY = 0.2 + 0.10 * sqrt(sp); // modest luma LP
    vec3  blurC  = gaussian5x5_rgb(HOOKED_tex, uv, px, sigmaC);
    vec3  blurY  = gaussian5x5_rgb(HOOKED_tex, uv, px, sigmaY);
    vec3  yccC   = RGB_to_YCbCr(blurC);
    vec3  yccY   = RGB_to_YCbCr(blurY);
    float flat = 1.0 - E;
    float lp_kC = saturate(flat * (0.35 + 0.25*sqrt(sp)));
    float lp_kY = saturate(flat * (0.20 + 0.15*sqrt(sp)));
    Cb = mix(Cb, yccC.y, lp_kC);
    Cr = mix(Cr, yccC.z, lp_kC);
    Y  = mix(Y,  yccY.x, lp_kY);

    // ---- C) Tone & chroma balance (driven by strength_tone) ----
    float st = max(strength_tone, 0.0);

    // Temporal gain smoothing (EMA on per-pixel gain) for static zones
    float motion = 0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){
        vec2 u = uv + vec2(x,y)*px;
        float yc = RGB_to_YCbCr(texRGB(HOOKED_tex, u)).x;
        float yp = RGB_to_YCbCr(texRGB(PREV_tex,   u)).x;
        motion += abs(yc - yp);
    }
    motion /= 9.0;
    float motion_norm = motion / (motion + 0.02);
    float static_mask = step(motion_norm, motion_threshold); // 1 if below threshold

    float prevY = RGB_to_YCbCr(rgb_prev).x;
    float gain_now  = (Y  + 1e-6) / (prevY + 1e-6);
    float gain_prev = 1.0; // neutral
    float alpha_gain = 1.0 / (1.0 + 0.6*st); // stronger st → more smoothing (lower effective α)
    float gain_s = mix(gain_now, mix(gain_prev, gain_now, 1.0 - alpha_gain), static_mask);
    Y *= gain_s;

    // Highlight knee softening with st (protect chroma washout)
    float knee = 0.6 + 0.1 * saturate(st*0.2);
    float hk = saturate((Y - knee) / (1.0 - knee));
    Y = mix(Y, knee + hk*0.85*(1.0 - knee), 0.25 * saturate(st*0.2));

    // Shadows chroma restraint
    float shadow_gate = saturate((shadow_threshold - Y) / max(shadow_threshold, 1e-4));
    float chroma_rest = 0.15 * st * shadow_gate;
    Cb = mix(Cb, 0.5, chroma_rest);
    Cr = mix(Cr, 0.5, chroma_rest);

    // ---- D) Neutral axis maintenance (tiny & gentle) ----
    // Pull gray axis toward neutrality very slightly (tied to st)
    float neutral_pull = 0.02 * saturate(st*0.2);
    Cb = mix(Cb, 0.5, neutral_pull);
    Cr = mix(Cr, 0.5, neutral_pull);

    // ---- Compose ----
    vec3 ycc_out = vec3(Y, Cb, Cr);
    vec3 rgb_out = YCbCr_to_RGB(ycc_out);
    vec3 out_rgb = clamp01(rgb_out); // perceptually neutral; no gamma tricks

    // ---- Debug Overlays (non-invasive, selectable) ----
    // 1: Phase map (magnitude via |offCb|+|offCr|), 2: Bleed mask strength, 3: Edge mask, 4: Motion mask
    if (debug_mode > 0.5){
        float mode = debug_mode;
        // 1. Phase map
        if (abs(mode - 1.0) < 0.5){
            float ph = 0.5*(abs(offCb)+abs(offCr)) / max(phase_cap, 1e-6);
            return vec4(mix(out_rgb, vec3(saturate(ph)), 0.8), 1.0);
        }
        // 2. Bleed mask strength
        if (abs(mode - 2.0) < 0.5){
            float bm = saturate(abs(asym));
            return vec4(mix(out_rgb, vec3(bm), 0.8), 1.0);
        }
        // 3. Edge mask visualization
        if (abs(mode - 3.0) < 0.5){
            return vec4(mix(out_rgb, vec3(E), 0.8), 1.0);
        }
        // 4. Motion mask visualization
        if (abs(mode - 4.0) < 0.5){
            return vec4(mix(out_rgb, vec3(static_mask), 0.8), 1.0);
        }
    }

    return vec4(out_rgb, 1.0);
}
