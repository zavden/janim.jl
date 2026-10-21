# Course 3 · 4.2 — A glitch that comes and goes
#
# `intensity` is a field of a mutable struct, so the whole technique is one
# updater. What makes it read as an ACCIDENT rather than as an animation is
# the SHAPE of that function of time:
#
#   · a glitch is short and violent — a spike, not a swell;
#   · it repeats irregularly;
#   · and it must return to EXACTLY zero, because zero is an exact no-op and
#     the picture has to come back clean.
#
# Irregular but deterministic: use the engine's own noise
# (`Janim._noise_hash`) keyed on the frame index, never `rand()`. A2 is what
# lets you scrub back to a glitch and see the same one.
#
#   julia --project=. examples/tutorial/c3_04_glitch/02_glitch_animated.jl

using Janim

const PREVIEW_T = 2.4

function construct(scene)
    title = TextMobject("a spike, not a swell — and it returns to exact zero";
                        size = 0.4, color = GREY_A)
    to_edge!(title, UP; buff = 0.3)

    photo = VGroup()
    for k in 0:6
        r = Rectangle(width = 1.5, height = 3.4 - 0.3k)
        set_fill!(r; color = color_gradient(["#39D0FF", "#FF3D8B"], 7)[k+1],
                  opacity = 1.0)
        set_stroke!(r; opacity = 0)
        move_to!(r, Point3f(-4.6 + 1.55k, 0.1, 0))
        add!(photo, r)
    end
    caption = TextMobject("BROADCAST"; size = 0.8, color = WHITE)
    move_to!(caption, 0.1 * UP)

    glitch = Glitch(; intensity = 0.0, seed = 11, rate = 2, slices = 22)
    meter = DecimalNumber(0.0; num_decimal_places = 2, size = 0.5, color = "#FF3D8B")
    move_to!(meter.group, Point3f(5.2, -2.7, 0))

    use_composition!(scene, Composition(
        Layer(photo, caption; effects = [glitch]),
        Layer(title, meter);
        background = (0.02f0, 0.03f0, 0.05f0, 1f0)))

    # The driver. `burst` is 1 for a few frames at irregular moments, decided
    # by a hash of the frame index — deterministic, so scrubbing shows the
    # same glitches.
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        window = scene.frames ÷ 7                     # a decision every 7 frames
        fire = Janim._noise_hash(1, 1, window, 4) > 0.72
        phase = (scene.frames % 7) / 7
        glitch.intensity = fire ? 0.9 * (1 - phase)^2 : 0.0   # spike, then exact 0
        set_number!(meter, glitch.intensity)
        nothing
    end)
    add!(scene, clock, meter)

    wait!(scene, 4.0)
    println("intensity at the end: ", glitch.intensity,
            " (0.0 exactly means the pass was skipped)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__),
                   "02_glitch_animated.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
