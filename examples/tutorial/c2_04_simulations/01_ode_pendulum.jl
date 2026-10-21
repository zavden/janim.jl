# Course 2 · 4.1 — Simulations: a real integrator inside an updater
#
# This is the only-in-Julia part. SciML's solvers are ordinary packages, so
# the physics in an Janim scene can be the same code you would use for
# research — not a hand-rolled Euler step.
#
#     integ = init(ODEProblem(f!, u0, tspan), Tsit5(); reltol, abstol)
#     add_updater!(m, (m, dt) -> (dt > 0 && step!(integ, dt, true); …))
#
# FOUR RULES, all of them paid for:
#
#   1. KEEP THE INTEGRATOR OUTSIDE the updater and `step!` it by dt. Building
#      it inside would re-start the simulation every frame.
#   2. GUARD WITH `dt > 0`. Registration calls the updater once with dt = 0.
#   3. ONE integrator drives everything. Two "identical" pendulums are two
#      integrations, and a chaotic system separates them all by itself — you
#      would be looking at the divergence, not at what you meant to show.
#   4. DO NOT use motion blur over integrated physics. Subdividing dt makes
#      the solver take n small steps instead of one big one; the total time is
#      the same and the trajectory is not (measured: ~1e-2 for a non-linear
#      system, five orders worse than a linear one).
#
# The energy drift of this double pendulum with Tsit5 at reltol = 1e-10 is
# ~3·10⁻¹⁰ over the whole scene — printed at the end, so you can check rather
# than believe.
#
#   julia --project=. examples/tutorial/c2_04_simulations/01_ode_pendulum.jl

using Janim
using OrdinaryDiffEqTsit5

const G = 9.8
const L = 1.15

"The double pendulum, equal masses and equal lengths (in units where L = 1)."
function pendulum!(du, u, p, t)
    θ1, θ2, ω1, ω2 = u
    Δ = θ1 - θ2
    den = 3 - cos(2Δ)
    du[1] = ω1
    du[2] = ω2
    du[3] = (-3G * sin(θ1) - G * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
    du[4] = 2sin(Δ) * (2ω1^2 + 2G * cos(θ1) + ω2^2 * cos(Δ)) / den
end

"Total energy — the number that says whether the integration is trustworthy."
function energy(u)
    θ1, θ2, ω1, ω2 = u
    T = 0.5 * (2ω1^2 + ω2^2 + 2ω1 * ω2 * cos(θ1 - θ2))
    V = -G * (2cos(θ1) + cos(θ2))
    return T + V
end

const PREVIEW_T = 5.0

function construct(scene)
    title = TextMobject("Tsit5 inside an updater"; size = 0.44, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)
    add!(scene, title)

    pivot = Point3f(0, 1.6, 0)
    u0 = [2.3, 2.7, 0.0, 0.0]
    integ = init(ODEProblem(pendulum!, copy(u0), (0.0, 1e4)), Tsit5();
                 reltol = 1e-10, abstol = 1e-10)          # RULE 1: outside
    state = Ref((pivot, pivot))

    rod = VMobject()
    set_stroke!(rod; color = "#C8D2DC", width = 3.0)      # born with its style
    add_updater!(rod, function (m, dt)
        if dt > 0                                          # RULE 2
            step!(integ, dt, true)
            θ1, θ2 = integ.u[1], integ.u[2]
            a = pivot + Point3f(L * sin(θ1), -L * cos(θ1), 0)
            state[] = (a, a + Point3f(L * sin(θ2), -L * cos(θ2), 0))
        end
        set_points_as_corners!(m, [pivot, state[][1], state[][2]])
        nothing
    end)

    bob1 = Dot(pivot; radius = 0.09); set_fill!(bob1; color = "#C8D2DC")
    bob2 = Dot(pivot; radius = 0.11); set_fill!(bob2; color = "#FFD25E")
    add_updater!(bob1, m -> move_to!(m, state[][1]))       # RULE 3: they READ
    add_updater!(bob2, m -> move_to!(m, state[][2]))       # the one integrator

    # Add the trail AFTER what it follows, and layer it with set_z_index!:
    # `bring_to_back!` would put its updater first and cost a whole frame of
    # lag. `smooth = true` rounds the polyline through the same samples.
    add!(scene, rod, bob1, bob2)
    trail = TracedPath(() -> state[][2]; stroke_color = "#58C4DD",
                       stroke_width = 2.6, time_traced = 4.0, smooth = true)
    add!(scene, trail)
    set_z_index!(trail, -1)

    readout = DecimalNumber(0.0; num_decimal_places = 9, size = 0.4, color = GREY_B)
    move_to!(readout.group, Point3f(0, -3.3, 0))
    add_updater!(readout, d -> set_number!(d, energy(integ.u) - energy(u0)))
    caption = TextMobject("energy drift"; size = 0.32, color = GREY_C)
    move_to!(caption, Point3f(0, -2.9, 0))
    add!(scene, readout, caption)

    wait!(scene, 8.0)
    println("energy drift after ", round(scene.t; digits = 2), " s: ",
            energy(integ.u) - energy(u0))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "01_ode_pendulum.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
