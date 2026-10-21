# Course 2 · 5.2 — Translating a ManimGL scene
#
# Janim's engine is modelled on ManimGL, so this direction is the closer one:
# the rate functions ARE GL's (`smooth` is its quintic, not CE's sigmoid), the
# arc geometry has GL's 16 components, `Arrow` is one closed contour like GL's
# and not CE's tip-as-a-child, and the camera controls were traced from
# `scene.py`.
#
#   class Demo(Scene):                          function construct(scene)
#       def construct(self):
#           self.frame.set_height(6)              set_frame_height!(scene.frame, 6)
#           tex = Tex(R"\int_0^1 x^2 dx")         tex = Tex(raw"\int_0^1 x^2 dx")
#           self.play(Write(tex))                 play!(scene, Write(tex))
#           self.play(self.frame.animate           play!(scene, animate(scene.frame,
#                     .scale(0.5))                        (scale_frame!, 0.5)))
#           self.embed()                          live("this_file.jl")
#
# WHAT IS DIFFERENT, and it is short:
#
#   1. `self.embed()` (the IPython terminal in the middle of a render) becomes
#      `live("scene.jl")` — a window with Revise, where editing the file shows
#      up in ~80 ms. Space pauses, `,`/`.` step, `←`/`→` jump a second,
#      `[`/`]` jump an animation, PgUp/PgDn jump a checkpoint.
#   2. `checkpoint_paste()` becomes `checkpoint!(scene, "label")` plus
#      `janim render scene.jl --from label`. It is anchored to the CLI instead
#      of to an editor, and the snapshot INVALIDATES itself when the code
#      before the mark changes (manimgl trusts you and will serve stale state).
#   3. GL's shaders are per-mobject; Janim's effects are per LAYER, which is a
#      compositor and not a renderer feature (course 3).
#   4. `always_redraw(lambda: …)` is `always_redraw(() -> …)` and behaves the
#      same: rebuild every frame, adopt with `become!`.
#
#   julia --project=. examples/tutorial/c2_05_from_manim/02_from_manimgl.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    # self.frame.set_height(7)
    set_frame_height!(scene.frame, 7.0)

    # tex = Tex(R"\int_0^1 x^2\,dx = \frac{1}{3}")
    # NOTE the height: the frame was set to 7 units, so the visible range is
    # ±3.5 — and an integral with limits is over 2 units tall on its own.
    tex = Tex(raw"\int_0^1 x^2\,dx = \frac{1}{3}"; size = 0.75)
    move_to!(tex, 2.0 * UP)

    plane = NumberPlane((-4.0, 4.0, 1.0), (-2.0, 2.0, 1.0); width = 8.0, height = 3.6,
                        background_line_color = "#25405C", faded_opacity = 0.12)
    move_to!(plane.group, 1.1 * DOWN)

    # tracker = ValueTracker(0.2); dot = always_redraw(lambda: Dot(...))
    t = ValueTracker(0.2)
    dot = always_redraw() do
        x = get_value(t)
        d = Dot(coords_to_point(plane, x, x^2 - 1.0); radius = 0.11)
        set_fill!(d; color = "#FFD25E")
        d
    end
    curve = plot(plane.axes, x -> x^2 - 1.0; x_range = (-1.6, 1.6),
                 color = "#58C4DD", stroke_width = 4.0)

    add!(scene, plane.group, curve, tex, t, dot)

    # A checkpoint: everything before it can be skipped with `--from`, and it
    # is the anchor `janim states` reports on.
    checkpoint!(scene, "after_setup")

    play!(scene, Write(tex); run_time = 1.4)
    play!(scene, ShowCreation(curve); run_time = 1.0)
    play!(scene, animate(t, (set_value!, 1.55)); run_time = 1.6)

    # self.play(self.frame.animate.scale(0.55).move_to(dot))
    play!(scene, animate(scene.frame, (scale_frame!, 0.55),
                         (move_to!, get_center(dot))); run_time = 1.6)
    wait!(scene, 0.5)
    play!(scene, animate(scene.frame, reset_frame!); run_time = 1.0)
    println("checkpoints recorded in this run: ",
            [label for (label, _) in scene.checkpoint_frames])
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_from_manimgl.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
    println("live preview:  bin/janim preview ", @__FILE__)
end
