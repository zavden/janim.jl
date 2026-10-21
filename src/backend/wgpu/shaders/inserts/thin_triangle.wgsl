// inserts/thin_triangle.wgsl — the thin-triangle cull of the fill.
//
// A straight side of a polygon, and every straight segment of a glyph or of
// an SVG path, is a quadratic whose handle sits at the chord's midpoint
// (ManimGL's `set_points_as_corners`). After any f32 transform the three
// points stop being exactly collinear — 7·10⁻⁶ px of bulge on a triangle's
// left side after a `move_to!`, 2.6·10⁻⁶ px on a rotated square, 3·10⁻⁷ px on
// a DejaVu glyph — below the f32 resolution of a window coordinate (ulp ≈
// 1.5·10⁻⁵ px at x ≈ 214). ManimGL's geometry stage emits that Loop-Blinn
// triangle regardless (it culls `verts[0] == verts[1]` and zero alpha,
// nothing else) and stencil/cover follow it. No GPU rasterises a triangle of
// zero area — but lavapipe snaps
// the vertices to its 1/256 px grid, where three float-collinear points
// can stop being collinear, rasterises the one sample that falls inside
// the micro-triangle and sets up its interpolation planes with the FLOAT
// area, which is 0: 1/0 = ∞ and 0·∞ = NaN in the interpolated colour, flat
// colours included. The cover paints that sample NaN and zeroes its
// count; on the composited route (rgba16float) the NaN survives the
// resolve and every effect (Sharpen spreads it over its 23×23 footprint); on
// the direct route (rgba8unorm) it lands as one black sample, a quarter of a
// pixel darker. An EXACT cull (`cross == 0`) catches none of them: the
// cross product is 4·10⁻⁷ u², not 0.
//
// So the rule is stated in PIXELS after the projection (as Z_CORE in
// stroke.wgsl): the triangle's height in window pixels — twice its area
// over its longest side — below `THIN_PX` collapses the vertex to
// (0, 0, 0, 1), the stroke's own way of dropping a surplus vertex, which no
// rasteriser draws. A triangle thinner than a fraction of a subpixel cannot
// change what a conforming rasteriser draws except through its own
// rounding: culling it moves no byte on RADV and restores the sample
// lavapipe fabricated. The three shaders of the fill apply it
// identically, after choosing `pts`: if one culled and another did not,
// the stencil count would stay standing and the NEXT mobject would paint
// there. A vertex behind the camera (w ≤ 0) decides nothing: the triangle
// is emitted as before. `THIN_PX` is substituted by pipelines.jl
// (`_FILL_THIN_PX`, 0 = ManimGL's two culls alone); its value is the
// measured one.

const THIN_PX: f32 = 0.001953125;

// window pixels of a clip-space point: NDC · (W/2, H/2), where W/2 is
// `frame_scale / (frame_rescale_factors.x · pixel_size)` — camera.jl's
// uniforms: rescale = 2 / frame_width_default, pixel_size = frame_width /
// width, frame_scale = frame_height / frame_height_default — so a layer
// with a camera of its own and a mobject fixed in frame read the same
// pixel. (`abs`: the y factor carries the flip's sign.)
fn window_px(clip: vec4<f32>) -> vec2<f32> {
    let half = frame.frame_scale / (abs(frame.frame_rescale_factors.xy) * frame.pixel_size);
    return clip.xy / clip.w * half;
}

// true when the projected triangle is thinner than THIN_PX (its height in
// window pixels), the three vertices in front of the camera
fn is_thin(pts: array<vec3<f32>, 3>) -> bool {
    if (THIN_PX <= 0.0) {
        return false;
    }
    let ca = project_point(pts[0]);
    let cb = project_point(pts[1]);
    let cc = project_point(pts[2]);
    if (ca.w <= 0.0 || cb.w <= 0.0 || cc.w <= 0.0) {
        return false;
    }
    let a = window_px(ca);
    let b = window_px(cb);
    let c = window_px(cc);
    let ab = b - a;
    let ac = c - a;
    let bc = c - b;
    let area2 = abs(ab.x * ac.y - ab.y * ac.x);
    let longest = max(max(length(ab), length(ac)), length(bc));
    if (longest <= 0.0) {
        return true;
    }
    return area2 < THIN_PX * longest;
}
