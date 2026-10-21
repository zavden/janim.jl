# Course 3 · 5.2 — Shutter angle
#
#     shutter = 0.5      the 180° shutter — cinema's default
#
# `shutter` is the FRACTION OF THE FRAME INTERVAL during which the shutter is
# open. Film cameras spell the same number as an angle on a rotating disc, so
# the two vocabularies map like this:
#
#     shutter 0.25 →  90°   crisp, staccato (Saving Private Ryan)
#     shutter 0.5  → 180°   the standard look
#     shutter 1.0  → 360°   maximum smear, one exposure touching the next
#
# The trade is between STROBING and MUSH. Too short and fast motion strobes
# (the eye sees discrete copies); too long and everything is soft. 180° is the
# default because it is the compromise a century of cinema settled on.
#
# Cost: `n` sub-exposures means the frame is DRAWN n times, so the render is
# roughly n× slower. The scene is simulated once either way.
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/02_shutter_angle.jl

using Janim

const PREVIEW_T = 1.0
const PREVIEW_MOTION = 12

function construct(scene)
    title = TextMobject("shutter is how long the exposure lasts";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    # Three identical pendulums at different heights, all moving fast. The
    # scene renders once per shutter value (see the footer), so the three
    # renders are what you compare — a single frame cannot show three
    # shutters at once, and pretending otherwise would be a lie.
    bars = VGroup()
    for (k, colour) in enumerate(("#39D0FF", "#FFD25E", "#FF3D8B"))
        r = Rectangle(width = 1.1, height = 0.7)
        set_fill!(r; color = colour, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(-5.0, 1.7 - 1.5(k - 1), 0))
        add!(bars, r)
    end
    add!(scene, bars)

    labels = VGroup()
    for (k, s) in enumerate(("slow", "medium", "fast"))
        t = TextMobject(s; size = 0.32, color = GREY_B)
        move_to!(t, Point3f(-6.2, 1.7 - 1.5(k - 1), 0))
        add!(labels, t)
    end
    add!(scene, labels)

    play!(scene, AnimationGroup(
              animate(bars[1], (move_to!, Point3f(5.0, 1.7, 0)); rate_func = linear),
              animate(bars[2], (move_to!, Point3f(5.0, 0.2, 0));
                      rate_func = ease_in_out_cubic),
              animate(bars[3], (move_to!, Point3f(5.0, -1.3, 0));
                      rate_func = ease_in_expo));
          run_time = 1.6)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    base = joinpath(@__DIR__, "..", "output", basename(@__DIR__))
    mkpath(base)
    for shutter in (0.25, 0.5, 1.0)
        out = joinpath(base, "02_shutter_$(replace(string(shutter), "." => "p")).mp4")
        Scene(construct; output = out, fps = 30, resolution = (854, 480),
              motion_blur = 12, shutter = shutter)
        println("→ ", out)
    end
end
