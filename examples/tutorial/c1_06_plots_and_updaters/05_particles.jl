# Course 1 · 6.5 — Particles: DotCloud, TrueDot and the glow question
#
#     DotCloud(points; radius, color, opacity, glow_factor)
#     TrueDot(center) · GlowDot(center) · GlowDots(points)
#     set_radius! / set_radii! / scale_radii! / set_colors! / set_opacity!
#     make_3d!(dc)                       fake spheres: shading + z-buffer
#     get_points(dc)                     the LIVE vector — mutate it in place
#
# One cloud is ONE draw call, however many points: the geometry shader
# expands each point into a camera-facing disc, and glow is a per-fragment
# falloff (`pow(1−r, g)` on alpha) — no extra passes. The updater idiom is
# IN PLACE: `get_points(dc)` hands you the live vector on purpose, because
# the upload is per-frame anyway. A million particles step + upload in
# ~1.5 ms (numpy needs 6.59 ms for the same step).
#
# WHEN GLOW, WHEN BLOOM — measured, not guessed:
#   · sparse or volumetric clouds → `glow_factor`. It is 2–8× cheaper than
#     a Bloom pass and local density reads as brightness (the Lorenz short
#     in examples/scenes/10_lorenz_glow.jl is this recipe).
#   · densely OVERLAPPING dots (points packed on a curve) → the per-dot
#     alphas saturate and the halo flattens into a solid line; there, a
#     Bloom layer on the FINAL image keeps the neon look — at the price of
#     a fixed per-resolution pyramid.
#
#   julia --project=. examples/tutorial/c1_06_plots_and_updaters/05_particles.jl

using Janim

const PREVIEW_T = 2.5

function construct(scene)
    # Left: a ring of glowing particles orbiting — the in-place idiom.
    n = 900
    ring = GlowDots([Point3f(2.0cos(TAU * i / n) - 3.2, 1.6sin(TAU * i / n), 0)
                     for i in 1:n]; radius = 0.09)
    set_colors!(ring, color_gradient(["#1C758A", "#58C4DD", "#FFFF00"], n);
                opacity = 0.55)
    add_updater!(ring, (m, dt) -> begin
        pts = get_points(m)                      # the live vector
        for i in eachindex(pts)
            p = pts[i]
            x, y = p[1] + 3.2, p[2] / 0.8        # back to circle coords
            θ = atan(y, x) + 0.6dt               # orbit
            r = hypot(x, y)
            pts[i] = Point3f(r * cos(θ) - 3.2, 0.8r * sin(θ), 0)
        end
    end)

    # Right: make_3d! — the same primitive as little lit spheres.
    grid = DotCloud([Point3f(1.6 + 0.55i, -1.1 + 0.55j, 0)
                     for i in 0:4 for j in 0:4]; radius = 0.22,
                    color = "#E8A33D")
    make_3d!(grid)

    hud = TextMobject("one cloud, one draw call"; size = 0.4, color = GREY_A)
    to_corner!(hud, UL; buff = 0.35)
    fix_in_frame!(hud)

    add!(scene, ring, grid, hud)
    play!(scene, animate(grid, (rotate!, 0.5)); run_time = 2.0)
    wait!(scene, 3.0)
    println("ring: ", get_num_points(ring), " particles · grid: ",
            get_num_points(grid), " spheres · radius max ",
            round(get_radius(grid); digits = 2))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "05_particles.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
