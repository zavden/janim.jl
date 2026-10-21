# Course 1 · 1.6 — Layers (draw order)
#
# The scene draws its list in order, and each mobject draws its family in DFS
# order. So "ordering" is REORDERING — there is no z-buffer in 2D (that is
# `apply_depth_test!`, and it belongs to 3D).
#
# Three tools, and the third one has a tooth:
#
#   add! order          last added draws on top
#   set_z_index!(m, z)  higher draws later; the sort is STABLE, so equal
#                       z-indices keep insertion order. Touches DRAWING only.
#   bring_to_front!/    moves the mobject in `scene.mobjects` — which is the
#   bring_to_back!      UPDATE order as well as the draw order.
#
# THE TOOTH: `bring_to_back!(scene, trail)` puts the trail's updater FIRST, so
# it samples the previous frame's position and lags exactly one frame behind
# what it follows (0.618 scene units for a point crossing a circle of radius 2
# at 20 fps). `set_z_index!(trail, -1)` gives
# the same picture with no lag. Prefer it whenever an updater reads another
# mobject's state.
#
#   julia --project=. examples/tutorial/c1_01_basics/06_layers.jl

using Janim

const PREVIEW_T = 2.0

"Three overlapping discs, left to right, added in the order given."
function stack(x)
    a = Circle(radius = 0.9); set_fill!(a; color = "#2C5F8A", opacity = 1.0)
    b = Circle(radius = 0.9); set_fill!(b; color = "#E8A33D", opacity = 1.0)
    c = Circle(radius = 0.9); set_fill!(c; color = GREEN, opacity = 1.0)
    for (m, dx) in ((a, -0.5), (b, 0.0), (c, 0.5))
        set_stroke!(m; color = BLACK, width = 3.0)
        move_to!(m, Point3f(x + dx, 0.3, 0))
    end
    return (a, b, c)
end

function construct(scene)
    title = TextMobject("draw order is list order"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    # Left: plain add! order — green last, so green on top.
    a1, b1, c1 = stack(-3.6)
    add!(scene, a1, b1, c1)

    # Right: the same three, added in the same order, but the BLUE one is
    # given a z-index so it lands on top. Nothing else changed.
    a2, b2, c2 = stack(3.6)
    add!(scene, a2, b2, c2)
    set_z_index!(a2, 1)

    for (x, txt) in ((-3.6, "add! order"), (3.6, "set_z_index!(blue, 1)"))
        lab = TextMobject(txt; size = 0.36, color = GREY_B)
        move_to!(lab, Point3f(x, -1.6, 0))
        add!(scene, lab)
    end

    # A moving dot with its trail, laid out the RIGHT way: the trail is added
    # AFTER the dot it follows (so it samples this frame's position) and sent
    # behind with set_z_index!, which does not touch the update order.
    path = Circle(radius = 0.55)
    move_to!(path, Point3f(0, -2.4, 0))
    dot = Dot(Point3f(0.55, -2.4, 0); radius = 0.11)
    set_fill!(dot; color = YELLOW)
    trail = TracedPath(() -> get_center(dot); stroke_color = YELLOW, stroke_width = 3.0)
    add!(scene, dot, trail)          # dot FIRST, trail after: no one-frame lag
    set_z_index!(trail, -1)          # …and behind, without reordering updaters

    play!(scene, MoveAlongPath(dot, path; rate_func = linear); run_time = 2.5)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "06_layers.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
