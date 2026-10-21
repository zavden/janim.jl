# Course 2 · 3.1 — Moving the camera
#
# CE has a `MovingCameraScene` you must inherit from. Here every scene's
# camera is already animatable: `scene.frame` is a `CameraFrame`, a mobject
# that is a live VIEW onto the camera the scene renders with.
#
#     animate(scene.frame, (scale_frame!, 0.5))      zoom IN (factor < 1)
#     animate(scene.frame, (move_to!, 2 * RIGHT))    pan
#     animate(scene.frame, (set_frame_height!, 3.0)) "show me 3 units tall"
#     animate(scene.frame, (reorient!, -40.0, 70.0)) the 3D angles (lesson 3.3)
#     reset_frame!(scene.frame)
#
# It works because `CameraFrame` implements the four lines of the
# interpolation contract — nothing in `Transform` knows a camera exists. The
# orientation is interpolated with `quat_slerp`, so a rotating camera takes
# the short arc at constant angular speed instead of the wobble a
# component-wise lerp gives.
#
# ONE THING THAT DOES NOT MOVE WITH IT: `to_edge!` and `FRAME_X_RADIUS` speak
# about the NOMINAL frame (8 units tall), not about the current camera. Zoom
# in and a title placed with `to_edge!` does not follow — same as Manim. If
# you want it pinned to the screen, that is `fix_in_frame!`.
#
#   julia --project=. examples/tutorial/c2_03_camera/01_moving_camera.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    # A world with detail at two scales, so zooming has something to find.
    grid = NumberPlane((-8.0, 8.0, 1.0), (-5.0, 5.0, 1.0); width = 16.0,
                       height = 10.0, background_line_color = "#25405C",
                       faded_opacity = 0.15)
    add!(scene, grid.group)

    big = Circle(radius = 2.2)
    set_stroke!(big; color = "#58C4DD", width = 4.0); set_fill!(big; opacity = 0)
    move_to!(big, 1.5 * LEFT)

    tiny = VGroup()
    for k in 0:11
        θ = k * TAU / 12
        d = Dot(Point3f(2.6 + 0.28cos(θ), 0.9 + 0.28sin(θ), 0); radius = 0.035)
        set_fill!(d; color = "#FFD25E")
        add!(tiny, d)
    end
    label = TextMobject("detail"; size = 0.12, color = "#FFD25E")
    move_to!(label, Point3f(2.6, 0.45, 0))

    pinned = TextMobject("fix_in_frame!: stays put"; size = 0.4, color = GREY_A)
    to_corner!(pinned, UL; buff = 0.4)
    fix_in_frame!(pinned)

    floating = TextMobject("to_edge! is nominal: it does not follow";
                           size = 0.4, color = GREY_C)
    to_edge!(floating, DOWN; buff = 0.4)

    add!(scene, big, tiny, label, pinned, floating)
    wait!(scene, 0.5)

    # Zoom IN: a factor below 1 shrinks the frame, so the world grows.
    play!(scene, animate(scene.frame, (scale_frame!, 0.22),
                         (move_to!, Point3f(2.6, 0.9, 0)));
          run_time = 2.2)
    wait!(scene, 0.8)
    println("frame height now: ", round(get_height(scene.frame); digits = 3),
            " scene units (nominal is ", FRAME_HEIGHT, ")")

    # Pan while zoomed, then back. `reset_frame!` is the way home.
    play!(scene, animate(scene.frame, (shift!, Point3f(-0.9, -0.4, 0)));
          run_time = 1.2)
    play!(scene, animate(scene.frame, reset_frame!); run_time = 1.4)
    wait!(scene, 0.4)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_moving_camera.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
