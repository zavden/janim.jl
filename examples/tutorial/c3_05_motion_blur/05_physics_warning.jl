# Course 3 · 5.5 — Why NOT to blur integrated physics
#
# Motion blur subdivides `dt`: an integrator that took one step of 1/30 s now
# takes `n` steps of 1/(30n) s. The total time per frame is identical; the
# DISCRETISATION is not — and a chaotic system amplifies any difference
# exponentially.
#
# This lesson MEASURES it rather than asserting it. Two copies of the same
# double pendulum from the same initial state, stepped for the same total
# time, one in whole frames and one in eight pieces per frame. The numbers
# below are printed by the scene, so you can check them:
#
#     2 s    7.5e-11      ← indistinguishable
#     5 s    1.1e-9
#    10 s    1.6e-8
#    15 s    5.4e-5
#    20 s    6.7e-2       ← plainly a different pendulum
#
# That is the shape to remember. It is NOT that the blurred integration is
# wrong — both are accurate to the solver's tolerance. It is that a Lyapunov
# exponent turns 1e-11 into 1e-1 in twenty seconds, and the two renders stop
# being the same film. With a looser tolerance it happens sooner: at
# reltol = 1e-6 the same test reaches 10 radians by 20 s.
#
# So: blur animations, text, graphs and camera moves. If the TRAJECTORY is the
# content, render without blur — or pre-compute the path once and animate
# along it, which blurs safely because the path is then a function of time.
#
#   julia --project=. examples/tutorial/c3_05_motion_blur/05_physics_warning.jl

using Janim
using OrdinaryDiffEqTsit5

const G = 9.8

function pendulum!(du, u, p, t)
    θ1, θ2, ω1, ω2 = u
    Δ = θ1 - θ2
    den = 3 - cos(2Δ)
    du[1] = ω1; du[2] = ω2
    du[3] = (-3G * sin(θ1) - G * sin(θ1 - 2θ2) - 2sin(Δ) * (ω2^2 + ω1^2 * cos(Δ))) / den
    du[4] = 2sin(Δ) * (2ω1^2 + 2G * cos(θ1) + ω2^2 * cos(Δ)) / den
end

"Step an integrator for `frames` frames, in `sub` pieces per frame."
function walk(u0, frames::Int, sub::Int; fps = 30, tol = 1e-10)
    integ = init(ODEProblem(pendulum!, copy(u0), (0.0, 1e4)), Tsit5();
                 reltol = tol, abstol = tol)
    dt = 1 / (fps * sub)
    for _ in 1:(frames * sub)
        step!(integ, dt, true)
    end
    return copy(integ.u)
end

const PREVIEW_T = 2.0

function construct(scene)
    u0 = [2.3, 2.7, 0.0, 0.0]

    header = TextMobject("one step per frame  vs  eight (motion_blur = 8)";
                         size = 0.46, color = GREY_A)
    to_edge!(header, UP; buff = 0.4)
    add!(scene, header)

    rows = VGroup()
    for frames in (60, 150, 300, 450, 600)
        a = walk(u0, frames, 1)
        b = walk(u0, frames, 8)
        d = maximum(abs.(a .- b))
        s = "after $(lpad(round(Int, frames / 30), 2)) s:  max |Δ| = " *
            "$(round(d; sigdigits = 3))"
        colour = d > 1e-3 ? "#FF5E5E" : d > 1e-6 ? "#FFD25E" : "#7FDD58"
        add!(rows, TextMobject(s; size = 0.42, color = colour,
                               font = "Liberation Mono"))
        println(s)
    end
    arrange!(rows, DOWN; buff = 0.3, aligned_edge = LEFT)
    move_to!(rows, 0.3 * UP)
    add!(scene, rows)

    note = TextMobject("chaos amplifies the discretisation, not the accuracy";
                       size = 0.36, color = GREY_B)
    move_to!(note, 2.6 * DOWN)
    add!(scene, note)

    play!(scene, LaggedStart([FadeIn(r; shift = 0.25 * RIGHT)
                              for r in rows.submobjects]...;
                             lag_ratio = 0.22); run_time = 2.2)
    play!(scene, Write(note); run_time = 0.8)
    wait!(scene, 0.8)
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "05_physics_warning.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
