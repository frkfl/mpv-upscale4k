// CAS pre-save: captures LUMA before AMD_CAS_RT modifies it.
// Place this immediately before AMD_CAS_RT in the shader chain.
// The blender (cas_luma_blend.glsl) uses CAS_ORIG to mix back.

//!HOOK LUMA
//!BIND HOOKED
//!SAVE CAS_ORIG
//!DESC [CAS wrapper] Save luma before sharpening

vec4 hook()
{
    return HOOKED_tex(HOOKED_pos);
}
