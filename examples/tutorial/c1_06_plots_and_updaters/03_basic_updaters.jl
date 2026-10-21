# Course 1 · 6.3 — Updaters
#
# An updater is a function the scene calls once per frame:
#
#     add_updater!(m, (m, dt) -> …)      the dt form (time-based)
#     add_updater!(m, m -> …)            the no-dt form (state-based)
#
# Which one you get is decided by ARITY: the engine asks whether a two-
# argument method exists. Registration calls it once with dt = 0, which is why
# an integrator inside an updater must guard with `dt > 0 &&` (course 2).
#
# The three companions:
#
#     ValueTracker(x)     a mobject with no points whose state is one number.
#                         Animatable, so `animate(vt, (set_value!, 10))` works.
#     DecimalNumber(x)    that number as glyphs; `set_number!` rebuilds them
#                         and RE-CENTRES, so 9.9 → 10.0 does not jump sideways.
#     always_redraw(f)    `f()` builds a mobject from scratch every frame and
#                         the result is adopted with `become!` — so the scene,
#                         the compositor and any group keep the SAME identity.
#
# THE RULE that costs an afternoon if you do not know it: a mobject whose
# POINTS are created inside an updater must be born with its final style. New
# points re-stamp the factory style, so styling it after the fact is undone on
# the next frame. `always_redraw` and `TracedPath` handle it for you.
#
#   julia --project=. examples/tutorial/c1_06_plots_and_updaters/03_basic_updaters.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("one function, called every frame"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    ax = Axes((0.0, 6.5, 1.0), (-1.2, 1.2, 0.5); width = 6.4, height = 2.6,
              color = "#37506B", stroke_width = 2.0)
    move_to!(ax, 2.6 * LEFT + 0.6 * DOWN)
    add!(scene, ax)

    # The tracker drives everything else in this scene.
    t = ValueTracker(0.3)
    add!(scene, t)

    curve = plot(ax, sin; color = "#37506B", stroke_width = 2.5)
    add!(scene, curve)

    # always_redraw: the chord is rebuilt from the tracker every frame. Note
    # that the mobject is built COMPLETE (points and style) inside `f`, which
    # is exactly the rule above, made automatic.
    tangent = always_redraw() do
        x = get_value(t)
        p = c2p(ax, x, sin(x))
        d = 0.9
        l = Line(c2p(ax, x - d, sin(x) - d * cos(x)),
                 c2p(ax, x + d, sin(x) + d * cos(x)))
        set_stroke!(l; color = "#FFD25E", width = 3.5)
        l
    end
    add!(scene, tangent)

    # A dot with a dt-updater of its own: it reads the tracker, so it needs
    # no dt at all — the no-dt form is the honest signature here.
    dot = Dot(ORIGIN; radius = 0.11)
    set_fill!(dot; color = "#FF5E5E")
    add_updater!(dot, m -> move_to!(m, c2p(ax, get_value(t), sin(get_value(t)))))
    add!(scene, dot)

    # A live readout. `add_updater!` on a DecimalNumber hands YOU the number.
    readout = DecimalNumber(0.0; num_decimal_places = 2, size = 0.7, color = "#58C4DD")
    move_to!(readout.group, Point3f(4.6, 1.4, 0))
    add_updater!(readout, d -> set_number!(d, cos(get_value(t))))
    caption = TextMobject("slope = cos x"; size = 0.34, color = GREY_B)
    move_to!(caption, Point3f(4.6, 0.85, 0))
    add!(scene, readout, caption)

    # A trail, added AFTER what it follows and layered with set_z_index!.
    trail = TracedPath(() -> get_center(dot); stroke_color = "#FF5E5E",
                       stroke_width = 2.5, time_traced = 3.0)
    add!(scene, trail)
    set_z_index!(trail, -1)

    play!(scene, animate(t, (set_value!, 6.2); rate_func = smooth); run_time = 4.0)
    wait!(scene, 0.5)
    println("tracker ended at ", round(get_value(t); digits = 3),
            " · readout shows ", round(get_value(readout); digits = 3))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_basic_updaters.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
