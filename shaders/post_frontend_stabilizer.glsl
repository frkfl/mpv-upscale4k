//!PARAM dering_sigma
//!TYPE float
0.85
//!PARAM dering_mix_max
//!TYPE float
0.30
//!PARAM agc_gamma
//!TYPE float
0.6
//!PARAM agc_k0
//!TYPE float
0.02
//!PARAM agc_k1
//!TYPE float
0.35
//!PARAM agc_delta_max
//!TYPE float
0.25
//!PARAM agc_scale_kappa
//!TYPE float
0.9
//!PARAM unclip_shadow_power
//!TYPE float
0.88
//!PARAM unclip_highlight_power
//!TYPE float
1.05
//!PARAM unclip_eta_fill
//!TYPE float
0.03
//!PARAM hue_cap_deg_skin
//!TYPE float
3.0
//!PARAM hue_cap_deg_global
//!TYPE float
5.0
//!PARAM sat_cap_skin
//!TYPE float
0.12
//!PARAM sat_cap_global
//!TYPE float
0.20
//!PARAM meanY_guard_pct
//!TYPE float
0.005
//!PARAM ring_kappa
//!TYPE float
0.5
//!PARAM ring_gain
//!TYPE float
3.0
//!PARAM protect_grad_lo
//!TYPE float
0.06
//!PARAM protect_grad_hi
//!TYPE float
0.16
//!PARAM motion_lo
//!TYPE float
0.01
//!PARAM motion_hi
//!TYPE float
0.03
//!PARAM highlights_gate_Y
//!TYPE float
0.85

//!HOOK MAIN
//!BIND HOOKED
//!DESC Post Front-End Stabilizer v1 — optimized (branchless, 3-tap FIR, fused windows)

#define EPS 1e-6
#define PI  3.14159265358979323846

// ---------- RGB<->YCbCr (BT.601, gamma) ----------
vec3 rgb2ycc601(vec3 rgb){
    float Y  = dot(rgb, vec3(0.299, 0.587, 0.114));
    float Cb = (rgb.b - Y) / 1.772;
    float Cr = (rgb.r - Y) / 1.402;
    return vec3(Y, Cb, Cr);
}
vec3 ycc6012rgb(vec3 ycc){
    float Y=ycc.x, Cb=ycc.y, Cr=ycc.z;
    float R = Y + 1.402 * Cr;
    float B = Y + 1.772 * Cb;
    float G = (Y - 0.299*R - 0.114*B) / 0.587;
    return vec3(R,G,B);
}
float luma_at(vec2 p){ return rgb2ycc601(HOOKED_tex(p).rgb).x; }
vec3  ycc_at (vec2 p){ return rgb2ycc601(HOOKED_tex(p).rgb); }

float G_from_S(float S){ return clamp((S - 1.0), 0.0, 1.0); } // S∈[0,2] -> [0,1]
float sstep(float a,float b,float x){ return smoothstep(a,b,clamp(x,min(a,b),max(a,b))); }
vec2  safe_norm(vec2 v){ float m=max(length(v),EPS); return v/m; }

// Broad skin mask in CbCr (branchless)
float skin_mask(vec2 C){
    float theta = atan(C.y, C.x);   // atan(Cr, Cb)
    float center = PI*0.5;
    float d = abs(atan(tan(theta - center)));
    float ang_w = radians(55.0);
    float ang_term = 1.0 - sstep(ang_w*0.5, ang_w, d);
    float m = length(C);
    float mag_term = smoothstep(0.04, 0.20, m) * (1.0 - smoothstep(0.45, 0.65, m));
    return clamp(ang_term * mag_term, 0.0, 1.0);
}

// Motion proxy (no history): diagonal diff
float motion_mask(vec2 p){
    vec2 d = HOOKED_pt * 1.5;
    float a = abs(luma_at(p + d) - luma_at(p - d));
    return sstep(motion_lo, motion_hi, a);
}

// Directional 3-tap FIR blur along a given normal (weights 0.25,0.5,0.25)
vec2 blur3_chroma(vec2 p, vec2 normal){
    vec2 px = HOOKED_pt;
    vec2 n = safe_norm(normal);
    vec2 dir = vec2(-n.y, n.x);
    vec3 c0 = ycc_at(p).xyz;
    vec2 C0 = c0.yz;
    vec2 C1 = ycc_at(p + dir*px).yz;
    vec2 C_1= ycc_at(p - dir*px).yz;
    return 0.25*C_1 + 0.5*C0 + 0.25*C1;
}

// ------------------------------ MAIN ------------------------------
vec4 hook(){
    vec2 p = HOOKED_pos;
    vec4 src = HOOKED_tex(p);
    vec3 ycc0 = rgb2ycc601(src.rgb);
    float Yc = ycc0.x;
    vec2  Cc = ycc0.yz;

    // ===== Fused 3x3 neighborhood pass (min/max/mean/var/amp + gradient) =====
    vec2 px = HOOKED_pt;
    float meanY = 0.0, meanY2 = 0.0, ampC = 0.0;
    float t_black = 0.0, t_white = 0.0;
    float Ymin = 1.0, Ymax = 0.0;

    // Central diffs for gradient from immediate neighbors (included in loop)
    float Yl=0.0, Yr=0.0, Yu=0.0, Yd=0.0;

    // Accumulate 3x3
    for(int j=-1;j<=1;j++){
        for(int i=-1;i<=1;i++){
            vec2 q = p + vec2(float(i)*px.x, float(j)*px.y);
            vec3 ycc = ycc_at(q);
            float Y = ycc.x;
            vec2  C = ycc.yz;
            meanY  += Y;
            meanY2 += Y*Y;
            ampC   += length(C);
            Ymin    = min(Ymin, Y);
            Ymax    = max(Ymax, Y);
            t_black += step(Y, 0.02);
            t_white += step(0.98, Y);

            // Save axis-adjacent for gradient quickly
            Yl += (i==-1 && j==0) ? Y : 0.0;
            Yr += (i==+1 && j==0) ? Y : 0.0;
            Yu += (i==0 && j==-1) ? Y : 0.0;
            Yd += (i==0 && j==+1) ? Y : 0.0;
        }
    }
    meanY  /= 9.0;
    meanY2 /= 9.0;
    float varY = max(meanY2 - meanY*meanY, 0.0);
    float A    = ampC / 9.0;
    float Tb   = t_black / 9.0;
    float Tw   = t_white / 9.0;

    // Gradient & normal (central diff)
    vec2 gY = vec2((Yr - Yl) * 0.5, (Yd - Yu) * 0.5);
    vec2 n_edge = vec2(-gY.y, gY.x);

    // Protect mask via gradient magnitude (cheaper than DoG)
    float Protect = sstep(protect_grad_lo, protect_grad_hi, length(gY));

    // ===== 1) Auto Dering Detector (cheap oscillation metric) =====
    // 3-sample Cb/Cr along normal: C[-1], C0, C[+1]
    vec2 C_m1 = ycc_at(p - safe_norm(n_edge)*px).yz;
    vec2 C_p1 = ycc_at(p + safe_norm(n_edge)*px).yz;

    // Δ- and Δ+: differences relative to center
    vec2 dM = Cc - C_m1;
    vec2 dP = C_p1 - Cc;

    // Oscillation score per channel: opposite slopes → (dM⋅dP)<0
    float Ocb = max(0.0, -(dM.x * dP.x));
    float Ocr = max(0.0, -(dM.y * dP.y));
    float O   = max(Ocb, Ocr);

    // Normalize by local chroma energy
    float E    = length(Cc) + EPS;
    float Sraw = O / (O + ring_kappa * E);
    float Sring= clamp(ring_gain * Sraw, 0.0, 2.0);

    // Directional 3-tap FIR along normal (zero phase) + capped mix
    float w_ring = min(0.30 * G_from_S(Sring) * (1.0 - Protect), dering_mix_max);
    vec2  C_der  = mix(Cc, blur3_chroma(p, n_edge), w_ring);

    // ===== 2) Auto Chroma Gain Compensation (hue-preserving) =====
    float g_rel = A / (EPS + pow(max(meanY, EPS), agc_gamma));
    float g_tgt = agc_k0 + agc_k1 * pow(max(meanY, EPS), agc_gamma);
    float delta = clamp((g_rel - g_tgt) / max(g_tgt, EPS), -agc_delta_max, agc_delta_max);

    float Q = varY / (varY + 0.01*0.01);
    float S_agc = 1.4; // active by default
    float W = 0.5 * abs(delta) * Q * G_from_S(clamp(S_agc,0.0,2.0));
    W *= mix(1.0, 0.5, step(highlights_gate_Y, Yc)); // highlight guard

    float sgn   = (delta > 0.0) ? 1.0 : -1.0;
    float scale = 1.0 - sgn * agc_scale_kappa * W;

    // Skin guard: cap saturation delta
    float skin  = skin_mask(C_der);
    float sat0  = length(C_der);
    float sat1  = length(C_der * scale);
    float dsat  = sat1 - sat0;
    float ds_cap= mix(sat_cap_global, sat_cap_skin, skin);
    float sat1c = sat0 + clamp(dsat, -ds_cap, ds_cap);
    float scl_c = (sat0 > EPS) ? (sat1c / sat0) : 1.0;
    vec2  C_agc = C_der * scl_c;

    // ===== 3) Auto Unclip (toe/shoulder, colored fill) =====
    // Flatness proxies in tails via 3×3 variance: use varY as shared proxy
    float S_blk = sstep(0.10, 0.30, Tb) * (1.0 - sstep(0.002, 0.01, varY));
    float S_wht = sstep(0.10, 0.30, Tw) * (1.0 - sstep(0.002, 0.01, varY));

    float W_blk = 0.6 * G_from_S(S_blk);
    float W_wht = 0.6 * G_from_S(S_wht);

    // Motion gating (reduce correction where motion > 0.5)
    float M = motion_mask(p);
    float mcut = step(0.5, M);
    W_blk *= mix(1.0, 0.5, mcut);
    W_wht *= mix(1.0, 0.5, mcut);

    float Y_toe = mix(Yc, pow(max(Yc,0.0), unclip_shadow_power), W_blk);
    float Y_sh  = mix(Y_toe, 1.0 - pow(max(1.0 - Y_toe,0.0), unclip_highlight_power), W_wht);
    float Y3    = Y_sh;

    // Colored fill: local midtone hue direction (cheap estimate: use current C direction normalized)
    vec2 h_mid = (length(C_agc) > EPS) ? normalize(C_agc) : vec2(0.0);
    vec2 C_fill= C_agc + unclip_eta_fill * W_blk * h_mid;

    // Shadow chroma gate (fade below 0.08)
    float fade = 1.0 - sstep(0.0, 0.08, Y3);
    vec2  C3   = mix(C_fill, C_fill * (1.0 - 0.6*fade), 1.0);

    // Local contrast guard using Michelson from fused Ymin/Ymax
    float mic = (Ymax - Ymin) / max(Ymax + Ymin, EPS);
    float allow = step(0.015, mic);
    Y3 = mix(Yc, Y3, allow);
    C3 = mix(C_agc, C3, allow);

    // Mean-Y guard (tiny pull toward original)
    Y3 = mix(Y3, Yc, clamp(meanY_guard_pct*2.0, 0.0, 1.0));

    // Specular color preserve: limit sat change ≤10% at Y>0.9
    float ymask = sstep(0.90, 1.00, Yc);
    float s0 = length(Cc), s3 = length(C3);
    float s_lim = clamp((s3 - s0) / max(s0, EPS), -0.10, 0.10);
    float s_tgt = s0 * (1.0 + s_lim);
    float s_k   = (s3 > EPS) ? (s_tgt / s3) : 1.0;
    vec2  C_hi  = mix(C3, C3 * s_k, ymask);

    // Output
    vec3 out_rgb = ycc6012rgb(vec3(clamp(Y3,0.0,1.0), C_hi));
    return vec4(clamp(out_rgb, 0.0, 1.0), src.a);
}
