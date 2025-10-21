//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Micro entropy grain for pre-downscale (luma-biased, blue-noise, ultra low energy)
//!PARAM float strength = 0.009      // 0.006–0.012 typical; keep tiny
//!PARAM float chroma   = 0.20       // low chroma to avoid color crawl
//!PARAM float grain_size = 1.3      // 1.1–1.6: micro grain scale
//!PARAM float midtone_bias = 0.75   // 0..1: more weight in midtones
//!PARAM float animate = 1.0         // 1 = slight temporal evolution, 0 = static

// Goal: seed subtle texture before SSIM downscale so flats won't collapse,
// without changing luma statistics enough to confuse FSRCNNX.

float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// blue-ish noise with mild high-pass tilt
float blue(vec2 uv, float t, float gsize){
    vec2 s = uv * (180.0 / gsize);
    float n1 = hash13(vec3(floor(s), t*0.37));
    float n2 = hash13(vec3(floor(s+vec2(13.7,7.9)), t*0.61));
    float n3 = hash13(vec3(floor(s+vec2(3.1,27.5)), t*0.19));
    float v = (n1 + 0.75*n2 + 0.5*n3) / 2.25;
    v = v*2.0 - 1.0;          // [-1, 1]
    // gentle high-pass so it doesn't act like blur bait
    return v * (0.85 + 0.15*(n2));
}

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec4 src = HOOKED_tex(uv);

    // frame time seed (many builds carry frame idx in z; else static)
    float t = (animate > 0.5) ? float(int(HOOKED_size.z)) : 0.0;

    float Y  = luma(src.rgb);

    // weight grain toward midtones (avoid deep blacks/whites)
    float mid = smoothstep(0.08, 0.92, Y);
    mid *= mix(1.0, smoothstep(0.2, 0.7, Y), midtone_bias);

    float g  = blue(uv, t, grain_size) * strength * mid;

    // luma-only component
    float gY = g;

    // small chroma component blended in
    vec3 gRGB = vec3(g);
    vec3 add  = mix(vec3(gY), gRGB, chroma);

    // apply (keep it ultra subtle)
    vec3 outc = src.rgb + add;
    return vec4(outc, src.a);
}

