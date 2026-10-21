# Course 1 · 5.3 — The animations you reach for constantly
#
# Emphasis — "look HERE". None of them is a new mechanism; each is composition
# over Transform / ShowCreation / rate functions, which is the test that the
# primitives were the right ones:
#
#   Indicate(m; scale_factor, color)      grow and tint, and come back
#   Flash(point_or_mobject; num_lines)    the radial burst
#   Circumscribe(m; shape = :rectangle)   draw a box round it, rub it out
#   FocusOn(target; opacity)              the camera-iris gesture
#   Wiggle(m; n_wiggles)                  shake without moving anything
#
# Appearing and disappearing:
#
#   Write(m) / Unwrite(m)                 for text and formulas
#   DrawBorderThenFill(m)                 outline first, then the fill rises
#   ShowCreation(m) / Uncreate(m)         the stroke draws / retreats
#   GrowFromCenter/Point/Edge · GrowArrow · SpinInFromNothing · ShrinkToCenter
#
# And the two escape valves, for when nothing above fits:
#
#   UpdateFromAlphaFunc(m, (m, α) -> …)   whatever you can write as a function
#                                          of α. It takes NO snapshot, which
#                                          is what lets it drive a Surface or
#                                          a type of your own.
#   UpdateFromFunc(m, m -> …)             no α: for a mobject that depends on
#                                          another one being animated now.
#
# Detail worth having: `Uncreate` and `Unwrite` hand the mobject back INTACT.
# Manim leaves the collapsed husk behind, so re-adding it later shows nothing
# and the bug looks like the renderer's.
#
#   julia --project=. examples/tutorial/c1_05_utilities/03_useful_animations.jl

using Janim

const PREVIEW_T = 3.4

function construct(scene)
    title = TextMobject("emphasis is composition, not new machinery";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    targets = VGroup()
    for (txt, colour) in (("Indicate", "#58C4DD"), ("Flash", "#FFD25E"),
                          ("Circumscribe", "#7FDD58"), ("Wiggle", "#E8A33D"),
                          ("FocusOn", "#FF5E5E"))
        t = TextMobject(txt; size = 0.42, color = colour)
        add!(targets, t)
    end
    arrange!(targets, DOWN; buff = 0.45)
    move_to!(targets, 3.4 * LEFT + 0.3 * DOWN)
    add!(scene, targets)
    play!(scene, FadeIn(targets); run_time = 0.6)

    play!(scene, Indicate(targets[1]); run_time = 0.9)
    play!(scene, Flash(targets[2]; flash_radius = 0.9, num_lines = 16); run_time = 0.9)
    play!(scene, Circumscribe(targets[3]; buff = 0.15); run_time = 1.0)
    play!(scene, Wiggle(targets[4]); run_time = 1.2)
    play!(scene, FocusOn(targets[5]); run_time = 1.2)

    # The appearance family, on the right.
    shapes = VGroup()
    for m in (Square(side_length = 0.9), Circle(radius = 0.5),
              Triangle(radius = 0.6), Star(6; outer_radius = 0.55))
        set_fill!(m; color = "#2C5F8A", opacity = 1.0)
        set_stroke!(m; color = "#58C4DD", width = 3.0)
        add!(shapes, m)
    end
    arrange!(shapes, RIGHT; buff = 0.5)
    move_to!(shapes, 3.0 * RIGHT + 1.4 * UP)

    play!(scene, LaggedStart(GrowFromCenter(shapes[1]),
                             DrawBorderThenFill(shapes[2]),
                             SpinInFromNothing(shapes[3]),
                             ShowCreation(shapes[4]); lag_ratio = 0.35);
          run_time = 2.4)

    # The escape valve: a pulse nobody has a class for.
    pulse = Circle(radius = 0.8)
    set_stroke!(pulse; color = "#C77DFF", width = 4.0); set_fill!(pulse; opacity = 0)
    move_to!(pulse, 3.0 * RIGHT + 1.4 * DOWN)
    add!(scene, pulse)
    play!(scene, UpdateFromAlphaFunc(pulse, function (m, a)
              r = 0.35 + 0.55 * sin(3PI * a)^2
              become!(m, begin
                  c = Circle(radius = r)
                  set_stroke!(c; color = "#C77DFF", width = 4.0, opacity = 1 - 0.6a)
                  set_fill!(c; opacity = 0)
                  move_to!(c, 3.0 * RIGHT + 1.4 * DOWN)
                  c
              end)
          end); run_time = 2.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "03_useful_animations.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
