// present.wgsl — the preview's presentation pass: the frame held in
// `rv.target` onto the window's surface texture, with ONE triangle that
// covers the screen and a nearest sample at level 0.
//
// ManimGL's `present.wgsl`, literal: three vertices from `vertex_index`, no
// buffer and no index, and `uv = (0.5 + 0.5·x, 0.5 − 0.5·y)`. The target's
// row 0 is the TOP of the frame (WebGPU's texture rows run top to bottom) and
// NDC y = +1 is the top of the screen, so the image lands upright with no
// flip anywhere. At 1:1 (a window born at the
// render's size, which is every preview outside HiDPI) every pixel centre
// falls on its own texel and the surface receives the bytes of the frame;
// on a HiDPI framebuffer the triangle stretches.

@group(0) @binding(0) var tex: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;

struct PresentOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> PresentOut {
    // (−1, −1), (3, −1), (−1, 3): the part of the triangle inside the clip
    // volume is exactly the screen
    let x = f32(i32(i & 1u) * 4 - 1);
    let y = f32(i32(i & 2u) * 2 - 1);
    var out: PresentOut;
    out.position = vec4<f32>(x, y, 0.0, 1.0);
    out.uv = vec2<f32>(0.5 + 0.5 * x, 0.5 - 0.5 * y);
    return out;
}

@fragment
fn fs_main(in: PresentOut) -> @location(0) vec4<f32> {
    return textureSampleLevel(tex, samp, in.uv, 0.0);
}
