// true_dot.wgsl — DotCloud / TrueDot / GlowDots on WebGPU (ManimGL's
// true_dot shaders) as one vertex stage and one fragment stage. ManimGL
// expands each point into a camera-facing quad in a geometry stage; here
// every point is an INSTANCE (three vertex buffers stepped per instance:
// point, radius, rgba) drawn as six vertices, and the corner table is the strip's two triangles
// — (−1,−1),(−1,1),(1,−1) and (1,−1),(−1,1),(1,1) — literally. The disc, the
// glow, the fake sphere (`make_3d!`) and the rim are ManimGL's formulas; the one
// rewrite is the rim's reversed `smoothstep`, its exact mirror.

// #INSERT uniforms.wgsl
// #INSERT frame_units.wgsl
// #INSERT project_point.wgsl
// #INSERT finalize_color.wgsl

const CORNERS: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, -1.0),
    vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, 1.0),
);

struct VertexIn {
    @builtin(vertex_index) vertex_index: u32,
    @location(0) point: vec3<f32>,
    @location(1) radius: f32,
    @location(2) rgba: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) scaled_aaw: f32,
    @location(2) point: vec3<f32>,
    @location(3) to_cam: vec3<f32>,
    @location(4) center: vec3<f32>,
    @location(5) radius: f32,
    @location(6) uv_coords: vec2<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    var corners = CORNERS;
    let corner = corners[in.vertex_index % 6u];
    var out: VertexOut;
    out.color = in.rgba;
    out.radius = in.radius;
    out.center = in.point;
    out.scaled_aaw = (mob.anti_alias_width * get_pixel_unit_size()) / in.radius;

    let to_cam = normalize(frame.camera_position - in.point);
    out.to_cam = to_cam;
    let right = in.radius * normalize(cross(vec3<f32>(0.0, 1.0, 1.0), to_cam));
    let up = in.radius * normalize(cross(to_cam, right));

    let point = in.point + corner.x * right + corner.y * up;
    out.point = point;
    out.uv_coords = corner;
    out.position = project_point(point);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let r = length(in.uv_coords.xy);
    if (r > 1.0) {
        discard;
    }

    var frag_color = in.color;

    if (mob.glow_factor > 0.0) {
        frag_color.a = frag_color.a * pow(1.0 - r, mob.glow_factor);
    }

    if (any(mob.shading != vec3<f32>(0.0))) {
        let point_3d = in.point + in.radius * sqrt(1.0 - r * r) * in.to_cam;
        let normal = normalize(point_3d - in.center);
        frag_color = finalize_color(frag_color, point_3d, normal);
    }

    // ManimGL: smoothstep(1.0, 1.0 - scaled_aaw, r) — reversed; the exact mirror.
    frag_color.a = frag_color.a * (1.0 - smoothstep(1.0 - in.scaled_aaw, 1.0, r));
    return frag_color;
}
