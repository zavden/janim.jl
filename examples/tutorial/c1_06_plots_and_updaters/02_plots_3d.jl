# Course 1 · 6.2 — 3D plots
#
#     ThreeDAxes(x_range, y_range, z_range; width, height, depth)
#     c2p(ax, x, y, z)
#     Surface(uv_func; u_range, v_range, resolution, color, opacity, shading)
#
# A `Surface` is a uv mesh: `resolution` samples of `uv_func`, triangulated.
# Normals come from the ε-steps in u and v, and each one travels as a SECOND
# point (`d_normal_point = p + nudge·n̂`), so `shift!` and `rotate!` transform
# the normal for free and the shader recovers it by subtraction.
#
# The three 3D switches:
#
#   reorient!(scene.frame, theta_deg, phi_deg, gamma_deg; center, height)
#   apply_depth_test!(m)   join the z-buffer (real occlusion). 2D mobjects do
#                          NOT by default — in 2D, ordering IS the answer.
#   fix_in_frame!(m)       ignore the camera: HUD, titles, labels that must
#                          stay put while the world turns.
#   set_shading!(m; reflectiveness, gloss, shadow)
#
#   julia --project=. examples/tutorial/c1_06_plots_and_updaters/02_plots_3d.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    # The camera first: an isometric-ish view of the world.
    reorient!(scene.frame, -50.0, 68.0; height = 9.0)

    axes = ThreeDAxes((-3.0, 3.0, 1.0), (-3.0, 3.0, 1.0), (-2.0, 2.0, 1.0);
                      width = 6.0, height = 6.0, depth = 4.0,
                      color = "#37506B", stroke_width = 2.0)
    apply_depth_test!(axes.group)

    # z = sin(r)/r — the classic ripple, sampled as a uv patch.
    ripple = Surface((u, v) -> begin
                         r = hypot(u, v) + 1e-6
                         (u, v, 1.6 * sin(2r) / (1 + r))
                     end;
                     u_range = (-3.0, 3.0), v_range = (-3.0, 3.0),
                     resolution = (81, 81), color = "#2C5F8A", opacity = 0.92,
                     shading = (0.35, 0.35, 0.4))
    apply_depth_test!(ripple)

    # A parametric curve through the same space, placed with c2p.
    helix = VMobject()
    set_points_as_corners!(helix, [coords_to_point(axes, 2.2cos(t), 2.2sin(t),
                                                   0.35t - 1.6)
                                   for t in 0:0.05:(2TAU)])
    set_stroke!(helix; color = "#FFD25E", width = 4.0)
    apply_depth_test!(helix)

    # A HUD that ignores the camera entirely.
    hud = TextMobject("z = 1.6 sin(2r) / (1 + r)"; size = 0.42, color = GREY_A)
    to_corner!(hud, UL; buff = 0.4)
    fix_in_frame!(hud)

    add!(scene, axes, ripple, helix, hud)
    play!(scene, AnimationGroup(FadeIn(hud), ShowCreation(helix); lag_ratio = 0.3);
          run_time = 1.6)

    # Moving the camera is animating a mobject: `scene.frame` is one.
    play!(scene, animate(scene.frame, (reorient!, 25.0, 55.0)); run_time = 2.4)
    wait!(scene, 0.5)
    println("camera: theta = ", round(get_theta(scene.camera) / DEG; digits = 1),
            "° · phi = ", round(get_phi(scene.camera) / DEG; digits = 1), "°")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "02_plots_3d.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
