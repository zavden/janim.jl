# Course 1 · 4.3 — `animate`: the method-call form
#
# In CE/GL this is `self.play(m.animate.shift(RIGHT).rotate(PI))` — about half
# of all `play` calls. Python gets there with a chainable proxy that records
# method calls. Julia has no equivalent worth the machinery, and Janim
# uses no macros until the function falls short. So:
#
#     animate(m, (shift!, 2 * RIGHT), (rotate!, TAU / 4); run_time = 2)
#     animate(m, center!)                    # a bare function, no arguments
#     animate(vt, (set_value!, 10.0))        # works on a ValueTracker too
#     animate(scene.frame, (scale_frame!, 0.5))   # …and on the camera
#
# Under the hood it is exactly what Manim does: a `Transform` towards a COPY
# that has had those mutations applied. Three consequences worth internalising:
#
#   1. The copy is built inside `begin!`, not when you call `animate` — so
#      chaining inside a `Succession` snapshots the right state.
#   2. Calls are POSITIONAL. A keyword setter (`set_color!(m; color = …)`)
#      needs a one-line adapter, as in lesson 1.4.
#   3. It is a Transform, so it interpolates the END STATE, not the gesture.
#      `animate(m, (rotate!, PI))` moves every point along its chord — for a
#      real turn use `Rotate`/`Rotating`.
#
#   julia --project=. examples/tutorial/c1_04_animations/03_method_animations.jl

using Janim

const PREVIEW_T = 2.2

paint!(m, c) = set_color!(m; color = c)

function construct(scene)
    title = TextMobject("animate(m, (f, args...)) — the .animate idiom";
                        size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    box = RoundedRectangle(width = 1.8, height = 1.2, corner_radius = 0.25)
    set_fill!(box; color = "#2C5F8A", opacity = 1.0); set_stroke!(box; opacity = 0)
    move_to!(box, 4.0 * LEFT + 1.2 * UP)
    add!(scene, box)

    # Several mutations in ONE animation: they are applied in order to the
    # copy, and the result is what the mobject travels towards.
    play!(scene, animate(box, (shift!, 4.0 * RIGHT), (rotate!, TAU / 8),
                         (scale!, 1.3), (paint!, "#E8A33D"));
          run_time = 2.0)

    # A bare function with no arguments is fine.
    play!(scene, animate(box, center!); run_time = 1.0)

    # It is not limited to geometry: anything that fulfils the interpolation
    # contract works, including a number and the camera frame.
    vt = ValueTracker(0.0)
    counter = DecimalNumber(0.0; num_decimal_places = 2, size = 0.8, color = "#7FDD58")
    move_to!(counter.group, 2.0 * DOWN)
    add_updater!(counter, d -> set_number!(d, get_value(vt)))
    add!(scene, vt, counter)
    play!(scene, animate(vt, (set_value!, 12.5); rate_func = ease_out_cubic);
          run_time = 1.8)

    wait!(scene, 0.4)
    println("tracker: ", get_value(vt), " · counter shows: ", get_value(counter))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "03_method_animations.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
