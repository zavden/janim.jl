// stencil.wgsl — the first half of a VMobject's fill: the triangles of its
// curves counted into the STENCIL buffer, nonzero rule, as ManimGL does.
// Instanced triples over the vertex arena — `point` ×3, `fill_rgba` ×3 for
// the culls, and of `base_normal` the fan base at element 0 and the unit
// normal at element 1 — the draw `draw(6, n_curves, 0, first_instance)`:
// vertex_index / 3 picks the fan (base_point, p0, p2) or the Loop-Blinn
// triangle (p0, p1, p2), vertex_index % 3 the corner. No colour is written
// (the pipeline's colour mask is 0): the pipeline's stencil state does the
// counting — IncrementWrap on a front face, DecrementWrap on a back face, as
// the rasteriser sees them — so no orientation (the determinant with the
// mobject's normal) is needed: a shape seen from behind counts −1 and its
// hole +1, and −1 ≠ 0 fills where 0 leaves the hole. cover.wgsl then paints,
// once per sample, wherever the count is not zero, and zeroes it.
//
// The curve. Loop-Blinn discards where y − x² < 0 in the triangle's uv.
// Under MSAA a `discard` is per FRAGMENT — the four samples of the pixel go
// together — and the curved edge would stay aliased at any sample count
// (a probe arc showed 72 partial pixels, the same as at one sample). So the
// fragment writes
// `@builtin(sample_mask)` instead: uv is affine across the pixel (exactly
// so at w = 1), its derivatives place it at each of the SAMPLES standard
// positions, and the quadratic is evaluated there. Measured byte-identical
// to `@interpolate(perspective, sample)` — which asks the rasteriser for
// the true per-sample uv — on RADV and on lavapipe (their 4× positions are
// the standard ones), at 1.5× the cost of the per-pixel test where the
// per-sample stage costs 8.7×. The fan triangles cover all their samples.
// `SAMPLES` and `CULL_ALPHA` are substituted by pipelines.jl: the module is
// compiled per sample count, and the gradient's variant keeps the curves
// whose three alphas are zero (the ramp decides, as in cover_grad.wgsl).
// A triangle thinner than `THIN_PX` window pixels — the Loop-Blinn
// triangle of a straight side after an f32 transform — is culled by
// `is_thin` (inserts/thin_triangle.wgsl), identically in the three
// shaders of the fill, so the count and the paint keep agreeing.

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl
// #INSERT thin_triangle.wgsl

const SAMPLES: u32 = 4u;
const CULL_ALPHA: f32 = 1.0;

const SIMPLE_QUADRATIC: array<vec2<f32>, 3> = array<vec2<f32>, 3>(
    vec2<f32>(0.0, 0.0),
    vec2<f32>(0.5, 0.0),
    vec2<f32>(1.0, 1.0),
);

// the standard sample positions of a 4× pattern, relative to the pixel centre
const OFFSET_X: array<f32, 4> = array<f32, 4>(-0.125, 0.375, -0.375, 0.125);
const OFFSET_Y: array<f32, 4> = array<f32, 4>(-0.375, -0.125, 0.125, 0.375);

struct VertexIn {
    @builtin(vertex_index) vertex_index: u32,
    @location(0) p0: vec3<f32>,
    @location(1) p1: vec3<f32>,
    @location(2) p2: vec3<f32>,
    @location(3) c0: vec4<f32>,
    @location(4) c1: vec4<f32>,
    @location(5) c2: vec4<f32>,
    @location(6) base_point: vec3<f32>,
    @location(7) unit_normal: vec3<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) fill_all: f32,
};

struct FragOut {
    @location(0) color: vec4<f32>,
    @builtin(sample_mask) mask: u32,
};

fn collapsed() -> VertexOut {
    var out: VertexOut;
    out.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    out.uv = vec2<f32>(0.0);
    out.fill_all = 1.0;
    return out;
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    // ManimGL's two geometry-stage culls, on the whole curve (the alpha
    // one is off for a gradient run)
    if (all(in.p0 == in.p1)) {
        return collapsed();
    }
    if (CULL_ALPHA > 0.5 && all(vec3<f32>(in.c0.a, in.c1.a, in.c2.a) == vec3<f32>(0.0))) {
        return collapsed();
    }
    let tri = in.vertex_index / 3u;
    let corner = in.vertex_index % 3u;
    var pts: array<vec3<f32>, 3>;
    var fill_all: f32;
    if (tri == 0u) {
        pts = array<vec3<f32>, 3>(in.base_point, in.p0, in.p2);
        fill_all = 1.0;
    } else {
        pts = array<vec3<f32>, 3>(in.p0, in.p1, in.p2);
        fill_all = 0.0;
    }
    if (is_thin(pts)) {                // the thin-triangle cull, in window pixels
        return collapsed();
    }
    var quad = SIMPLE_QUADRATIC;
    var out: VertexOut;
    out.fill_all = fill_all;
    out.uv = quad[corner];
    out.position = project_point(pts[corner]);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> FragOut {
    var out: FragOut;
    out.color = vec4<f32>(0.0);
    if (in.fill_all != 0.0) {
        out.mask = 0xffffffffu;
        return out;
    }
    var mask: u32 = 0u;
    if (SAMPLES == 1u) {
        if (in.uv.y - in.uv.x * in.uv.x >= 0.0) {
            mask = 1u;
        }
    } else {
        let dx = dpdx(in.uv);
        let dy = dpdy(in.uv);
        var ox = OFFSET_X;
        var oy = OFFSET_Y;
        for (var s: u32 = 0u; s < SAMPLES; s = s + 1u) {
            let uv = in.uv + ox[s] * dx + oy[s] * dy;
            if (uv.y - uv.x * uv.x >= 0.0) {
                mask = mask | (1u << s);
            }
        }
    }
    if (mask == 0u) {
        discard;
    }
    out.mask = mask;
    return out;
}
