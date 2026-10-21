# Course 3 · 3.6 — The animated spotlight
#
# A mask's mobjects are updated like everything else, so a mask can FOLLOW
# something. That is the whole trick behind a spotlight: a hidden grid, a
# feathered circle chasing the subject, and the grid is revealed only where
# the circle is.
#
# Two practical notes:
#
#   · PARK THE SHAPE OFF SCREEN to start with (`move_to!(spot, (99, 99, 0))`).
#     A mask always cuts, so before the spotlight "turns on" you want its
#     coverage to be nowhere — and moving it away is cheaper and clearer than
#     animating its radius from zero.
#   · The masking shape is never drawn, so its colour does not matter; only
#     its alpha does. Give it `fill_opacity = 1.0` and forget about it.
#
#   julia --project=. examples/tutorial/c3_03_masks/06_animated_spotlight.jl

using Janim

const PREVIEW_T = 2.6

function construct(scene)
    title = TextMobject("the mask follows: a spotlight"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    # The hidden layer: a grid of numbers nobody can see until the light hits.
    hidden = VGroup()
    for i in 0:8, j in 0:4
        t = TextMobject(string((i * 5 + j) % 10); size = 0.42, color = "#7FDD58")
        move_to!(t, Point3f(-5.6 + 1.4i, 1.9 - 0.95j, 0))
        add!(hidden, t)
    end

    # The subject the light follows.
    ball = Circle(radius = 0.28)
    set_fill!(ball; color = "#FFD25E", opacity = 1.0); set_stroke!(ball; opacity = 0)
    move_to!(ball, Point3f(-4.5, 0, 0))

    spot = Circle(radius = 1.5, fill_opacity = 1.0)
    move_to!(spot, Point3f(99, 99, 0))          # parked: nothing is revealed
    add_updater!(spot, m -> move_to!(m, get_center(ball)))

    use_composition!(scene, Composition(
        crop(hidden; inside = spot, feather = 0.28),
        Layer(ball),
        Layer(title);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    # The updater is registered but the spotlight is parked, so the first
    # frames show nothing. Moving the ball is what turns it on.
    wait!(scene, 0.4)
    play!(scene, animate(ball, (move_to!, Point3f(4.6, 1.4, 0));
                         rate_func = ease_in_out_sine); run_time = 2.2)
    play!(scene, animate(ball, (move_to!, Point3f(-1.2, -1.7, 0));
                         rate_func = ease_in_out_sine); run_time = 1.8)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "06_animated_spotlight.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
