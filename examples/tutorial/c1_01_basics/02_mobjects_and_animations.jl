# Course 1 · 1.2 — Mobjects and animations
#
# A MOBJECT is geometry plus style; it does not know about time. An ANIMATION
# is a function of α ∈ [0,1] that mutates a mobject; it does not know about the
# scene. `play!` is the only thing that knows about both.
#
# Two ways in, and the difference matters:
#
#   add!(scene, m)              m is on screen from now on, unanimated
#   play!(scene, FadeIn(m))     m is put on screen BY the animation
#
# `play!` adds the animation's mobject for you, so the second form needs no
# `add!`. And a "remover" (FadeOut, Uncreate, Unwrite) takes it back out.
#
#   julia --project=. examples/tutorial/c1_01_basics/02_mobjects_and_animations.jl

using Janim

const PREVIEW_T = 3.2

function construct(scene)
    label = TextMobject("mobject = geometry + style"; size = 0.5, color = GREY_A)
    to_edge!(label, UP; buff = 0.5)
    add!(scene, label)                       # on screen, no animation

    circle = Circle(radius = 1.1)
    set_fill!(circle; color = BLUE, opacity = 1.0)
    set_stroke!(circle; color = WHITE, width = 4.0)
    shift!(circle, 3.2 * LEFT)

    square = Square(side_length = 2.0)
    set_fill!(square; color = "#E8A33D", opacity = 1.0)
    set_stroke!(square; opacity = 0)

    triangle = Triangle(radius = 1.3)
    set_fill!(triangle; color = GREEN, opacity = 1.0)
    set_stroke!(triangle; opacity = 0)
    shift!(triangle, 3.2 * RIGHT)

    # 1. ShowCreation draws the outline as if by hand.
    play!(scene, ShowCreation(circle); run_time = 1.0)

    # 2. FadeIn: no `add!` needed — `play!` puts the mobject in the scene.
    play!(scene, FadeIn(square; shift = 0.6 * UP); run_time = 0.8)

    # 3. Transform morphs one shape into another. It leaves you holding
    #    `square`, now wearing the triangle's shape — see lesson 1.5.
    play!(scene, Transform(square, triangle); run_time = 1.2)

    # 4. wait! is not "nothing happens": it is frames of scene time, and
    #    updaters keep running during it (lesson 6.3).
    wait!(scene, 0.6)

    # 5. FadeOut is a REMOVER: when it ends, the scene no longer holds it.
    play!(scene, FadeOut(square); run_time = 0.8)
    println("mobjects left in the scene: ", length(scene.mobjects))
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_mobjects_and_animations.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
