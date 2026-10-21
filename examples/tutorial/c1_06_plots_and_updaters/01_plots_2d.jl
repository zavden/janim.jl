# Course 1 · 6.1 — 2D plots
#
#     Axes(x_range, y_range; width, height, include_numbers)
#     NumberLine(x_range; width, unit_size, include_numbers, …)
#     NumberPlane(x_range, y_range; …)   ComplexPlane   PolarPlane
#
#     c2p(ax, x, y) / coords_to_point     data  → scene point
#     p2c(ax, point) / point_to_coords    point → data
#     plot(ax, f; x_range, n, color, discontinuities)
#     plot!(graph, ax, f)                 re-sample IN PLACE (the hot loop)
#     get_area(ax, f, x0, x1) · get_graph_label · get_v_line · get_h_line
#
# THE DESIGN DECISION, and everything else follows from it: the map is DERIVED
# FROM THE LIVE GEOMETRY, never stored as numbers. `number_to_point` reads the
# axis line's CURRENT endpoints, so `shift!(ax, 2RIGHT)`, `scale!(ax, 0.5)`
# and even `rotate!` move the whole coordinate world coherently — with no
# invalidation logic and nothing to keep in sync.
#
# `get_area` is worth a look too: it is the EXACT polygon under the curve,
# closed along the axis. Manim approximates it with a stack of rectangles
# because its fill cannot be trusted on a self-touching outline; ours is
# filled by real winding, so the exact polygon just works.
#
#   julia --project=. examples/tutorial/c1_06_plots_and_updaters/01_plots_2d.jl

using Janim

const PREVIEW_T = 5.0

function construct(scene)
    title = TextMobject("the map is read off the geometry"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    # Two details about the labels, both worth stealing:
    #   · pick a range whose TICKS are the numbers you want printed. With
    #     `(-3.5, 3.5, 1)` the ticks are -3.5, -2.5, … and at 0 decimals both
    #     -0.5 and 0.5 print "0" — two zeros, side by side.
    #   · `numbers_to_exclude = [0]` drops the origin label, which the two
    #     axes would otherwise write on top of each other.
    ax = Axes((-4.0, 4.0, 1.0), (-1.0, 1.0, 0.5); width = 7.4, height = 3.4,
              include_numbers = true, color = "#37506B", stroke_width = 2.0,
              label_size = 0.3, num_decimal_places = 1,
              numbers_to_exclude = [0.0])
    move_to!(ax, 2.6 * LEFT + 0.4 * DOWN)

    sine = plot(ax, sin; color = "#58C4DD", stroke_width = 4.0)
    area = get_area(ax, sin, 0.0, PI; color = "#58C4DD", opacity = 0.3)
    label = get_graph_label(ax, sine, "sin x"; x = 1.6, direction = UP, size = 0.4,
                            color = "#58C4DD")

    # A discontinuous function: the cut makes it two subpaths instead of the
    # vertical stroke a naive sampler draws across the jump.
    step_fn = x -> x < 0 ? -1.0 : 1.0
    steps = plot(ax, step_fn; x_range = (-2.4, 2.4), color = "#FF5E5E",
                 stroke_width = 3.0, discontinuities = [0.0])

    marker = Dot(c2p(ax, 1.0, sin(1.0)); radius = 0.09)
    set_fill!(marker; color = YELLOW)
    vline = get_v_line(ax, 1.0, sin(1.0); color = YELLOW)

    # TWO things about this `add!`.
    #
    # `ax` straight in: a coordinate object HAS a group of VMobjects and
    # delegates the whole scene interface to it — including
    # `set_stroke!`/`set_fill!`, which is what the fade animations call on
    # their copy. So `FadeIn(ax)` just works. One rule still stands: add the
    # SAME object you animate — adding both `ax` and `ax.group` would give
    # the scene two roots over one family and draw it twice.
    #
    # And note what is NOT here: `sine`, `area`, `label`, `steps` and `spiral`
    # are brought in by their own animations. `play!` adds the animation's
    # mobject for you, so adding it first only makes it visible BEFORE it is
    # created — the classic "why is it already there" in Manim too.
    add!(scene, ax, vline, marker)

    # A polar grid, to show the family is bigger than Axes.
    polar = PolarPlane(; r_max = 3.0, radius = 1.55, n_radii = 12, n_circles = 3,
                       color = "#37506B")
    move_to!(polar, 4.6 * RIGHT + 0.5 * DOWN)
    # `polar_to_point` reads the LIVE θ=0 radius, exactly like `c2p` reads
    # its axes (it does not answer in the plane's own frame, so you need not
    # add the centre by hand). The plane was just moved: the spiral lands
    # on it with no bookkeeping. The same pass gave every coordinate object
    # `get_center`/`get_width`/… by delegation.
    spiral = VMobject()
    set_points_as_corners!(spiral, [polar_to_point(polar, θ, 0.45θ)
                                    for θ in 0:0.05:TAU])
    set_stroke!(spiral; color = "#FFD25E", width = 3.0)
    add!(scene, polar)

    println("c2p(1, sin 1) = ", round.(Tuple(c2p(ax, 1.0, sin(1.0))); digits = 3))
    println("p2c of that point = ", round.(p2c(ax, c2p(ax, 1.0, sin(1.0))); digits = 6))

    play!(scene, AnimationGroup(FadeIn(ax), FadeIn(polar);
                                lag_ratio = 0.2); run_time = 1.0)
    play!(scene, ShowCreation(sine); run_time = 1.2)
    play!(scene, AnimationGroup(FadeIn(area), Write(label)); run_time = 0.8)
    play!(scene, ShowCreation(steps); run_time = 0.8)
    play!(scene, ShowCreation(spiral); run_time = 1.2)

    # The whole coordinate world moves as one, map included: the marker is
    # re-placed through c2p AFTER the axes have moved, and it lands right.
    play!(scene, animate(ax, (shift!, 0.5 * UP), (scale!, 0.9)); run_time = 1.2)
    move_to!(marker, c2p(ax, 1.0, sin(1.0)))
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_plots_2d.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
