//!HOOK POSTKERNEL
//!BIND HOOKED
//!DESC Micro-Contrast (local tone separation)
//!PARAM float radius = 1.0      // sample radius, 0.5–2.0 typical
//!PARAM float amount = 0.12     // overall effect strength
//!PARAM float threshold = 0.02  // suppress tiny noise changes
//!PARAM float gamma_in = 2.20
//!PARAM float gamma_out = 2.20

float luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 toLin(vec3 c, float g){ return pow(max(c,0.0), vec3(g>0.0? 1.0/g : 1.0)); }
vec3 toGam(vec3 c, float g){ return pow(max(c,0.0), vec3(g>0.0? g : 1.0)); }

vec4 hook(){
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / HOOKED_size.xy;
    float r = radius;

    // current pixel in linear light
    vec3 c = toLin(HOOKED_tex(uv).rgb, gamma_in);

    // 3x3 local blur
    vec3 n  = toLin(HOOKED_tex(uv + vec2(0.0, -px.y*r)).rgb, gamma_in);
    vec3 s  = toLin(HOOKED_tex(uv + vec2(0.0,  px.y*r)).rgb, gamma_in);
    vec3 e  = toLin(HOOKED_tex(uv + vec2( px.x*r, 0.0)).rgb, gamma_in);
    vec3 w  = toLin(HOOKED_tex(uv + vec2(-px.x*r, 0.0)).rgb, gamma_in);
    vec3 ne = toLin(HOOKED_tex(uv + vec2( px.x*r,-px.y*r)).rgb, gamma_in);
    vec3 nw = toLin(HOOKED_tex(uv + vec2(-px.x*r,-px.y*r)).rgb, gamma_in);
    vec3 se = toLin(HOOKED_tex(uv + vec2( px.x*r, px.y*r)).rgb, gamma_in);
    vec3 sw = toLin(HOOKED_tex(uv + vec2(-px.x*r, px.y*r)).rgb, gamma_in);

    vec3 blur = (c+n+s+e+w+ne+nw+se+sw) / 9.0;

    // tone-local contrast term
    vec3 diff = c - blur;
    float gate = smoothstep(threshold, 3.0*threshold, abs(luma(diff)));
    vec3 boosted = c + diff * (amount * gate);

    // return re-gammaed
    return vec4(toGam(boosted, gamma_out), 1.0);
}
