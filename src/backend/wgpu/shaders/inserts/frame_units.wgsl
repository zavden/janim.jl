// inserts/frame_units.wgsl — ManimGL's INS_FRAME_UNITS, in WGSL. Its three
// uniforms live in the two blocks of uniforms.jl: `frame_scale` and `pixel_size` in the frame's (group 0),
// `is_fixed_in_frame` in the mobject's (group 1) — a shader that includes
// this insert declares both blocks first.

fn get_frame_unit_size() -> f32 {
    return mix(frame.frame_scale, 1.0, mob.is_fixed_in_frame);
}

fn get_pixel_unit_size() -> f32 {
    return frame.pixel_size * get_frame_unit_size() / frame.frame_scale;
}
