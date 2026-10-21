# Course 2 · 3.3 — The 3D camera
#
# There is no `ThreeDScene` to inherit from either: the same camera does 3D,
# and it is a QUATERNION camera (the controls traced from ManimGL).
#
#     reorient!(scene.frame, theta_deg, phi_deg, gamma_deg; center, height)
#     set_euler_angles! · increment_euler_angles!
#     get_theta / get_phi / get_gamma · get_view_matrix
#     get_focal_distance / set_focal_distance!   (what Dof focuses on)
#     get_implied_camera_location                (where the eye actually is)
#
# The angles, in ManimGL's convention: `theta` spins around the z axis (which
# way you are looking from), `phi` tilts down from the pole (0° = straight
# down onto the xy plane, 90° = edge on), `gamma` rolls the camera about its
# own axis.
#
# THE THREE SWITCHES that decide how a mobject behaves in 3D:
#
#   apply_depth_test!(m)   join the z-buffer. Off by default: in 2D, ORDER is
#                          the answer, and paying for depth would be a tax on
#                          every flat scene.
#   fix_in_frame!(m)       ignore the camera entirely — HUD, titles, legends.
#   set_shading!(m; reflectiveness, gloss, shadow)
#
# Animating the camera is animating a mobject, so it composes with everything:
# `AnimationGroup(animate(scene.frame, …), FadeIn(x))` is ordinary code.
#
#   julia --project=. examples/tutorial/c2_03_camera/03_camera_3d.jl

using Janim

const PREVIEW_T = 3.0

function construct(scene)
    reorient!(scene.frame, -35.0, 72.0; height = 9.0)

    axes = ThreeDAxes((-3.0, 3.0, 1.0), (-3.0, 3.0, 1.0), (-2.0, 2.0, 1.0);
                      width = 6.0, height = 6.0, depth = 4.0,
                      color = "#37506B", stroke_width = 2.0)
    apply_depth_test!(axes.group)

    ball = Sphere(; radius = 0.9, resolution = (81, 41), color = "#2C5F8A")
    shift!(ball, Point3f(-1.6, -1.2, 0.9) - get_center(ball))
    set_shading!(ball; reflectiveness = 0.5, gloss = 0.4, shadow = 0.35)
    apply_depth_test!(ball)

    ring = Torus(; r1 = 1.8, r2 = 0.28, resolution = (81, 41), color = "#E8A33D")
    shift!(ring, Point3f(1.4, 1.0, 0.4) - get_center(ring))
    apply_depth_test!(ring)

    # A flat mobject in a 3D world: without depth testing it draws in list
    # order and will happily sit "through" the sphere. With it, it is
    # occluded properly.
    blade = Rectangle(width = 4.0, height = 2.2)
    set_fill!(blade; color = "#7FDD58", opacity = 0.55); set_stroke!(blade; opacity = 0)
    rotate!(blade, PI / 2; axis = RIGHT)
    apply_depth_test!(blade)

    hud = VGroup()
    for s in ("apply_depth_test! → real occlusion",
              "fix_in_frame! → this text ignores the camera")
        add!(hud, TextMobject(s; size = 0.34, color = GREY_A))
    end
    arrange!(hud, DOWN; buff = 0.2, aligned_edge = LEFT)
    to_corner!(hud, UL; buff = 0.35)
    fix_in_frame!(hud)

    add!(scene, axes, blade, ball, ring, hud)
    wait!(scene, 0.6)

    # An orbit: theta sweeps, phi dips. One animation over `scene.frame`.
    play!(scene, animate(scene.frame, (reorient!, 55.0, 58.0);
                         rate_func = ease_in_out_sine); run_time = 2.6)
    println("eye at ", round.(Tuple(get_implied_camera_location(scene.camera));
                              digits = 2),
            " · focal distance ", round(get_focal_distance(scene.camera); digits = 3))

    # Zoom in 3D is the same verb as in 2D.
    play!(scene, animate(scene.frame, (scale_frame!, 0.65)); run_time = 1.4)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "03_camera_3d.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
