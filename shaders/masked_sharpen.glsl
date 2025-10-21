//!HOOK POSTKERNEL
//!BIND HOOKED
//!BIND PREV              // if this errors, switch to MAIN_PAST and rename below
//!DESC Masked, anti-halo, luma-only sharpen with motion gating
//!PARAM float strength = 0.28     // overall sharpen amount (0.20–0.35 typical)
//!PARAM float clamp_amt = 0.035   // max halo per-pixel (0.03–0.05 typical)
//!PARAM float edge_low = 0.03     // ignore very weak edges (0.02–0.05)
//!PARAM float edge_high = 0.25    // suppress very strong (likely ringing) (0.2–0.35)
//!PARAM float flat_protect = 0.7  // more = less sharpen on flats (0.6–0.85)
//!PARAM float motion_gate = 0.5   // 0=off, 1=strong gating on motion (0.3–0.7 useful)

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float luma(vec3 c){ return dot(c, LUMA); }

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = 1.0 / vec2(HOOKED_size.xy);

    vec3 c00 = HOOKED_tex(uv).rgb;
    vec3 cx1 = HOOKED_tex(uv + vec2( px.x, 0)).rgb;
    vec3 cx0 = HOOKED_tex(uv + vec2(-px.x, 0)).rgb;
    vec3 cy1 = HOOKED_tex(uv + vec2(0,  px.y)).rgb;
    vec3 cy0 = HOOKED_tex(uv + vec2(0, -px.y)).rgb;
    vec3 cxy1= HOOKED_tex(uv + vec2( px.x,  px.y)).rgb;
    vec3 cxy0= HOOKED_tex(uv + vec2(-px.x, -px.y)).rgb;

    float y  = luma(c00);
    float yx1= luma(cx1), yx0=luma(cx0), yy1=luma(cy1), yy0=luma(cy0);
    float yxy1=luma(cxy1), yxy0=luma(cxy0);

    // band-pass edge measure: Sobel magnitude (mid edges), suppress extremes later
    float gx = (yx1 - yx0) * 0.5 + (yxy1 - yxy0) * 0.25;
    float gy = (yy1 - yy0) * 0.5 + (yxy1 - yxy0) * 0.25;
    float edge = sqrt(gx*gx + gy*gy);

    // local high-pass (unsharp) – 5-tap separable approx
    float blur = (y*0.4 + (yx1+yx0+yy1+yy0)*0.15);
    float hi = y - blur;

    // anti-halo clamp: limit correction to clamp_amt and to a fraction of edge strength
    float corr = clamp(hi, -clamp_amt, clamp_amt);
    float band = smoothstep(edge_low, edge_high, edge) * (1.0 - smoothstep(edge_high, edge_high*2.0, edge));

    // flat protection (reduce gain where variance is low)
    float var = abs(y - ( (yx1+yx0+yy1+yy0)*0.25 ));
    float flat = 1.0 - smoothstep(0.0, 0.08, var);
    float protect = mix(1.0, flat, flat_protect);

    // optional motion gating using previous frame luma diff
    vec3 prev = PREV_tex(uv).rgb;
    float yprev = luma(prev);
    float motion = clamp(abs(y - yprev) * 4.0, 0.0, 1.0); // quick & dirty
    float gate = mix(1.0, 1.0 - motion, motion_gate);

    float gain = strength * band * protect * gate;
    float y_out = y + corr * gain;

    // recompose luma change into RGB (preserve chroma)
    float dy = y_out - y;
    vec3 out_rgb = c00 + dy;

    return vec4(out_rgb, 1.0);
}

