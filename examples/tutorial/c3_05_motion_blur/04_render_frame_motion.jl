# Course 3 · 5.4 — Blurring a single frame
#
#     render_frame_motion(construct, t; n = 8, shutter = 0.5, fps = 30,
#                         resolution = (854, 480), png = "f.png")
#
# The still-image sibling of `motion_blur`: it renders `n` sub-frames centred
# on `t` and averages them. Same picture as the video's frame at `t`, without
# encoding a video to look at one frame.
#
# It is the honest way to CHECK a blurred render before committing to it:
# an instantaneous frame cannot show the subject of a blur lesson, and this does
# (a lesson declares `PREVIEW_MOTION` for that).
#
# The sampling is symmetric about `t` (`t − dtf/2 + dtf(k+½)/n`), the same
# midpoint rule the animation timeline uses, so the average is centred rather
# than lagging half a shutter behind.
#
# Cost: n full renders. At n = 8 that is 8× one frame — which is nothing for a
# still and is exactly why you check a still first.
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/04_render_frame_motion.jl

using Janim

const PREVIEW_T = 1.0
const PREVIEW_MOTION = 16

function construct(scene)
    title = TextMobject("render_frame_motion: check the still, then render";
                        size = 0.4, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    wheel = VGroup()
    for k in 0:11
        spoke = Line(ORIGIN, Point3f(1.9cos(k * TAU / 12), 1.9sin(k * TAU / 12), 0))
        set_stroke!(spoke; color = color_gradient(["#39D0FF", "#FFD25E"], 12)[k+1],
                    width = 5.0)
        add!(wheel, spoke)
    end
    rim = Circle(radius = 1.95)
    set_stroke!(rim; color = GREY_A, width = 4.0); set_fill!(rim; opacity = 0)
    add!(wheel, rim)
    move_to!(wheel, 0.3 * DOWN)
    add!(scene, wheel)

    play!(scene, Rotating(wheel, 2TAU; run_time = 2.0, rate_func = linear);
          run_time = 2.0)
    wait!(scene, 0.3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    base = joinpath(@__DIR__, "..", "output", basename(@__DIR__))
    mkpath(base)
    # The instantaneous frame…
    render_frame(construct, 1.0; fps = 30, resolution = (854, 480),
                 png = joinpath(base, "04_still_sharp.png"))
    # …and the same instant, exposed for half a frame.
    render_frame_motion(construct, 1.0; n = 16, shutter = 0.5, fps = 30,
                        resolution = (854, 480),
                        png = joinpath(base, "04_still_blurred.png"))
    println("→ ", base, "/04_still_{sharp,blurred}.png — look at both")
end
