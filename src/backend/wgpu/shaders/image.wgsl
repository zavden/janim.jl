// image.wgsl — ImageMobject on WebGPU (ManimGL's textured-quad vertex and
// fragment shaders). The four corners (UL, DL, UR, DR) are drawn as a
// triangle strip, and the texture is sampled at the same uv: the pixel array
// is 4×w×h with row 1 on top, which is the layout `wgpuQueueWriteTexture`
// takes with v = 0 at the top — same bytes, same uv, no flip on the texture
// side.

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl

@group(2) @binding(0) var image: texture_2d<f32>;
@group(2) @binding(1) var image_sampler: sampler;

struct VertexIn {
    @location(0) point: vec3<f32>,
    @location(1) im_coords: vec2<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) im_coords: vec2<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    var out: VertexOut;
    out.im_coords = in.im_coords;
    out.position = project_point(in.point);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    var color = textureSample(image, image_sampler, in.im_coords);
    color.a = color.a * mob.opacity;
    if (color.a <= 0.0) {
        discard;
    }
    return color;
}
