//!PARAM target
//!TYPE int
//!MINIMUM 0
//!MAXIMUM 6
0

//!PARAM strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.5
0.8

//!PARAM diffuse_adj
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.5
1.0

//!PARAM specular_adj
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.5
1.0

//!PARAM undertone_adj
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.5
1.0

//!PARAM reflectance_adj
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.5
1.0

//!HOOK MAIN
//!BIND HOOKED
//!DESC Universal skin tone perceptual correction (refined undertone)

// Helper functions
float luma(vec3 c){ return dot(c, vec3(0.2627,0.6780,0.0593)); }
vec3 rgb2yuv(vec3 c){ return mat3(0.2627,0.6780,0.0593, -0.1396,-0.3604,0.5, 0.5,-0.4598,-0.0402)*c; }
vec3 yuv2rgb(vec3 yuv){ return mat3(1.0,0.0,1.4746, 1.0,-0.1646,-0.5714, 1.0,1.8814,0.0)*yuv; }

// Refined undertone hue rotation: smooth, energy-preserving
vec3 undertone_pass(vec3 rgb, float hue, float shift, float s){
    vec3 yuv = rgb2yuv(rgb);
    float hue_ang = degrees(atan(yuv.z, yuv.y));
    float d = abs(atan(sin(radians(hue_ang - hue)), cos(radians(hue_ang - hue)))) * 180.0 / 3.14159265;
    float w = smoothstep(40.0, 0.0, d); // smoother falloff for SDR flattening
    float ang = radians(shift * w * s * 80.0);
    float cs = cos(ang), sn = sin(ang);
    vec2 rot = vec2(cs*yuv.y - sn*yuv.z, sn*yuv.y + cs*yuv.z);
    vec3 res = yuv2rgb(vec3(yuv.x, rot));
    return clamp(res, 0.0, 1.0);
}

// Diffuse pass – soft tone remapping
vec3 diffuse_pass(vec3 rgb, float s){
    float Y = luma(rgb);
    float adj = mix(1.0, pow(Y, 0.8), s*0.5);
    return mix(rgb, pow(rgb, vec3(adj)), s);
}

// Specular shaping – soften high luminance, restore volume
vec3 specular_pass(vec3 rgb, float s){
    float Y = luma(rgb);
    float k = smoothstep(0.6, 1.0, Y);
    vec3 soft = mix(rgb, sqrt(rgb), k*0.6);
    return mix(rgb, soft, s);
}

// Reflectance – lift shadows and adjust exposure curve
vec3 reflectance_pass(vec3 rgb, float lift, float gain, float s){
    float Y = luma(rgb);
    float Yc = Y + lift*(1.0 - smoothstep(0.1, 0.3, Y));
    Yc = pow(Yc, gain);
    float env_gate = smoothstep(0.05, 0.25, Y); 
    float local = mix(1.0, env_gate, 0.5*s); 
    float scale = mix(1.0, Yc / max(Y, 1e-6), s*local);
    return rgb * scale;
}

vec4 hook() {
    vec3 rgb = HOOKED_tex(HOOKED_pos).rgb;

    // Base coefficients for each target tone
    float diff_base=0.3, spec_base=0.3, tone_base=0.3, refl_base=0.3;
    float hue=38.0, shift=0.0, lift=0.0, gain=1.0;

    if (target==0){ // Porcelain / Fair-Neutral
        diff_base=0.45; spec_base=0.25; tone_base=0.25; refl_base=0.35;
        hue=30.0; shift=0.02; lift=0.02; gain=1.03;
    } else if (target==1){ // Light-Warm (Golden/Peach)
        diff_base=0.35; spec_base=0.35; tone_base=0.35; refl_base=0.35;
        hue=38.0; shift=0.03; lift=0.02; gain=1.05;
    } else if (target==2){ // Olive / Mediterranean
        diff_base=0.30; spec_base=0.30; tone_base=0.40; refl_base=0.30;
        hue=42.0; shift=-0.02; lift=0.03; gain=1.04;
    } else if (target==3){ // Tan / Light Brown
        diff_base=0.25; spec_base=0.35; tone_base=0.30; refl_base=0.40;
        hue=40.0; shift=0.00; lift=0.03; gain=1.08;
    } else if (target==4){ // Brown-Warm (Caramel / Bronze)
        diff_base=0.25; spec_base=0.30; tone_base=0.30; refl_base=0.45;
        hue=40.0; shift=0.02; lift=0.04; gain=1.06;
    } else if (target==5){ // Deep Brown / Ebony (Cool)
        diff_base=0.25; spec_base=0.25; tone_base=0.25; refl_base=0.50;
        hue=42.0; shift=-0.02; lift=0.05; gain=1.04;
    } else if (target==6){ // Deep Warm (Mahogany)
        diff_base=0.25; spec_base=0.25; tone_base=0.35; refl_base=0.45;
        hue=36.0; shift=0.03; lift=0.04; gain=1.02;
    }

    // Apply user adjustments
    float diff = diff_base * diffuse_adj;
    float spec = spec_base * specular_adj;
    float tone = tone_base * undertone_adj;
    float refl = refl_base * reflectance_adj;

    // Apply passes in perceptual order
    vec3 d = diffuse_pass(rgb, diff * strength);
    vec3 s = specular_pass(d, spec * strength);
    vec3 u = undertone_pass(s, hue, shift, tone * strength);
    vec3 f = reflectance_pass(u, lift, gain, refl * strength);

    return vec4(clamp(f, 0.0, 1.0), 1.0);
}
