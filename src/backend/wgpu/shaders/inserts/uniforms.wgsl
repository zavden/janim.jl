// inserts/uniforms.wgsl — the two uniform blocks every shader declares. Their
// byte layout is mirrored on the Julia side by the two isbits structs of
// uniforms.jl (112 and 64 bytes): the two sides must agree field by field.
//
//   group 0 · the FRAME: written once per pass (camera_uniforms' six camera
//             fields).
//   group 1 · the MOBJECT: one block per RUN in a dynamic-offset arena; the
//             fields every pass reads — the stroke's, the fill's gradient,
//             the dots' and the textures' — so the zoo shares one layout and
//             one bind group.

struct FrameUniforms {
    view: mat4x4<f32>,
    frame_rescale_factors: vec3<f32>,
    frame_scale: f32,
    camera_position: vec3<f32>,
    pixel_size: f32,
    light_position: vec3<f32>,
    _pad: f32,
};

struct MobjectUniforms {
    shading: vec3<f32>,
    is_fixed_in_frame: f32,
    anti_alias_width: f32,
    joint_type: f32,
    flat_stroke: f32,
    stroke_width_in_scene_units: f32,
    grad_focus: vec3<f32>,
    grad_kind: f32,
    spread_mode: f32,
    grad_opacity: f32,
    glow_factor: f32,
    opacity: f32,
};

@group(0) @binding(0) var<uniform> frame: FrameUniforms;
@group(1) @binding(0) var<uniform> mob: MobjectUniforms;
