// inserts/finalize_color.wgsl — ManimGL's INS_FINALIZE_COLOR, in WGSL: the
// same formula operation by operation (`reflect`, `exp`, `pow`, `mix`, `max`
// exist unchanged). Its three uniforms are `frame.light_position`,
// `frame.camera_position` and `mob.shading`. GLSL compares the vector to zero
// as one scalar; WGSL's `==` on vectors is component-wise, hence the
// `all(...)` (the easiest silent error in a translation).

fn add_light(color: vec4<f32>, point: vec3<f32>, unit_normal: vec3<f32>) -> vec4<f32> {
    if (all(mob.shading == vec3<f32>(0.0))) {
        return color;
    }
    let reflectiveness = mob.shading.x;
    let gloss = mob.shading.y;
    let shadow = mob.shading.z;
    var result = color;
    let to_camera = normalize(frame.camera_position - point);
    let to_light = normalize(frame.light_position - point);
    let light_to_normal = dot(to_light, unit_normal);
    var bright_factor = max(light_to_normal, 0.0) * reflectiveness;
    let light_reflection = reflect(-to_light, unit_normal);
    let light_to_cam = dot(light_reflection, to_camera);
    let shine = gloss * exp(-3.0 * pow(1.0 - light_to_cam, 2.0));
    bright_factor = bright_factor + shine;
    result = vec4<f32>(mix(result.rgb, vec3<f32>(1.0), bright_factor), result.a);
    if (light_to_normal < 0.0) {
        result = vec4<f32>(mix(result.rgb, vec3<f32>(0.0), max(-light_to_normal, 0.0) * shadow), result.a);
    }
    return result;
}

fn finalize_color(color: vec4<f32>, point: vec3<f32>, unit_normal: vec3<f32>) -> vec4<f32> {
    return add_light(color, point, unit_normal);
}
