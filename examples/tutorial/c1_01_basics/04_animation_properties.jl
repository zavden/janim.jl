# Course 1 · 1.4 — Animation properties
#
# Every animation carries the same four dials (they live in `AnimBase`):
#
#   run_time    seconds. `play!(…; run_time = t)` overrides it.
#   rate_func   how α moves inside that time (lesson 4.1).
#   lag_ratio   the delay between the members of the animated mobject's
#               FAMILY: 0 = all together, 1 = strictly one after another.
#   remover     when true, the scene drops the mobject at the end (FadeOut).
#
# `lag_ratio` is the one people get wrong. On a single animation it staggers
# the CHILDREN of the mobject being animated. On an `AnimationGroup` it
# staggers the ANIMATIONS. Same word, two levels — both appear below.
#
# Second thing this lesson teaches: `animate(m, (f, args...))` calls `f`
# POSITIONALLY, so a keyword setter like `set_color!(m; color = …)` needs a
# one-line adapter. That is the whole trick.
#
#   julia --project=. examples/tutorial/c1_01_basics/04_animation_properties.jl

using Janim

const PREVIEW_T = 1.6

"The adapter: `animate` passes arguments positionally, `set_color!` wants a keyword."
paint!(m, c) = set_color!(m; color = c)

"A row of six dots at height `y`. Narrow on purpose: the animation below
scales the row by 1.5 about its own centre, and the labels live at x = 4.6."
function row(y)
    g = VGroup()
    for k in 0:5
        d = Dot(Point3f(-3.6 + 1.0k, y, 0); radius = 0.2)
        set_fill!(d; color = "#37506B")
        add!(g, d)
    end
    return g
end

function construct(scene)
    title = TextMobject("lag_ratio staggers a family"; size = 0.5, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    rows = [row(1.5), row(0.0), row(-1.5)]
    lags = [0.0, 0.15, 1.0]
    for (g, lag, y) in zip(rows, lags, (1.5, 0.0, -1.5))
        lab = TextMobject("lag_ratio = $lag"; size = 0.33, color = GREY_B)
        move_to!(lab, Point3f(4.6, y, 0))
        add!(scene, g, lab)
    end

    # The three rows animate for the SAME 3 seconds. Only the lag differs, so
    # what you are looking at is purely what lag_ratio does.
    play!(scene, AnimationGroup(
              [animate(g, (paint!, YELLOW), (scale!, 1.5); lag_ratio = lag)
               for (g, lag) in zip(rows, lags)]...);
          run_time = 3.0)
    wait!(scene, 0.4)

    # `remover`: FadeOut sets it, so the scene lets go of the mobject. Compare
    # `Uncreate`, which also hands the mobject back INTACT rather than as the
    # collapsed husk Manim leaves behind.
    play!(scene, AnimationGroup([FadeOut(g) for g in rows]...; lag_ratio = 0.2);
          run_time = 1.2)
    println("rows still in the scene: ",
            count(m -> m in rows, scene.mobjects), " of 3")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "04_animation_properties.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
