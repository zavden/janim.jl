# Course 3 · 2.8 — The neon recipe
#
# Glow is not one effect, it is a PIPELINE, and every piece is doing something
# specific:
#
#   1. `blend = :add` on the glowing layer. Additive light is what makes two
#      overlapping strokes brighter instead of one hiding the other — and it
#      is the only mode where a dark background contributes nothing.
#   2. `Bloom` with a LOW threshold on that layer, so the stroke's own colour
#      spills. Threshold high → only the brightest core glows; low → the whole
#      stroke does.
#   3. a dark background. Additive blending over a light background just
#      clips to white.
#   4. optionally, a second copy of the geometry, thicker and dimmer,
#      underneath — the cheap way to fake the tube behind the light.
#
# The pieces are all from this chapter; what this lesson teaches is the ORDER
# and why each one is there.
#
#   julia --project=. examples/tutorial/c3_02_blur_and_glow/08_glow_pipeline.jl

using Janim

const PREVIEW_T = 2.6

"The sign: a word and a frame around it, as stroked paths."
function sign_parts()
    word = TextMobject("JANIM"; size = 1.25)
    set_fill!(word; opacity = 0)                    # a tube, not a solid
    set_stroke!(word; color = "#FF3D8B", width = 5.0, opacity = 1.0)
    move_to!(word, 0.35 * UP)

    frame = RoundedRectangle(width = 6.4, height = 2.6, corner_radius = 0.4)
    set_fill!(frame; opacity = 0)
    set_stroke!(frame; color = "#39D0FF", width = 4.0)
    move_to!(frame, 0.35 * UP)
    return (word, frame)
end

function construct(scene)
    word, frame = sign_parts()

    # The "tube": the same geometry, thicker and dim, under the bright one.
    tube_w = copy(word); set_stroke!(tube_w; color = "#7A1240", width = 13.0)
    tube_f = copy(frame); set_stroke!(tube_f; color = "#0F4A66", width = 11.0)

    caption = TextMobject("blend = :add · Bloom(threshold = 0.2) · dark background";
                          size = 0.34, color = GREY_B)
    move_to!(caption, 2.5 * DOWN)

    flicker = Bloom(threshold = 0.2, intensity = 1.6, sigma = 0.12)

    use_composition!(scene, Composition(
        Layer(tube_w, tube_f),                                   # the glass
        Layer(word, frame; blend = :add, effects = [flicker]),   # the light
        Layer(caption);
        background = (0.015f0, 0.01f0, 0.03f0, 1f0))              # dark, on purpose
    )

    # A neon sign flickers: the intensity is a field, so this is one updater.
    # Deterministic on purpose — a hash of the frame index, never `rand()`.
    clock = VGroup()
    add_updater!(clock, function (m, dt)
        dt > 0 || return
        n = Janim._noise_hash(1, 1, scene.frames ÷ 3, 7)
        flicker.intensity = 1.2 + 0.9 * (n > 0.22 ? 1.0 : 0.15)
        nothing
    end)
    add!(scene, clock)

    wait!(scene, 3.0)
    println("bloom intensity at the end: ", round(flicker.intensity; digits = 2))
end

if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "..", "output", basename(@__DIR__), "08_glow_pipeline.mp4")
    mkpath(dirname(out))
    Scene(construct; output = out, fps = 30, resolution = (854, 480))
    println("→ ", out)
end
