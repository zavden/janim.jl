// cover.wgsl — the second half of a VMobject's fill: the same triangles
// stencil.wgsl counted, drawn again with the colour, under the stencil test
// `NotEqual 0` — every sample the count marked is painted ONCE (the pipeline
// zeroes the count as it passes, and on a depth fail too, so nothing is left
// behind for the next mobject) with the fill colour of the corner, lit by
// `finalize_color`, straight alpha, through the pass's
// SrcAlpha/OneMinusSrcAlpha blend. The interior reads its own byte.
//
// The depth is the triangle's own, per fragment, tested and written by the
// pipeline when the mobject depth-tests (`Less`, with the slope bias in the
// pipeline state) and ignored otherwise. A VMobject that overlaps itself in
// 3D paints the z of the first triangle that reaches the sample (the fill's
// colour is the same either way).
//
// The vertex stage mirrors stencil.wgsl's, culls included (a curve whose
// three alphas are zero is dropped whole, as ManimGL's geometry stage drops
// it; stencil.wgsl drops it too, so the count and the paint agree). No
// per-fragment `discard`: a discarded fragment would leave its count
// standing. A fragment whose interpolated alpha is exactly zero blends
// nothing and still writes its depth. The thin-triangle cull
// (inserts/thin_triangle.wgsl) is applied in the vertex stage, the same test
// stencil.wgsl applies, after `pts` is chosen.

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl
// #INSERT thin_triangle.wgsl
// #INSERT finalize_color.wgsl

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
    @location(0) color: vec4<f32>,
};

fn collapsed() -> VertexOut {
    var out: VertexOut;
    out.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    out.color = vec4<f32>(0.0);
    return out;
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    if (all(in.p0 == in.p1)) {
        return collapsed();
    }
    if (all(vec3<f32>(in.c0.a, in.c1.a, in.c2.a) == vec3<f32>(0.0))) {
        return collapsed();
    }
    let tri = in.vertex_index / 3u;
    let corner = in.vertex_index % 3u;
    var pts: array<vec3<f32>, 3>;
    var cols: array<vec4<f32>, 3>;
    if (tri == 0u) {
        // the fan: (base_point, p0, p2) with the colours (c1, c0, c2)
        pts = array<vec3<f32>, 3>(in.base_point, in.p0, in.p2);
        cols = array<vec4<f32>, 3>(in.c1, in.c0, in.c2);
    } else {
        pts = array<vec3<f32>, 3>(in.p0, in.p1, in.p2);
        cols = array<vec4<f32>, 3>(in.c0, in.c1, in.c2);
    }
    if (is_thin(pts)) {                // the thin-triangle cull, in window pixels
        return collapsed();
    }
    var out: VertexOut;
    out.color = finalize_color(cols[corner], pts[corner], in.unit_normal);
    out.position = project_point(pts[corner]);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    return in.color;
}
