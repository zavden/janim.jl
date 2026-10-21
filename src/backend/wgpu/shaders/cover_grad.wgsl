// cover_grad.wgsl — cover.wgsl for a gradient fill: the same triangles under
// the same stencil test, the colour from the ramp texture at a t computed
// per PIXEL out of the affine per-point uv. Two slots more than cover.wgsl,
// the gradient run's own buffers: `grad_uv` ×3 and the fan base's uv,
// `grad_uv_base`. No zero-alpha cull in the vertex stage: the RAMP decides
// visibility per pixel (and stencil.wgsl's gradient variant keeps the same
// curves). `mod(t, 2.0)` is written `t − 2·floor(t/2)` here.
// The thin-triangle cull (inserts/thin_triangle.wgsl) is as in cover.wgsl,
// after `pts` is chosen.

// #INSERT uniforms.wgsl
// #INSERT project_point.wgsl
// #INSERT thin_triangle.wgsl
// #INSERT finalize_color.wgsl

@group(2) @binding(0) var ramp: texture_2d<f32>;
@group(2) @binding(1) var ramp_sampler: sampler;

const RAMP_RESOLUTION: f32 = 1024.0;

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
    @location(8) guv0: vec2<f32>,
    @location(9) guv1: vec2<f32>,
    @location(10) guv2: vec2<f32>,
    @location(11) guv_base: vec2<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) guv: vec2<f32>,
    @location(1) g_point: vec3<f32>,
    @location(2) g_normal: vec3<f32>,
};

fn collapsed() -> VertexOut {
    var out: VertexOut;
    out.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    out.guv = vec2<f32>(0.0);
    out.g_point = vec3<f32>(0.0);
    out.g_normal = vec3<f32>(0.0, 0.0, 1.0);
    return out;
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    if (all(in.p0 == in.p1)) {
        return collapsed();
    }
    let tri = in.vertex_index / 3u;
    let corner = in.vertex_index % 3u;
    var pts: array<vec3<f32>, 3>;
    var uvs: array<vec2<f32>, 3>;
    if (tri == 0u) {
        pts = array<vec3<f32>, 3>(in.base_point, in.p0, in.p2);
        uvs = array<vec2<f32>, 3>(in.guv_base, in.guv0, in.guv2);
    } else {
        pts = array<vec3<f32>, 3>(in.p0, in.p1, in.p2);
        uvs = array<vec2<f32>, 3>(in.guv0, in.guv1, in.guv2);
    }
    if (is_thin(pts)) {                // the thin-triangle cull, in window pixels
        return collapsed();
    }
    var out: VertexOut;
    out.guv = uvs[corner];
    out.g_point = pts[corner];
    out.g_normal = in.unit_normal;
    out.position = project_point(pts[corner]);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    var t: f32;
    if (mob.grad_kind < 0.5) {
        t = in.guv.x;
    } else {
        let f = mob.grad_focus.xy;
        let ff = dot(f, f);
        if (ff < 1e-12) {
            t = length(in.guv);
        } else {
            // SVG focal radial: p lies on the circle centred f + t(c − f)
            // with radius t·r. uv space has c = 0, r = 1; the import clamps
            // the focus inside, so the quadratic has ONE positive root.
            let d = in.guv - f;
            let A = ff - 1.0;
            let B = dot(d, f);
            let C = dot(d, d);
            t = (-B - sqrt(max(B * B - A * C, 0.0))) / A;
        }
    }
    if (mob.spread_mode < 0.5) {
        t = clamp(t, 0.0, 1.0);
    } else if (mob.spread_mode < 1.5) {
        t = 1.0 - abs((t - 2.0 * floor(t / 2.0)) - 1.0);
    } else {
        t = fract(t);
    }
    let x = mix(0.5 / RAMP_RESOLUTION, 1.0 - 0.5 / RAMP_RESOLUTION, t);
    var ramp_color = textureSample(ramp, ramp_sampler, vec2<f32>(x, 0.5));
    ramp_color.a = ramp_color.a * mob.grad_opacity;      // exact identity when nobody is fading
    return finalize_color(ramp_color, in.g_point, normalize(in.g_normal));
}
