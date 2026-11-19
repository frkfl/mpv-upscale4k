// CAS luma blend: mixes the CAS-sharpened LUMA with the original LUMA.
// Place this immediately after AMD_CAS_RT in the shader chain.
//
// AMD_CAS_RT in this port hooks LUMA only — chroma is never touched by CAS,
// so there is no chroma parameter to control. Only luma needs a blend weight.
//
// cas_luma_blend = 0.0  → bypass (original luma, CAS has no effect)
// cas_luma_blend = 1.0  → full CAS output (default if this shader is absent)

//!PARAM cas_luma_blend
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!HOOK LUMA
//!BIND HOOKED
//!BIND CAS_ORIG
//!DESC [CAS wrapper] Blend sharpened luma

vec4 hook()
{
    float sharpened = HOOKED_tex(HOOKED_pos).r;
    float original  = CAS_ORIG_tex(HOOKED_pos).r;
    return vec4(mix(original, sharpened, cas_luma_blend), 0.0, 0.0, 1.0);
}
