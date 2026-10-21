# Course 3 · 4.8 — Wave
#
#     Wave(; amplitude = 0.1, wavelength = 1.5, angle = 0.0, phase = 0.0)
#
# The uv are displaced by a sine: ripples, heat haze, water, a flag.
# `amplitude` and `wavelength` are in SCENE UNITS; `angle` is the direction
# the wave TRAVELS in, and the displacement is perpendicular to it.
#
# `phase` is a plain field with no clock behind it, so animating it from an
# updater is what makes the wave move. That is the whole design: no wall time,
# no internal counter, and the wave stays as deterministic as everything else.
#
# One numerical detail worth stealing: the phase is reduced mod 2π on its way
# to the shader. The sine is periodic but Float32 is not — an updater doing
# `phase += dt` for a minute would hand the shader a number big enough to lose
# resolution, and the ripples would go blocky. Normalising makes the period
# exact and minute ten as sharp as second one.
#
#   julia --project=. examples/tutorial/c3_04_glitch/08_wave.jl

using Janim

const PREVIEW_T = 2.4

"A grid: the shape that shows a displacement field best."
function grid(x)
    g = VGroup()
    for k in -6:6
        v = Line(Point3f(x + 0.28k, -1.8, 0), Point3f(x + 0.28k, 1.8, 0))
        set_stroke!(v; color = "#39D0FF", width = 2.0)
        add!(g, v)
    end
    for k in -6:6
        h = Line(Point3f(x - 1.7, 0.28k, 0), Point3f(x + 1.7, 0.28k, 0))
        set_stroke!(h; color = "#39D0FF", width = 2.0)
        add!(g, h)
    end
    return g
end

function construct(scene)
    title = TextMobject("animate the phase and the wave travels";
                        size = 0.42, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    across = Wave(; amplitude = 0.09, wavelength = 0.9, angle = 0.0)
    upwards = Wave(; amplitude = 0.09, wavelength = 0.9, angle = PI / 2)
    diagonal = Wave(; amplitude = 0.14, wavelength = 1.6, angle = PI / 4)

    labels = Mobject[]
    for (x, s) in ((-4.6, "angle = 0"), (0.0, "angle = pi/2"), (4.6, "angle = pi/4"))
        lab = TextMobject(s; size = 0.3, color = GREY_B)
        move_to!(lab, Point3f(x, -2.6, 0))
        push!(labels, lab)
    end

    use_composition!(scene, Composition(
        Layer(grid(-4.6); effects = [across]),
        Layer(grid(0.0); effects = [upwards]),
        Layer(grid(4.6); effects = [diagonal]),
        Layer(title, labels...);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        for (w, speed) in ((across, 2.4), (upwards, -1.8), (diagonal, 1.2))
            w.phase = mod(w.phase + speed * dt, TAU)   # keep it small, exactly
        end
        nothing
    end)
    add!(scene, clock)

    wait!(scene, 4.0)
    println("phases: ", round.((across.phase, upwards.phase, diagonal.phase);
                               digits = 3), " — all inside [0, 2pi)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "08_wave.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
