# Course 3 · 4.4 — A television losing sync
#
# `CRT`'s `roll` is a vertical offset with a dark sync bar at the seam.
# Animate it and the picture rolls — the thing an old set does when the
# vertical hold slips.
#
# Note what is NOT there: `CRT` declares no `current_frame` field, so the
# frame clock never touches it. It has no internal notion of time at all —
# the motion comes entirely from you writing to `roll`. That is a good
# illustration of the effect contract: `_tick!` fills in only what asks for it,
# and an effect that does not ask stays a pure function of its fields.
#
# The consequence worth having: a rolling television is still deterministic
# and still scrub-able, because `roll` is a function of `scene.t`, which
# advances by exactly 1/fps.
#
#   julia --project=. examples/tutorial/c3_04_glitch/04_crt_roll.jl

using Janim

const PREVIEW_T = 2.6

function construct(scene)
    bars = VGroup()
    for (k, c) in enumerate(("#FFFFFF", "#FFFF00", "#00FFFF", "#00FF00",
                             "#FF00FF", "#FF0000", "#0000FF"))
        r = Rectangle(width = 1.3, height = 4.4)
        set_fill!(r; color = c, opacity = 1.0); set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(-3.9 + 1.3(k - 1), 0.3, 0))
        add!(bars, r)
    end
    label = TextMobject("VERTICAL HOLD"; size = 0.42, color = BLACK)
    move_to!(label, Point3f(0, -1.6, 0))
    plate = Rectangle(width = 4.4, height = 0.7)
    set_fill!(plate; color = "#DDDDDD", opacity = 1.0); set_stroke!(plate; opacity = 0)
    move_to!(plate, Point3f(0, -1.6, 0))

    tube = CRT(; scanlines = 200, scan_depth = 0.4, curvature = 0.2, roll = 0.0)

    use_composition!(scene, Composition(
        Layer(bars, plate, label; effects = [tube]);
        background = (0.02f0, 0.02f0, 0.03f0, 1f0)))

    # Losing sync: the roll accelerates, then settles. `mod` keeps the number
    # small so a long scene does not lose precision.
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        speed = 0.15 + 0.5 * max(0.0, sin(0.7 * scene.t))
        tube.roll = mod(tube.roll + speed * dt, 1.0)
        nothing
    end)
    add!(scene, clock)

    wait!(scene, 4.0)
    println("roll at the end: ", round(tube.roll; digits = 3),
            " — a plain field, no internal clock")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "04_crt_roll.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
