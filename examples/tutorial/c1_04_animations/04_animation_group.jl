# Course 1 · 4.4 — Composing animations in time
#
#     AnimationGroup(anims...; lag_ratio = 0, run_time = -1)
#     LaggedStart(anims...; lag_ratio = 0.05)     # the same thing, named
#     Succession(anims...)                        # lag_ratio = 1, and LAZY
#
# The time algebra is one line:
#
#     start[k+1] = interpolate(start[k], end[k], lag_ratio)
#
# so lag 0 = all at once, lag 1 = strictly one after another, small lag = a
# cascade. `run_time = -1` means "as long as the last one needs".
#
# WHY `Succession` IS ITS OWN TYPE and not just lag_ratio = 1: it begins each
# animation when its turn comes. `AnimationGroup` begins them ALL at the
# start, and since `begin!` is where an animation snapshots its endpoints,
# chaining two animations over the SAME mobject in an AnimationGroup would
# snapshot the second one's start before the first one had run.
#
#   julia --project=. examples/tutorial/c1_04_animations/04_animation_group.jl

using Janim

const PREVIEW_T = 2.0

"Six squares in a row at height `y`, in one colour."
function bar(y, colour)
    g = VGroup()
    for k in 0:5
        s = Square(side_length = 0.6)
        set_fill!(s; color = colour, opacity = 1.0); set_stroke!(s; opacity = 0)
        move_to!(s, Point3f(-3.2 + 0.8k, y, 0))
        add!(g, s)
    end
    return g
end

function construct(scene)
    title = TextMobject("start[k+1] = lerp(start[k], end[k], lag_ratio)";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    together = bar(1.6, "#58C4DD")
    lagged   = bar(0.4, "#E8A33D")
    chained  = bar(-0.8, "#7FDD58")
    for (g, txt, y) in ((together, "AnimationGroup (lag 0)", 1.6),
                        (lagged, "LaggedStart (lag 0.15)", 0.4),
                        (chained, "Succession (lag 1)", -0.8))
        lab = TextMobject(txt; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(4.6, y, 0))
        add!(scene, lab)
    end

    # The same six FadeIns, composed three ways, all in 2.4 s.
    fades(g) = [FadeIn(s; shift = 0.4 * DOWN) for s in g.submobjects]
    play!(scene, AnimationGroup(
              AnimationGroup(fades(together)...; lag_ratio = 0.0),
              LaggedStart(fades(lagged)...; lag_ratio = 0.15),
              Succession(fades(chained)...));
          run_time = 2.4)
    wait!(scene, 0.4)

    # Succession over ONE mobject, which is where its laziness earns its keep:
    # each step snapshots the state the previous step left behind.
    trav = Dot(Point3f(-3.2, -2.2, 0); radius = 0.18)
    set_fill!(trav; color = "#FF5E5E")
    add!(scene, trav)
    play!(scene, Succession(
              animate(trav, (shift!, 3.0 * RIGHT)),
              animate(trav, (shift!, 1.2 * UP)),
              animate(trav, (scale!, 2.0)));
          run_time = 2.4)
    println("the dot ended at ", round.(Tuple(get_center(trav)); digits = 2))
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "04_animation_group.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
