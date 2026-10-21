# Course 3 · 6 — CAPSTONE: the field and the chaos, without a word on screen
#
# The engine's example 03 (`examples/03_field_and_chaos.jl`) is a 62-second
# tour with formulas, captions and three acts. This is the same machine with
# the words taken away: one double pendulum, a trail rounded by `make_smooth!`
# and nothing on screen but light. Everything it teaches is in this file's
# comments, which is where a capstone's explanation belongs.
#
# What is stacked here, and where each piece was taught:
#
#   the trail is a TracedPath(smooth = true)          course 1, lesson 6.3
#   the spotlight is an animated MASK following it     course 3, lesson 3.6
#   the trail glows on an :add layer with Bloom        course 3, lesson 2.8
#   the streamlines sit behind a per-layer Dof         course 3, lesson 2.7
#   the ending is an adjustment layer's blur           course 3, lesson 1.4
#   the physics is a real integrator in an updater     course 2, lesson 4.1
#
# THE ONE NEW THING, and it is the trap this scene exists to teach:
#
#   WITH A COMPOSITION MOUNTED, PUT THE SIMULATION IN A SCENE-LEVEL MOBJECT.
#
# `_update_all!` updates `scene.mobjects` FIRST and the layers' contents
# afterwards, in layer order. A trail that reads the pendulum's state must be
# updated AFTER the pendulum writes it — but the trail's layer has to sit
# BELOW the pendulum's to be drawn behind it, and those two orders are the
# same list. Driving the integrator from an invisible mobject added straight
# to the scene breaks the tie: the state is written before any layer runs, so
# every layer reads this frame's value and nothing lags.
#
# (The 2D version of the same trap — `bring_to_back!` costing a whole frame of
# lag — is course 1, lesson 1.6.)
#
#   julia --project=. examples/tutorial/c3_06_capstone/01_pendulum_smooth_masked.jl

using Janim
using OrdinaryDiffEqTsit5

const G = 9.8
const L = 1.25                       # arm length, scene units
const PIVOT = Point3f(0, 1.5, 0)

function pendulum!(du, u, p, t)
    θ1, θ2, ω1, ω2 = u
    Δ = θ1 - θ2
    den = 3 - cos(2Δ)
    du[1] = ω1; du[2] = ω2
    du[3] = (-3G * sin(θ1) - G * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
    du[4] = 2sin(Δ) * (2ω1^2 + 2G * cos(θ1) + ω2^2 * cos(Δ)) / den
end

const PREVIEW_T = 11.0

function construct(scene)
    # ── the cast ─────────────────────────────────────────────────────────
    background = Rectangle(width = 16.0, height = 9.0)
    set_fill!(background; color = "#080B12", opacity = 1.0)
    set_stroke!(background; opacity = 0)

    # the rotational field, integrated properly so the streamlines are circles
    lines = VGroup()
    for r in 0.8:0.5:3.6
        prob = ODEProblem((du, u, p, t) -> (du[1] = -u[2]; du[2] = u[1]),
                          [r, 0.0], (0.0, TAU))
        sol = solve(prob, Tsit5(); reltol = 1e-8, abstol = 1e-8, saveat = 0.06)
        v = VMobject()
        set_points_as_corners!(v, [Point3f(u[1], u[2], 0) for u in sol.u])
        set_stroke!(v; color = "#39D0FF", width = 3.0, opacity = 0.0)
        add!(lines, v)
    end

    # the grid nobody can see until the spotlight passes over it
    grid = VGroup()
    for x in -7.2:0.75:7.2
        l = Line(Point3f(x, -4.2, 0), Point3f(x, 4.2, 0))
        set_stroke!(l; color = "#2A3B55", width = 1.8)
        add!(grid, l)
    end
    for y in -4.0:0.75:4.0
        l = Line(Point3f(-7.2, y, 0), Point3f(7.2, y, 0))
        set_stroke!(l; color = "#2A3B55", width = 1.8)
        add!(grid, l)
    end
    spot = Circle(radius = 1.45, fill_opacity = 1.0)
    move_to!(spot, Point3f(99, 99, 0))        # parked: nothing is revealed yet

    # the pendulum
    rod = VMobject()
    set_stroke!(rod; color = "#C8D2DC", width = 3.2)      # final style at birth
    bob1 = Dot(PIVOT; radius = 0.10); set_fill!(bob1; color = "#C8D2DC", opacity = 0.0)
    bob2 = Dot(PIVOT; radius = 0.13); set_fill!(bob2; color = "#FFD25E", opacity = 0.0)

    # ── the simulation, driven from a SCENE-LEVEL mobject (see the header) ──
    integ = init(ODEProblem(pendulum!, [2.2, 2.65, 0.0, 0.0], (0.0, 1e4)), Tsit5();
                 reltol = 1e-10, abstol = 1e-10)
    state = Ref((PIVOT, PIVOT))
    running = Ref(false)

    physics = VGroup()                       # invisible, and in NO layer
    add_updater!(physics, function (m, dt)
        (running[] && dt > 0) || return
        step!(integ, dt, true)
        θ1, θ2 = integ.u[1], integ.u[2]
        a = PIVOT + Point3f(L * sin(θ1), -L * cos(θ1), 0)
        state[] = (a, a + Point3f(L * sin(θ2), -L * cos(θ2), 0))
        nothing
    end)
    add!(scene, physics)                     # ← updated BEFORE every layer

    add_updater!(rod, m -> set_points_as_corners!(m, [PIVOT, state[][1], state[][2]]))
    add_updater!(bob1, m -> move_to!(m, state[][1]))
    add_updater!(bob2, m -> move_to!(m, state[][2]))
    add_updater!(spot, m -> running[] && move_to!(m, state[][2]))

    # THE TRAIL: the same samples the pendulum visits, joined as a CURVE.
    # `smooth = true` runs make_smooth! over them each frame — it moves no
    # anchor, so the trail never invents a point the bob did not reach; it
    # only changes how the visits are joined up. Worth it exactly here, where
    # the tip moves far between one frame and the next.
    trail = TracedPath(() -> state[][2]; stroke_color = "#39D0FF",
                       stroke_width = 2.8, time_traced = 6.0, smooth = true)

    dream = Blur(0.001)                       # the adjustment layer's dial

    # ── the stack ────────────────────────────────────────────────────────
    use_composition!(scene, Composition(
        Layer(background),
        crop(grid; inside = spot, feather = 0.35),
        Layer(lines; effects = [Dof(get_focal_distance(scene.camera) - 1.4;
                                    aperture = 0.05, max_sigma = 2.0)]),
        Layer(trail; blend = :add,
              effects = [Bloom(threshold = 0.22, intensity = 1.6, sigma = 0.15)]),
        Layer(rod, bob1, bob2),
        Layer(; effects = [dream]);
        background = (0.02f0, 0.025f0, 0.04f0, 1f0)))

    # ── act 1 · the field (0 – 4 s) ──────────────────────────────────────
    appear(m, op) = Transform(m, (c = copy(m); set_stroke!(c; opacity = op); c))
    appear_fill(m, op) = Transform(m, (c = copy(m); set_fill!(c; opacity = op); c))

    play!(scene, LaggedStart([appear(l, 0.9) for l in lines.submobjects]...;
                             lag_ratio = 0.12); run_time = 3.2)
    wait!(scene, 0.6)

    # ── act 2 · the chaos (4 – 17 s) ─────────────────────────────────────
    play!(scene, AnimationGroup(appear(lines, 0.16),
                                appear_fill(bob1, 1.0), appear_fill(bob2, 1.0));
          run_time = 1.2)
    running[] = true
    wait!(scene, 12.0)

    # ── act 3 · the blur takes it (17 – 21 s) ────────────────────────────
    # Freeze the simulation BEFORE fading: an updater that keeps writing
    # points would re-stamp the factory style and the fade would show nothing.
    play!(scene, UpdateFromAlphaFunc(background, (m, a) ->
              (dream.sigma = 0.001 + 0.20a; nothing)); run_time = 1.6)
    running[] = false
    move_to!(spot, Point3f(99, 99, 0))        # park the spotlight again
    play!(scene, AnimationGroup(FadeOut(rod), FadeOut(bob1), FadeOut(bob2),
                                FadeOut(trail), appear(lines, 0.0));
          run_time = 1.8)
    play!(scene, UpdateFromAlphaFunc(background, (m, a) ->
              (dream.sigma = 0.20 - 0.199a; nothing)); run_time = 1.2)
    wait!(scene, 0.6)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "01_pendulum_smooth_masked.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 60, resolution = (1920, 1080))
    println("→ ", out)
end
