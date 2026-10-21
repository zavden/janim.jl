// surface.wgsl — Surface (the lit uv mesh) on WebGPU (ManimGL's surface
// vertex and fragment shaders). No geometry stage to replace: the mesh is
// drawn INDEXED (`draw_indexed`), the normal is recovered from
// `d_normal_point − point` as in ManimGL (Janim's normals are analytic, from
// the derivatives of uv_func — ManimGL's `grid_normal` is not adopted), and
// the light is applied PER VERTEX, because a Surface's colour is per
// vertex.

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl
// #INSERT finalize_color.wgsl

struct VertexIn {
    @location(0) point: vec3<f32>,
    @location(1) d_normal_point: vec3<f32>,
    @location(2) rgba: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    var out: VertexOut;
    out.position = project_point(in.point);
    let unit_normal = normalize(in.d_normal_point - in.point);
    out.color = finalize_color(in.rgba, in.point, unit_normal);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    return in.color;
}
