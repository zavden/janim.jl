# Course 3 · 5.1 — Motion blur
#
#     Scene(construct; output = …, motion_blur = 8, shutter = 0.5)
#     janim render scene.jl --motion-blur 8,0.5
#
# Each frame becomes the average of `n` EXPOSURES inside the shutter, with the
# scene state ADVANCED between them. So it is not a directional smear applied
# to a picture: it is the real thing a camera does, and it smears every object
# along its own path — curves, rotations and updater-driven motion included.
#
#   motion_blur   sub-exposures per frame. `n ≤ 1` is an exact no-op: the
#                 frame loop takes exactly the branch it always took, so a
#                 scene without blur costs nothing.
#   shutter       the fraction of the frame interval the shutter is open.
#                 0.5 is cinema's 180° shutter (lesson 5.2).
#
# USE IT for animations, text, graphs and camera moves. Do NOT use it over
# integrated physics — lesson 5.5 measures why.
#
# This file is rendered WITH blur by its footer; a single instantaneous frame
# cannot show the point, so `PREVIEW_MOTION` asks for a blurred still instead.
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/01_motion_blur_basics.jl

using Janim

const PREVIEW_T = 1.2
const PREVIEW_MOTION = 12          # ← sub-exposures for a blurred still

function construct(scene)
    title = TextMobject("each frame is the average of n exposures";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.35)
    add!(scene, title)

    # Fast linear motion: the classic case.
    slider = Square(side_length = 0.9)
    set_fill!(slider; color = "#39D0FF", opacity = 1.0); set_stroke!(slider; opacity = 0)
    move_to!(slider, Point3f(-5.2, 1.6, 0))

    # Rotation: a directional blur could not do this one.
    spinner = VGroup()
    for k in 0:2
        r = Rectangle(width = 2.2, height = 0.22)
        set_fill!(r; color = "#FFD25E", opacity = 1.0); set_stroke!(r; opacity = 0)
        rotate!(r, k * PI / 3)
        add!(spinner, r)
    end
    move_to!(spinner, Point3f(-2.5, -1.3, 0))

    # A curved path: every point follows its own arc.
    orbiter = Dot(ORIGIN; radius = 0.24)
    set_fill!(orbiter; color = "#FF3D8B")
    ring = Circle(radius = 1.5)
    move_to!(ring, Point3f(3.2, -1.0, 0))
    set_stroke!(ring; color = "#25405C", width = 2.0)

    add!(scene, slider, spinner, ring, orbiter)

    play!(scene, AnimationGroup(
              animate(slider, (move_to!, Point3f(5.2, 1.6, 0)); rate_func = linear),
              Rotating(spinner, 3TAU; run_time = 2.0),
              MoveAlongPath(orbiter, ring; rate_func = linear));
          run_time = 2.0)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "01_motion_blur_basics.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (1920, 1080),
          motion_blur = 12, shutter = 0.5)
    println("→ ", out)
end
