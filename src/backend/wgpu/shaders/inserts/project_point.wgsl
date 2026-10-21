// inserts/project_point.wgsl — ManimGL's position emit (INS_EMIT_GL_POSITION),
// in WGSL. One line differs, and it is the API's, not Janim's: ManimGL
// writes clip z = −0.1·z_s with w = 1 − z_s, whose window depth is
// 0.5·(1 − 1.1·z_s)/(1 − z_s); WebGPU's depth is z/w with z in [0, 1], so
// the clip z written here is 0.5·(1 − 1.1·z_s) over the same w — the same
// function of the point, algebraically, not bit for bit (the reassociation
// moves the last bit of z). x, y and w are untouched, and there is no y
// flip: WebGPU's framebuffer origin is the top-left, so the convention here
// is `camera_uniforms(cam; flip_y = false)`. Janim has no clip planes, so
// nothing of ManimGL's `gl_ClipDistance` is missing.

fn project_point(point: vec3<f32>) -> vec4<f32> {
    var result = vec4<f32>(point, 1.0);
    result = mix(frame.view * result, result, mob.is_fixed_in_frame);
    let scaled = result.xyz * frame.frame_rescale_factors;
    return vec4<f32>(scaled.xy, 0.5 * (1.0 - 1.1 * scaled.z), 1.0 - scaled.z);
}
