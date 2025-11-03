#version 450
//!PARAM alpha
//!TYPE float
0.8

//!PARAM delta_max
//!TYPE float
0.08

//!PARAM delta_exp
//!TYPE float
2.0

//!PARAM var_sensitivity
//!TYPE float
0.6

//!PARAM blur_sigma
//!TYPE float
0.8

//!PARAM chroma_alpha
//!TYPE float
0.4

//!PARAM debug_mode
//!TYPE float
0.0

//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV
//!DESC Temporal Structural Stabilizer (TSS) — deterministic temporal/spatial stabilizer

// Helpers
float saturate(float x){ return clamp(x, 0.0, 1.0); }
vec3  clamp01(vec3 v){ return clamp(v, 0.0, 1.0); }
vec3  fetchRGB(sampler2D t, vec2 uv){ return texture(t, uv).rgb; }

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

// 3x3 mean filter for vec3 field
vec3 mean3x3_rgb(sampler2D tex, vec2 uv, vec2 px){
    vec3 acc = vec3(0.0);
    for (int y=-1; y<=1; y++)
    for (int x=-1; x<=1; x++){
        acc += fetchRGB(tex, uv + vec2(x,y)*px);
    }
    return acc / 9.0;
}

// 3x3 mean on scalar (for variance)
float mean3x3_chan(sampler2D tex, vec2 uv, vec2 px, int chan){
    float acc = 0.0;
    for (int y=-1; y<=1; y++)
    for (int x=-1; x<=1; x++){
        vec3 rgb = fetchRGB(tex, uv + vec2(x,y)*px);
        float v = (chan==0)? dot(rgb, vec3(0.299,0.587,0.114)) : (chan==1? rgb.g : rgb.b); // chan 0 ~ Y proxy on RGB
        acc += v;
    }
    return acc / 9.0;
}

// Sobel gradient magnitude on Y (from RGB)
float sobel_mag_Y(sampler2D tex, vec2 uv, vec2 px){
    float a = dot(fetchRGB(tex, uv + vec2(-1,-1)*px), vec3(0.299,0.587,0.114));
    float b = dot(fetchRGB(tex, uv + vec2( 0,-1)*px), vec3(0.299,0.587,0.114));
    float c = dot(fetchRGB(tex, uv + vec2( 1,-1)*px), vec3(0.299,0.587,0.114));
    float d = dot(fetchRGB(tex, uv + vec2(-1, 0)*px), vec3(0.299,0.587,0.114));
    float f = dot(fetchRGB(tex, uv + vec2( 1, 0)*px), vec3(0.299,0.587,0.114));
    float g = dot(fetchRGB(tex, uv + vec2(-1, 1)*px), vec3(0.299,0.587,0.114));
    float h = dot(fetchRGB(tex, uv + vec2( 0, 1)*px), vec3(0.299,0.587,0.114));
    float i = dot(fetchRGB(tex, uv + vec2( 1, 1)*px), vec3(0.299,0.587,0.114));

    float Gx = (c + 2.0*f + i) - (a + 2.0*d + g);
    float Gy = (g + 2.0*h + i) - (a + 2.0*b + c);
    return length(vec2(Gx, Gy));
}

// Gaussian blur (5x5) with sigma in [0..2]; sigma=0 → return source
vec3 gaussian5x5(vec2 uv, vec2 px, sampler2D tex, float sigma){
    sigma = max(sigma, 1e-6);
    float s2 = sigma * sigma;
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int y=-2; y<=2; y++){
        for (int x=-2; x<=2; x++){
            vec2 o = vec2(x,y);
            float w = exp(-(dot(o,o)) / (2.0*s2));
            acc += fetchRGB(tex, uv + o*px) * w;
            wsum += w;
        }
    }
    return acc / max(wsum, 1e-6);
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;

    // Read current & previous frames
    vec3 curr = fetchRGB(HOOKED_tex, uv);
    vec3 prev = fetchRGB(PREV_tex,   uv);

    // --- Temporal difference evaluation (Δ)
    vec3 delta_raw = abs(curr - prev);
    // Optional smoothing (apply deterministically)
    // Smooth Δ via 3x3 mean on RGB diffs
    vec3 delta_smooth = vec3(0.0);
    for (int y=-1; y<=1; y++)
    for (int x=-1; x<=1; x++){
        vec2 u = uv + vec2(x,y)*px;
        delta_smooth += abs(fetchRGB(HOOKED_tex, u) - fetchRGB(PREV_tex, u));
    }
    delta_smooth /= 9.0;
    vec3 Delta = delta_smooth;

    // --- Weight computation: w = clamp(1 - (Δ/delta_max)^delta_exp, 0..1)
    float dmax = max(delta_max, 1e-6);
    float dexp = max(delta_exp, 1.0);
    vec3 w = vec3(1.0) - pow(clamp(Delta / dmax, vec3(0.0), vec3(1e6)), vec3(dexp));
    w = clamp01(w);

    // --- Adaptive local variance gating (3x3 on current frame)
    // Compute variance on luma proxy from RGB
    float m = mean3x3_chan(HOOKED_tex, uv, px, 0);
    float v = 0.0;
    for (int y=-1; y<=1; y++)
    for (int x=-1; x<=1; x++){
        float Y = dot(fetchRGB(HOOKED_tex, uv + vec2(x,y)*px), vec3(0.299,0.587,0.114));
        v += (Y - m)*(Y - m);
    }
    v /= 9.0;
    // Normalize variance to [0,1]
    float v_norm = v / (v + 0.01);
    float g = mix(1.0, v_norm, saturate(var_sensitivity)); // lower variance -> closer to 1.0

    // --- Temporal fusion: stabilized = mix(curr, prev, alpha * w * g)
    float a = alpha;
    vec3 blendF = clamp(vec3(a * g) * w, vec3(0.0), vec3(1.0));
    vec3 stabilized = mix(curr, prev, blendF); // per-channel blend

    // --- Spatial reinforcement (Gaussian blur weighted by edge inverse)
    // Edge-preserving factor based on gradient magnitude of stabilized luma
    // Compute gradient on the stabilized approximation by sampling from a tiny synthetic tex:
    // We'll approximate by using HOOKED_tex gradient as proxy (deterministic & cheap)
    float grad_mag = sobel_mag_Y(HOOKED_tex, uv, px);
    float grad_norm = grad_mag / (grad_mag + 0.001);
    float edge_keep = 1.0 - grad_norm; // stronger blur where edges are weak

    float sigma = clamp(blur_sigma, 0.0, 2.0);
    vec3 blurred = (sigma > 0.0) ? gaussian5x5(uv, px, HOOKED_tex, sigma) : stabilized;
    // Blend in RGB domain with edge-aware factor
    float sblend = saturate( (sigma * 0.5) * edge_keep );
    stabilized = mix(stabilized, blurred, sblend);

    // --- Final chroma-luma re-merge: extra chroma temporal smoothing
    vec3 ycc_stab = RGB_to_YCbCr(stabilized);
    vec3 ycc_prev = RGB_to_YCbCr(prev);
    float ca = saturate(chroma_alpha);
    ycc_stab.y = mix(ycc_stab.y, ycc_prev.y, ca);
    ycc_stab.z = mix(ycc_stab.z, ycc_prev.z, ca);
    vec3 out_rgb = YCbCr_to_RGB(ycc_stab);

    // Output
    vec3 out_fin = clamp01(0.5 + 0.5 * tanh(2.0 * (out_rgb - 0.5)));

    // Debug overlay: visualize temporal weights as grayscale (higher=w→more blend)
    if (debug_mode > 0.5){
        float wl = dot(w, vec3(0.299, 0.587, 0.114)); // weight luminance
        return vec4(vec3(wl), 1.0);
    }

    return vec4(out_fin, 1.0);
}
