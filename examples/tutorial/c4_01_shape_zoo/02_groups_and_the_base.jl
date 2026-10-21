# Course 4 · 1.2 — Groups, the base type, and building a path by hand
#
# Three things live under every shape in lesson 1.1:
#
#   VMobject  the base: an EMPTY path plus a factory style. Build one by hand
#             with the path API and you have a shape the engine cannot tell
#             from a Circle.
#   VGroup    a parent of VMobjects. Styling it styles the family.
#   Group     a parent of ANYTHING — a Surface, a ValueTracker, a camera
#             frame. It moves and animates like a VGroup, and like manim's
#             Group: the verbs recurse into the members that can take them,
#             and a member that cannot (a ValueTracker has no position) is
#             left alone rather than throwing. What VGroup gives on top is
#             STYLE: `set_fill!` on a Group has nothing generic to set.
#
# `Mobject` is the abstract supertype the three share, and `VMobject(:Tag; …)`
# is the raw constructor the shape zoo is written on — the extension seam
# (`vmob` is an alias of it).
#
#   julia --project=. examples/tutorial/c4_01_shape_zoo/02_groups_and_the_base.jl

using Janim

const PREVIEW_T = 1.2

function construct(scene)
    title = TextMobject("a path built by hand is a first-class shape";
                        size = 0.4, color = GREY_A)
    to_edge!(title, UP; buff = 0.25)

    # ── a VMobject built one segment at a time ────────────────────────────
    hand = VMobject(; color = YELLOW, stroke_width = 4.0)
    start_new_path!(hand, Point3f(-2, -1, 0))
    add_line_to!(hand, Point3f(-1, 1, 0))
    add_quadratic_bezier_to!(hand, Point3f(0, 2, 0), Point3f(1, 1, 0))
    add_arc_to!(hand, Point3f(2, -1, 0), -TAU / 6)
    shift!(hand, 3.2 * LEFT + 0.6 * UP)

    # a second subpath in the same mobject: one shape, two contours
    add_subpath!(hand, get_points(Circle(radius = 0.35, arc_center = ORIGIN)))

    # ── the same points, described three ways ─────────────────────────────
    corners = VMobject(; color = TEAL, stroke_width = 3.0)
    set_points_as_corners!(corners, [Point3f(-1, -1, 0), Point3f(0, 1, 0),
                                     Point3f(1, -1, 0), Point3f(1.6, 0.6, 0)])
    smooth_one = copy(corners)
    set_points_smoothly!(smooth_one, [Point3f(-1, -1, 0), Point3f(0, 1, 0),
                                      Point3f(1, -1, 0), Point3f(1.6, 0.6, 0)])
    set_stroke!(smooth_one; color = PINK)
    jagged = copy(smooth_one)
    make_jagged!(jagged)
    set_stroke!(jagged; color = ORANGE)
    smoothed = copy(corners)
    make_smooth!(smoothed)
    set_stroke!(smoothed; color = GREEN)

    lines = VGroup(corners, smooth_one, jagged, smoothed)
    arrange!(lines, DOWN; buff = 0.25)
    move_to!(lines, Point3f(2.6, 0.4, 0))
    scale!(lines, 0.75)

    # a VGroup takes the setters of a single mobject and passes them down
    set_stroke!(lines; width = 3.0)

    # Group holds anything at all — here a VMobject and a point cloud
    cloud = GlowDots(Point3f[Point3f(0.35cos(t), 0.35sin(t), 0)
                             for t in range(0, TAU; length = 24)];
                     radius = 0.06, color = GOLD)
    # Group moves as one, exactly like VGroup — a cloud and a shape together
    sq = Square(side_length = 0.9)
    mixed = Group(sq, cloud)
    move_to!(mixed, Point3f(0, -2.6, 0))

    note = TextMobject("is_smooth: " * string(is_smooth(smoothed)) *
                       "   ·   subpaths: " * string(length(get_subpaths(hand))) *
                       "   ·   VMobject(:Custom) is the seam";
                       size = 0.26, color = GREY_B)
    to_edge!(note, DOWN; buff = 0.3)

    raw = VMobject(:Custom; color = MAROON_B, stroke_width = 2.0)
    set_points_by_ends!(raw, Point3f(-1, 0, 0), Point3f(1, 0, 0); path_arc = TAU / 4)
    move_to!(raw, Point3f(-3.2, -2.4, 0))

    add!(scene, title, note)
    play!(scene, ShowCreation(hand), ShowCreation(lines; lag_ratio = 0.1);
          run_time = 1.4)
    # a Group cannot be animated as one — its members can
    add!(scene, cloud)
    play!(scene, FadeIn(sq), ShowCreation(raw); run_time = 0.8)
    # …and animates as one: an animation of FUNCTIONS over the whole container
    play!(scene, animate(mixed, (shift!, 0.3 * RIGHT)); run_time = 0.4)
    wait!(scene, 0.4)
end
