// inserts/quad_common.wgsl — what every quad pass of the compositor shares:
// the one bind group, the parameter block, the vertex and the two samplers'
// reads.
//
//   group 0 · binding 0  tex_a   the pass's first texture (Tex, Backdrop, Layer, A, Src…)
//             binding 1  tex_b   its second (Layer, Mask, B, Blurred) — tex_a again when unused
//             binding 2  samp    nearest + repeat for every pass but the window's, which
//                                binds the linear + repeat one (repeat addressing,
//                                because BLUR, EDGE and CHROMA sample outside [0, 1]:
//                                the border of everything blurred depends on it)
//             binding 3  P       the parameters, one block per pass in a ring with a
//                                dynamic offset (uniforms.jl's ParamArena): four generic
//                                floats, four more, four ints and the blur's 64 weights
//                                as sixteen vec4 (an `array<f32, 64>` is illegal in a
//                                uniform: stride 16), read as `P.w[i >> 2][i & 3]`
//
// The vertex is a strip of four corners (0,0) (0,1) (1,0) (1,1) from
// `vertex_index`, `uv = tc`, and the flip — ONCE, here — on the GEOMETRY:
// `position.y = −(2·tc.y − 1)`. WebGPU's framebuffer row 0 is the top and so
// is its texel row 0; without the flip every pass would turn the picture over
// and a chain of an even number of passes would hide it. Negating y lands the
// corner tc = (0,0) on memory row 0, so memory row r of the destination reads
// memory row r of the source and `@builtin(position).y` is `r + 0.5` on both
// sides — the CRT's scanlines, the VHS's rows and the noise's pixel land on
// memory rows. And it is the geometry, not the uv, that carries the flip for
// a measured reason: flipping `uv.y = 1 − tc.y` in the vertex changes the
// interpolation's rounding and the fragment's uv differs from the unflipped
// one in half the pixels by up to 1 697 ulp — enough to pick the neighbouring
// texel wherever an effect samples near a texel boundary (Glitch's bands,
// Pixelate's cells) — while the same triangles on the same rows, `uv = tc`,
// interpolate to the SAME bits in every pixel.
// `textureSampleLevel(…, 0.0)` everywhere: no surface has mipmaps, and CRT
// and VHS return in non-uniform control flow before they sample.

struct QuadParams {
    f0: vec4<f32>,
    f1: vec4<f32>,
    i0: vec4<i32>,
    w: array<vec4<f32>, 16>,
};

@group(0) @binding(0) var tex_a: texture_2d<f32>;
@group(0) @binding(1) var tex_b: texture_2d<f32>;
@group(0) @binding(2) var samp: sampler;
@group(0) @binding(3) var<uniform> P: QuadParams;

struct QuadOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

// the strip's corner i: (0,0), (0,1), (1,0), (1,1)
fn quad_corner(i: u32) -> vec2<f32> {
    return vec2<f32>(f32(i >> 1u), f32(i & 1u));
}

@vertex
fn vs_quad(@builtin(vertex_index) vertex_index: u32) -> QuadOut {
    let tc = quad_corner(vertex_index);
    var out: QuadOut;
    out.position = vec4<f32>(2.0 * tc.x - 1.0, -(2.0 * tc.y - 1.0), 0.0, 1.0);
    out.uv = tc;
    return out;
}

fn sample_a(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(tex_a, samp, uv, 0.0);
}

fn sample_b(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(tex_b, samp, uv, 0.0);
}
