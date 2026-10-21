# Course 1 · 4.2 — Animations as objects
#
# An animation is a VALUE. You build it, you can hold it, pass it around, put
# it inside a group, and hand it to `play!` later — it does not run until
# something drives its three-act life cycle:
#
#     begin!(a)                 snapshot the start, align the structures, α=0
#     interpolate!(a, α) × N    the rate function is applied INSIDE
#     finish!(a)                exact α=1 and cleanup
#
# `play!` makes exactly those three calls. So does `Timeline`, so does
# `render_frame`, so does the daemon — which is why an animation never needs
# to know who is driving it.
#
# Everything with a capital letter in this list is one of these values:
#
#   Transform · ReplacementTransform · TransformFromCopy · FadeTransform
#   FadeIn · FadeOut · ShowCreation/Create · Uncreate
#   Write · Unwrite · DrawBorderThenFill
#   GrowFromCenter/Point/Edge · GrowArrow · SpinInFromNothing · ShrinkToCenter
#   Rotate · Rotating · MoveAlongPath
#   Indicate · Flash · Circumscribe · FocusOn · Wiggle
#   AnimationGroup · Succession · LaggedStart · TransformMatchingTex
#   UpdateFromAlphaFunc · UpdateFromFunc      ← the escape valves
#
# Two of them are worth singling out. `Transform` snapshots BOTH ends inside
# `begin!`, not when you build it — which is what makes chaining inside a
# `Succession` capture the right states. And `Rotating` is not a Transform:
# interpolating between two rotated states moves points along CHORDS, so a
# half-turned square would visibly shrink; `Rotating` re-applies the rotation
# to the start state each frame instead.
#
#   julia --project=. examples/tutorial/c1_04_animations/02_class_animations.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    title = TextMobject("an animation is a value you build";
                        size = 0.46, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    sq = Square(side_length = 1.4)
    set_fill!(sq; color = "#2C5F8A", opacity = 1.0); set_stroke!(sq; opacity = 0)
    move_to!(sq, 4.0 * LEFT + 0.8 * UP)

    ring = Circle(radius = 0.75)
    set_stroke!(ring; color = "#58C4DD", width = 5.0); set_fill!(ring; opacity = 0)
    move_to!(ring, 1.3 * LEFT + 0.8 * UP)

    star = Star(5; outer_radius = 0.9)
    set_fill!(star; color = "#FFD25E", opacity = 1.0); set_stroke!(star; opacity = 0)
    move_to!(star, 1.5 * RIGHT + 0.8 * UP)

    arrow = Arrow(Point3f(3.2, 0.2, 0), Point3f(5.2, 1.4, 0))
    set_fill!(arrow; color = "#7FDD58")

    # Build them all first — nothing has happened yet.
    plan = [ShowCreation(ring), GrowFromCenter(star), GrowArrow(arrow),
            FadeIn(sq; shift = 0.5 * DOWN)]
    println("built ", length(plan), " animations, total run_time = ",
            sum(get_run_time, plan), " s — none of them has run")

    # …and now hand them over, one after another.
    for a in plan
        play!(scene, a; run_time = 0.7)
    end

    # Rotating vs Transform, side by side: same half-turn, different paths.
    left = Square(side_length = 1.2)
    set_fill!(left; color = "#E8A33D", opacity = 1.0); set_stroke!(left; opacity = 0)
    move_to!(left, 2.2 * LEFT + 1.7 * DOWN)
    right = copy(left)
    move_to!(right, 2.2 * RIGHT + 1.7 * DOWN)
    target = copy(right); rotate!(target, PI)
    for (m, txt) in ((left, "Rotating (arcs)"), (right, "Transform (chords)"))
        lab = TextMobject(txt; size = 0.3, color = GREY_C)
        next_to!(lab, m, DOWN; buff = 0.3)
        add!(scene, lab)
    end
    add!(scene, left, right)
    play!(scene, AnimationGroup(Rotating(left, PI; run_time = 2.0),
                                Transform(right, target; run_time = 2.0));
          run_time = 2.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_class_animations.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
