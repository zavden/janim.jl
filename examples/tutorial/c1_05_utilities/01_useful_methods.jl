# Course 1 · 5.1 — The layout family
#
# ALWAYS place things relative to other things. Hand-written coordinates are
# the first thing to break when a label gets longer or a font changes.
#
#   next_to!(m, other, RIGHT; buff, aligned_edge, coor_mask)
#   align_to!(m, other, UP)        match one edge, touch only that axis
#   to_edge!(m, UP; buff) · to_corner!(m, UR; buff) · center!(m)
#   set_x!/set_y!/set_z!(m, v; direction)      · get_coord/set_coord!
#   match_x!/match_y!/match_z! · match_width!/match_height!/match_depth!
#   match_color!/match_style!
#   arrange!(group, DOWN; buff, aligned_edge)
#   arrange_in_grid!(group; n_rows, n_cols, buff, aligned_edge)
#   replace!(m, other; stretch) · surround!(m, other; buff)
#
# Two things to know:
#
#   · `to_edge!` uses the NOMINAL frame (FRAME_X_RADIUS/FRAME_Y_RADIUS), not
#     the current camera. Zooming the camera does not move where it lands —
#     same as Manim.
#   · `next_to!` takes a Mobject OR a point, and `aligned_edge` is the second
#     dimension: `next_to!(label, box, UP; aligned_edge = LEFT)` puts it above
#     AND flush left.
#
#   julia --project=. examples/tutorial/c1_05_utilities/01_useful_methods.jl

using Janim

const PREVIEW_T = 1.6

function construct(scene)
    title = TextMobject("place things relative to things"; size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)

    core = Rectangle(width = 2.6, height = 1.5)
    set_fill!(core; color = "#2C5F8A", opacity = 1.0); set_stroke!(core; opacity = 0)
    move_to!(core, 3.0 * LEFT)

    # next_to! in four directions, from the same call shape.
    tags = VGroup()
    for (d, txt) in ((UP, "UP"), (DOWN, "DOWN"), (LEFT, "LEFT"), (RIGHT, "RIGHT"))
        t = TextMobject(txt; size = 0.32, color = "#58C4DD")
        next_to!(t, core, d; buff = 0.22)
        add!(tags, t)
    end

    # aligned_edge: above AND flush with the left side.
    flush = TextMobject("aligned_edge = LEFT"; size = 0.28, color = "#FFD25E")
    next_to!(flush, core, UP; buff = 0.9, aligned_edge = LEFT)

    # A grid built by layout, not by coordinates.
    cells = VGroup()
    for k in 1:9
        s = Square(side_length = 0.55)
        set_fill!(s; color = "#37506B", opacity = 1.0)
        set_stroke!(s; color = "#0B0E14", width = 2.0)
        add!(cells, s)
    end
    arrange_in_grid!(cells; n_rows = 3, n_cols = 3, buff = 0.12)
    move_to!(cells, 3.4 * RIGHT + 0.4 * UP)

    # surround! — how SurroundingRectangle is built.
    halo = Rectangle(width = 1.0, height = 1.0)
    set_stroke!(halo; color = "#FF5E5E", width = 3.0); set_fill!(halo; opacity = 0)
    surround!(halo, cells; buff = 0.25, stretch = true)

    # A column laid out by arrange!, then pinned to a corner.
    column = VGroup()
    for s in ("arrange!", "to_corner!", "buff = 0.2")
        add!(column, TextMobject(s; size = 0.3, color = GREY_B))
    end
    arrange!(column, DOWN; buff = 0.16, aligned_edge = LEFT)
    to_corner!(column, DR; buff = 0.35)

    add!(scene, title, core, tags, flush, cells, halo, column)
    play!(scene, AnimationGroup(FadeIn(core), FadeIn(tags; shift = 0.2 * UP),
                                ShowCreation(halo), FadeIn(cells);
                                lag_ratio = 0.2); run_time = 2.0)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_useful_methods.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
