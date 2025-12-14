#version 450

//!PARAM clean_strength
//!TYPE float
0.35

//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Mild Clean+BlockFix (edge-aware denoise + flat deblock + dering + stochastic gating)

float luma2020(vec3 c) {
    return dot(c, vec3(0.2627, 0.6780, 0.0593));
}

vec3 rgb_to_ycbcr2020(vec3 rgb) {
    const float Kr = 0.2627;
    const float Kb = 0.0593;
    const float Kg = 1.0 - Kr - Kb;
    float Y  = Kr * rgb.r + Kg * rgb.g + Kb * rgb.b;
    float Cb = (rgb.b - Y) / (2.0 * (1.0 - Kb));
    float Cr = (rgb.r - Y) / (2.0 * (1.0 - Kr));
    return vec3(Y, Cb, Cr);
}

vec3 ycbcr_to_rgb2020(vec3 ycc) {
    const float Kr = 0.2627;
    const float Kb = 0.0593;
    const float Kg = 1.0 - Kr - Kb;
    float Y  = ycc.x;
    float Cb = ycc.y;
    float Cr = ycc.z;
    float R = Y + Cr * (2.0 * (1.0 - Kr));
    float B = Y + Cb * (2.0 * (1.0 - Kb));
    float G = (Y - Kr * R - Kb * B) / max(Kg, 1e-6);
    return vec3(R, G, B);
}

float w_spatial(vec2 d, float sigma_s) {
    float ss2 = max(sigma_s * sigma_s, 1e-6);
    return exp(-dot(d, d) / (2.0 * ss2));
}

float w_range(float dy, float sigma_r) {
    float sr2 = max(sigma_r * sigma_r, 1e-8);
    return exp(-(dy * dy) / (2.0 * sr2));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float block_edge_gate(float pix, float block_sz, float width_px) {
    float f = fract(pix / block_sz);
    float d = min(f, 1.0 - f) * block_sz; // distance in px to nearest boundary
    return 1.0 - smoothstep(0.0, max(width_px, 1e-6), d);
}

vec3 texRGB(vec2 uv) {
    return HOOKED_tex(uv).rgb;
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size;
    vec2 p  = uv * HOOKED_size;

    float s = clamp(clean_strength, 0.0, 1.0);

    float sigma_s  = mix(0.85, 1.35, s);
    float sigma_rY = mix(0.010, 0.040, s);
    float sigma_rC = sigma_rY * 1.8;

    // Stochastic gating noise (affects only decisions, not output grain)
    float hn = hash12(p + vec2(float(frame) * 0.37, random * 61.0)) - 0.5;
    float jitterY = hn * (0.0015 * s);

    // Base samples (3x3)
    vec3 c00  = texRGB(uv);
    vec3 c10  = texRGB(uv + vec2( px.x, 0.0));
    vec3 c_10 = texRGB(uv + vec2(-px.x, 0.0));
    vec3 c01  = texRGB(uv + vec2(0.0,  px.y));
    vec3 c0_1 = texRGB(uv + vec2(0.0, -px.y));
    vec3 c11  = texRGB(uv + vec2( px.x,  px.y));
    vec3 c_11 = texRGB(uv + vec2(-px.x,  px.y));
    vec3 c1_1 = texRGB(uv + vec2( px.x, -px.y));
    vec3 c_1_1= texRGB(uv + vec2(-px.x, -px.y));

    vec3 ycc00 = rgb_to_ycbcr2020(c00);
    float Y0   = ycc00.x;
    float Y0j  = Y0 + jitterY;

    float wsumY = 0.0;
    float Ysum  = 0.0;
    float wsumC = 0.0;
    vec2  Csum  = vec2(0.0);

    // Unrolled 3x3 bilateral (range term uses jittered center luma)
    {
        vec2 d = vec2(0.0, 0.0);
        float Ys = luma2020(c00);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = ycc00;
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(1.0, 0.0);
        float Ys = luma2020(c10);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c10);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(-1.0, 0.0);
        float Ys = luma2020(c_10);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c_10);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(0.0, 1.0);
        float Ys = luma2020(c01);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c01);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(0.0, -1.0);
        float Ys = luma2020(c0_1);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c0_1);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(1.0, 1.0);
        float Ys = luma2020(c11);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c11);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(-1.0, 1.0);
        float Ys = luma2020(c_11);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c_11);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(1.0, -1.0);
        float Ys = luma2020(c1_1);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c1_1);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }
    {
        vec2 d = vec2(-1.0, -1.0);
        float Ys = luma2020(c_1_1);
        float ws = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rY);
        float wc = w_spatial(d, sigma_s) * w_range(Ys - Y0j, sigma_rC);
        vec3 ycc = rgb_to_ycbcr2020(c_1_1);
        wsumY += ws; Ysum += ws * ycc.x;
        wsumC += wc; Csum += wc * ycc.yz;
    }

    float Yd = (wsumY > 0.0) ? (Ysum / wsumY) : Y0;
    vec2  Cd = (wsumC > 0.0) ? (Csum / wsumC) : ycc00.yz;
    vec3 denoised = ycbcr_to_rgb2020(vec3(Yd, Cd));

    // Flatness detector (center + 4-neighbors), with slight stochastic thresholding
    float YL = luma2020(c_10);
    float YR = luma2020(c10);
    float YU = luma2020(c01);
    float YD = luma2020(c0_1);

    float mY = 0.2 * (Y0 + YL + YR + YU + YD);
    float v  = 0.2 * ((Y0 - mY)*(Y0 - mY) + (YL - mY)*(YL - mY) + (YR - mY)*(YR - mY) + (YU - mY)*(YU - mY) + (YD - mY)*(YD - mY));

    float vscale = mix(0.0025, 0.0100, s) * (1.0 + hn * 0.20);
    float flatness = exp(-v / max(vscale * vscale, 1e-8)); // 1 flat, 0 detailed

    vec3 blur5 = (c00 + c_10 + c10 + c01 + c0_1) * 0.2;
    vec3 deblocked = mix(denoised, blur5, flatness * (0.35 * s));

    // Macroblock boundary fix (8x8) when both sides look locally flat
    vec3 c20  = texRGB(uv + vec2( 2.0 * px.x, 0.0));
    vec3 c_20 = texRGB(uv + vec2(-2.0 * px.x, 0.0));
    vec3 c02  = texRGB(uv + vec2(0.0,  2.0 * px.y));
    vec3 c0_2 = texRGB(uv + vec2(0.0, -2.0 * px.y));

    float YLL = luma2020(c_20);
    float YRR = luma2020(c20);
    float YUU = luma2020(c02);
    float YDD = luma2020(c0_2);

    float thr_side = mix(0.006, 0.020, s);

    float flatL = exp(-abs(YL - YLL) / max(thr_side, 1e-6));
    float flatR = exp(-abs(YR - YRR) / max(thr_side, 1e-6));
    float flatU = exp(-abs(YU - YUU) / max(thr_side, 1e-6));
    float flatD = exp(-abs(YD - YDD) / max(thr_side, 1e-6));

    float bx = block_edge_gate(p.x + hn * 0.35, 8.0, 0.55);
    float by = block_edge_gate(p.y - hn * 0.35, 8.0, 0.55);

    float wbx = bx * flatness * (flatL * flatR) * (0.55 * s);
    float wby = by * flatness * (flatU * flatD) * (0.55 * s);

    vec3 avgLR = 0.5 * (c_10 + c10);
    vec3 avgUD = 0.5 * (c0_1 + c01);

    vec3 blockfixed = deblocked;
    blockfixed = mix(blockfixed, avgLR, clamp(wbx, 0.0, 1.0));
    blockfixed = mix(blockfixed, avgUD, clamp(wby, 0.0, 1.0));

    // Dering / mosquito suppression near edges (attenuate residual detail near edges)
    float grad = abs(YR - YL) + abs(YU - YD);
    float edge = clamp(grad / 0.080, 0.0, 1.0);

    vec3 detail = c00 - blockfixed;
    float atten = 1.0 - (0.65 * s) * edge;
    vec3 cleaned = blockfixed + detail * clamp(atten, 0.0, 1.0);

    vec3 out_rgb = mix(c00, cleaned, s);

    out_color = vec4(clamp(out_rgb, 0.0, 1.0), 1.0);
    return out_color;
}
