# Course 1 · 1.5 — Copies
#
# `copy(m)` is DEEP: points, style rows and the whole subtree. Two copies
# share nothing, so mutating one never reaches the other. (The single
# exception is documented and deliberate: an `ImageMobject`'s pixel array is
# shared, because a texture can be megabytes and it is treated as immutable.)
#
# Where copies show up whether you ask for them or not:
#
#   Transform(a, b)          builds a copy of `b` in `begin!` and morphs `a`
#                            into it — `b` is never mutated, and afterwards
#                            the scene still holds `a`, wearing b's shape.
#   ReplacementTransform     …but the scene ends up holding `b` instead.
#   TransformFromCopy(a, b)  `a` stays put; a copy of it flies to `b`.
#   animate(m, (f, x))       the target is `f` applied to a copy of `m`.
#
# The trap: adding the SAME mobject to the scene twice draws it twice, and
# with winding fill the overlap deepens instead of staying put. If you want
# two of something, copy it.
#
#   julia --project=. examples/tutorial/c1_01_basics/05_copies.jl

using Janim

const PREVIEW_T = 2.6

function construct(scene)
    title = TextMobject("copy is deep — Transform never mutates its target";
                        size = 0.48, color = GREY_A)
    to_edge!(title, UP; buff = 0.4)
    add!(scene, title)

    source = Square(side_length = 1.6)
    set_fill!(source; color = BLUE, opacity = 1.0)
    set_stroke!(source; opacity = 0)
    move_to!(source, 4.2 * LEFT)

    target = Circle(radius = 0.95)
    set_fill!(target; color = "#E8A33D", opacity = 1.0)
    set_stroke!(target; opacity = 0)
    move_to!(target, 4.2 * RIGHT)

    for (m, txt) in ((source, "source"), (target, "target"))
        lab = TextMobject(txt; size = 0.35, color = GREY_B)
        next_to!(lab, m, DOWN; buff = 0.3)
        add!(scene, lab)
    end
    add!(scene, source, target)

    # A copy is an independent mobject: painting it leaves the original alone.
    twin = copy(source)
    set_fill!(twin; color = GREEN)
    move_to!(twin, 1.6 * LEFT)
    play!(scene, FadeIn(twin); run_time = 0.6)
    println("source fill after painting the copy: ", get_color(source))

    # TransformFromCopy: the source survives, the copy is what flies. The
    # scene keeps the TARGET afterwards (the copy is scaffolding).
    play!(scene, TransformFromCopy(source, target); run_time = 1.6)
    wait!(scene, 0.4)

    # Plain Transform consumes what you hand it: `twin` is now circle-shaped
    # and sits where the circle is, and you are still holding `twin`.
    circle_2 = Circle(radius = 0.6)
    set_fill!(circle_2; color = GREEN, opacity = 1.0)
    set_stroke!(circle_2; opacity = 0)
    move_to!(circle_2, 1.6 * RIGHT)
    play!(scene, Transform(twin, circle_2); run_time = 1.2)
    println("twin is a ", tag(twin), " that now looks like a ", tag(circle_2),
            " — its tag never changes, only its points")
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_copies.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
