// textured_surface.wgsl — TexturedSurface on WebGPU (ManimGL's textured
// surface shaders): the uv mesh, drawn indexed, with the texel as its colour
// and the light applied PER FRAGMENT (ManimGL's textured_surface lights the
// texel; Surface lights per vertex because its colour IS per vertex — the
// asymmetry is ManimGL's and is kept).

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl
// #INSERT finalize_color.wgsl

@group(2) @binding(0) var image: texture_2d<f32>;
@group(2) @binding(1) var image_sampler: sampler;

struct VertexIn {
    @location(0) point: vec3<f32>,
    @location(1) d_normal_point: vec3<f32>,
    @location(2) im_coords: vec2<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) point: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) im_coords: vec2<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    var out: VertexOut;
    out.position = project_point(in.point);
    out.point = in.point;
    out.normal = normalize(in.d_normal_point - in.point);
    out.im_coords = in.im_coords;
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    var c = textureSample(image, image_sampler, in.im_coords);
    c.a = c.a * mob.opacity;
    if (c.a <= 0.0) {
        discard;
    }
    return finalize_color(c, in.point, normalize(in.normal));
}
