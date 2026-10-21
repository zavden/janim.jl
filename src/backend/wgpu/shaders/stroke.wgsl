// stroke.wgsl — the stroke of a VMobject, on WebGPU: ManimGL's stroke vertex,
// geometry and fragment shaders as ONE vertex stage and one fragment stage,
// because WebGPU has no geometry shaders.
//
// How the geometry stage became a vertex stage. ManimGL receives each
// expanded triple (p0, p1, p2) as a triangle, walks the curve in n_steps
// points and emits a strip of 2·n_steps vertices. Here the same triples
// arrive by INSTANCING: the five SoA arrays `expanded_data` already produces are
// bound as five vertex buffers stepped per instance with three attributes
// each (offsets 0, 1 and 2 elements), so instance i sees the triple i whole
// and the runs, mirrors and range uploads need no change. The draw is `draw(6·(S − 1), n_curves)` with S the
// largest n_steps of the run, computed on the CPU from the same formula
// (records.jl) plus one step of margin: vertex_index / 6 is the segment,
// vertex_index % 6 the corner of the two triangles that make it, and the
// corner table is ManimGL's strip cut into triangles — (v0,v1,v2),
// (v2,v1,v3) — literally. A vertex past this curve's n_steps − 1 collapses
// to (0,0,0,1), a degenerate triangle no rasteriser draws. Every shared
// vertex is computed twice from the same inputs, so the ribbon has no
// cracks.
//
// The body is ManimGL's, line for line, with three deliberate divergences
// (the grazing-tangent return, the guard re-applied on the projected pair,
// the ±4 clamp of the shift) and the discard at alpha 0.8 on the depth
// prepass, which is what `Z_PASS` selects: the source is compiled twice,
// with this constant substituted (pipelines.jl), as ManimGL compiles its
// fill border. What is NOT ManimGL's, and moves bytes on purpose, is written
// where it happens: the two reversed `smoothstep`s (the AA one of the
// fragment and the miter blend of `step_to_corner`), which WGSL leaves
// undefined and here are their exact algebraic mirrors, 1 − smoothstep.

// #INSERT uniforms.wgsl
// #INSERT frame_units.wgsl
// #INSERT project_point.wgsl
// #INSERT finalize_color.wgsl

const Z_PASS: f32 = 0.0;
// On the prepass, the pixel a ribbon's centre line crosses writes z too: the
// fragment whose centre lies within Z_CORE pixels of the curve. Substituted
// like Z_PASS (pipelines.jl, `_STROKE_Z_CORE`); 0 is the alpha rule alone.
const Z_CORE: f32 = 0.5;

const NO_JOINT: i32 = 0;
const AUTO_JOINT: i32 = 1;
const BEVEL_JOINT: i32 = 2;
const MITER_JOINT: i32 = 3;
const COS_THRESHOLD: f32 = 0.999;
const POLYLINE_FACTOR: f32 = 100.0;
const MAX_STEPS: i32 = 32;
const MITER_COS_ANGLE_THRESHOLD: f32 = -0.8;
const STROKE_WIDTH_CONVERSION: f32 = 0.01;

// ManimGL's triangle strip, as the two triangles of each segment: (v0, v1, v2)
// and (v2, v1, v3), with v_{2i} = (i, −1) and v_{2i+1} = (i, +1).
const CORNERS: array<vec2<i32>, 6> = array<vec2<i32>, 6>(
    vec2<i32>(0, -1), vec2<i32>(0, 1), vec2<i32>(1, -1),
    vec2<i32>(1, -1), vec2<i32>(0, 1), vec2<i32>(1, 1),
);

struct VertexIn {
    @builtin(vertex_index) vertex_index: u32,
    @location(0) p0: vec3<f32>,
    @location(1) p1: vec3<f32>,
    @location(2) p2: vec3<f32>,
    @location(3) rgba0: vec4<f32>,
    @location(4) rgba1: vec4<f32>,
    @location(5) rgba2: vec4<f32>,
    @location(6) width0: f32,
    @location(7) width1: f32,
    @location(8) width2: f32,
    @location(9) joint0: f32,
    @location(10) joint1: f32,
    @location(11) joint2: f32,
    // the CENTRAL element of `base_normal`: the mobject's unit normal (the
    // odd elements carry the fill's fan base — ManimGL's geometry stage reads
    // only v_unit_normal[1] for the same reason)
    @location(12) unit_normal: vec3<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) dist_to_aaw: f32,
    @location(2) half_width_to_aaw: f32,
};

fn point_on_quadratic(t: f32, c0: vec3<f32>, c1: vec3<f32>, c2: vec3<f32>) -> vec3<f32> {
    return c0 + c1 * t + c2 * t * t;
}

fn tangent_on_quadratic(t: f32, c1: vec3<f32>, c2: vec3<f32>) -> vec3<f32> {
    return c1 + 2.0 * c2 * t;
}

fn project(vect: vec3<f32>, unit_normal: vec3<f32>) -> vec3<f32> {
    return vect - dot(vect, unit_normal) * unit_normal;
}

fn rotate_vector(vect: vec3<f32>, unit_normal: vec3<f32>, angle: f32) -> vec3<f32> {
    let perp = cross(unit_normal, vect);
    return cos(angle) * vect + sin(angle) * perp;
}

fn step_to_corner(point: vec3<f32>, tangent: vec3<f32>, unit_normal: vec3<f32>,
                  joint_angle: f32, inside_curve: bool, draw_flat: bool,
                  center_normal: vec3<f32>) -> vec3<f32> {
    var unit_tan: vec3<f32>;
    if (draw_flat) {
        unit_tan = normalize(tangent);
    } else {
        unit_tan = normalize(project(tangent, unit_normal));
    }
    var step = normalize(cross(unit_normal, unit_tan));

    if (joint_angle != 0.0) {
        let alignment = abs(dot(normalize(tangent), unit_normal));
        let alignment_threshold = 0.97;
        if (alignment > alignment_threshold) {
            // The tangent is nearly parallel to the view ray — the
            // joint math degenerates here. Keep the base perpendicular and
            // skip the miter entirely.
            return step;
        }
    }

    if (inside_curve || i32(mob.joint_type) == NO_JOINT) {
        return step;
    }

    var cos_angle = cos(joint_angle);
    var sin_angle = sin(joint_angle);

    if (abs(cos_angle) > COS_THRESHOLD) {
        return step;
    }

    if (!draw_flat) {
        step = normalize(cross(unit_normal, unit_tan));
        var adj_tan = rotate_vector(tangent, center_normal, joint_angle);
        adj_tan = project(adj_tan, unit_normal);
        cos_angle = dot(unit_tan, normalize(adj_tan));
        sin_angle = sqrt(1.0 - cos_angle * cos_angle) * sign(joint_angle) * sign(dot(unit_normal, center_normal));
        // re-apply the guard on the recomputed pair.
        if (abs(cos_angle) > COS_THRESHOLD) {
            return step;
        }
    }

    var miter_factor: f32;
    let joint_type = i32(mob.joint_type);
    if (joint_type == BEVEL_JOINT) {
        miter_factor = 0.0;
    } else if (joint_type == MITER_JOINT) {
        miter_factor = 1.0;
    } else {
        let mcat1 = MITER_COS_ANGLE_THRESHOLD;
        let mcat2 = mix(mcat1, -1.0, 0.5);
        // ManimGL: smoothstep(mcat1, mcat2, cos_angle), with mcat1 > mcat2 — the
        // reversed form WGSL leaves undefined; its exact mirror instead.
        miter_factor = 1.0 - smoothstep(mcat2, mcat1, cos_angle);
    }

    // clamp instead of trusting sin_angle to stay sane.
    let shift = clamp((cos_angle + mix(-1.0, 1.0, miter_factor)) / sin_angle, -4.0, 4.0);
    return step + shift * unit_tan;
}

fn collapsed() -> VertexOut {
    var out: VertexOut;
    out.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    out.color = vec4<f32>(0.0);
    out.dist_to_aaw = 0.0;
    out.half_width_to_aaw = 0.0;
    return out;
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    // ManimGL's vertex stage: the width in frame units, per point
    let stroke_width_factor = STROKE_WIDTH_CONVERSION * mix(
        get_frame_unit_size(), 1.0, mob.stroke_width_in_scene_units
    );
    let sw0 = stroke_width_factor * in.width0;
    let sw1 = stroke_width_factor * in.width1;
    let sw2 = stroke_width_factor * in.width2;

    // the three guards of ManimGL's geometry stage, on the whole curve
    if (all(in.p0 == in.p1)) {
        return collapsed();
    }
    if (all(vec3<f32>(sw0, sw1, sw2) == vec3<f32>(0.0))) {
        return collapsed();
    }
    if (all(vec3<f32>(in.rgba0.a, in.rgba1.a, in.rgba2.a) == vec3<f32>(0.0))) {
        return collapsed();
    }

    let draw_flat = (mob.flat_stroke != 0.0) || (mob.is_fixed_in_frame != 0.0);

    let c0 = in.p0;
    let c1 = 2.0 * (in.p1 - in.p0);
    let c2 = in.p0 - 2.0 * in.p1 + in.p2;

    let area = 0.5 * length(cross(in.p1 - in.p0, in.p2 - in.p0));
    let count = i32(round(POLYLINE_FACTOR * sqrt(area) / get_frame_unit_size()));
    let n_steps = min(2 + count, MAX_STEPS);

    // which point of the polyline this vertex is: the segment and the
    // corner, from the vertex index; past the curve's own budget, nothing
    var corners = CORNERS;
    let segment = i32(in.vertex_index / 6u);
    let corner = corners[in.vertex_index % 6u];
    if (segment >= n_steps - 1) {
        return collapsed();
    }
    let index = segment + corner.x;

    // the body of ManimGL's loop, for this one point
    let t = f32(index) / f32(n_steps - 1);
    let point = point_on_quadratic(t, c0, c1, c2);
    let tangent = tangent_on_quadratic(t, c1, c2);
    let stroke_width = mix(sw0, sw2, t);
    let joint_color = mix(in.rgba0, in.rgba2, t);
    let inside_curve = (index > 0) && (index < n_steps - 1);
    var joint_angle: f32;
    if (index == 0) {
        joint_angle = -in.joint0;
    } else if (inside_curve) {
        joint_angle = 0.0;
    } else {
        joint_angle = in.joint2;
    }

    // emit_point_with_width, for this one corner
    var unit_normal: vec3<f32>;
    if (draw_flat) {
        unit_normal = in.unit_normal;
    } else {
        unit_normal = normalize(frame.camera_position - point);
    }
    var out: VertexOut;
    out.color = finalize_color(joint_color, point, unit_normal);
    let step = step_to_corner(point, tangent, unit_normal, joint_angle, inside_curve, draw_flat, in.unit_normal);
    let aaw = max(mob.anti_alias_width * get_pixel_unit_size(), 1e-8);
    let dist_to_curve = f32(corner.y) * 0.5 * (stroke_width + aaw);
    out.position = project_point(point + dist_to_curve * step);
    out.half_width_to_aaw = 0.5 * stroke_width / aaw;
    out.dist_to_aaw = dist_to_curve / aaw;
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    var frag_color = in.color;
    let signed_dist_to_region = abs(in.dist_to_aaw) - in.half_width_to_aaw;
    // ManimGL: smoothstep(0.5, -0.5, signed_dist) — reversed; the exact mirror.
    frag_color.a = frag_color.a * (1.0 - smoothstep(-0.5, 0.5, signed_dist_to_region));
    // On the depth prepass only actual ink (alpha ≥ 0.8) writes z, so the AA
    // apron never punches holes into ink drawn later.
    // A ribbon thinner than the antialiasing width never reaches 0.8 — it is
    // all apron — so an opaque face drawn later on its own plane would paint
    // over it whole. So the pixel the centre line crosses writes z as well:
    // the fragment whose centre lies within Z_CORE pixels of the curve, when
    // the stroke itself is opaque enough (the same 0.8, of the ribbon's own
    // alpha: a translucent stroke still writes nothing). A ribbon wide enough
    // that its ink already covers that band moves no byte. Inert when
    // Z_PASS == 0.
    if (Z_PASS > 0.5) {
        let ink = frag_color.a >= 0.8;
        let core = in.color.a >= 0.8 && abs(in.dist_to_aaw) * mob.anti_alias_width <= Z_CORE;
        if (!(ink || core)) {
            discard;
        }
    }
    return frag_color;
}
